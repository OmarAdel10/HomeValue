"""FastAPI router for training endpoint."""

import json
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException
from sklearn.ensemble import RandomForestRegressor  # type: ignore[import-untyped]
from sklearn.linear_model import ElasticNetCV, RidgeCV  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]

from ml_backend.config import Config
from ml_backend.data.loader import load_california_housing
from ml_backend.models import (
    train_baselines,
    train_ensembles,
    train_regularized,
    tune_gradient_boosting,
    tune_random_forest,
)
from ml_backend.models.evaluation import cross_validate_model, evaluate_model
from ml_backend.models.selection import save_model, select_best_model
from ml_backend.preprocessing import (
    build_preprocessing_pipeline,
    infer_feature_types,
    split_train_test,
)

router = APIRouter(prefix="/train", tags=["training"])


def _save_comparison(
    config: Config, all_models: dict[str, Any], X_test_enc: Any, y_test_np: Any
) -> list[dict]:
    """Evaluate all models and save comparison data."""
    from ml_backend.models.evaluation import evaluate_model

    comparison = []
    for name, pipeline in all_models.items():
        metrics = evaluate_model(pipeline, X_test_enc, y_test_np)
        cv_results = cross_validate_model(pipeline, X_test_enc, y_test_np, cv=Config().cv_folds)
        is_best = False  # Will be updated after best model selection
        comparison.append(
            {
                "model_name": name,
                "model": name,
                "rmse": metrics["rmse"],
                "mae": metrics["mae"],
                "r2": metrics["r2"],
                "cv_rmse": cv_results["cv_rmse_mean"],
                "cv_rmse_std": cv_results["cv_rmse_std"],
                "cv_std": cv_results["cv_rmse_std"],
                "is_best": is_best,
            }
        )

    config.ensure_dirs()
    comparison_path = config.models_dir / "model_comparison.json"
    with open(comparison_path, "w") as f:
        json.dump(comparison, f, indent=2)

    return comparison


def _update_best_in_comparison(config: Config, best_name: str) -> None:
    """Mark the best model in the saved comparison."""
    comparison_path = config.models_dir / "model_comparison.json"
    if comparison_path.exists():
        with open(comparison_path) as f:
            comparison = json.load(f)
        for m in comparison:
            m["is_best"] = m["model_name"] == best_name
        with open(comparison_path, "w") as f:
            json.dump(comparison, f, indent=2)


def save_training_artifact(
    preprocessor: Any,
    estimator: Any,
    config: Config,
) -> Path:
    """Bundle a fitted preprocessor with the best estimator and persist it.

    The inference API receives raw feature rows, so the artifact must expose
    the same preprocessing step that was used during training.
    """
    config.ensure_dirs()
    artifact = Pipeline(
        [
            ("preprocessing", preprocessor),
            ("model", estimator),
        ]
    )
    path = config.models_dir / "best_model.joblib"
    save_model(artifact, path)
    return path


def run_full_training_pipeline(config: Config | None = None) -> dict:
    """Run the complete training pipeline and return the best model metrics.

    This function:
    1. Loads California housing data
    2. Splits train/test
    3. Builds preprocessing pipeline
    4. Trains baselines, regularized, ensembles, and tuned models
    5. Selects best model by RMSE on test set
    6. Saves best model to disk
    7. Returns model name and metrics

    Args:
        config: Optional Config object (uses default if not provided).

    Returns:
        Dict with model name, test metrics, and CV RMSE.
    """
    if config is None:
        config = Config()

    # 1. Load data
    X, y = load_california_housing()

    # 2. Train/test split
    X_train, X_test, y_train, y_test = split_train_test(X, y, config)

    # Convert to numpy arrays for sklearn compatibility
    y_train_np = y_train.to_numpy()
    y_test_np = y_test.to_numpy()

    # 3. Build preprocessing pipeline
    numeric_features, categorical_features = infer_feature_types(X_train)
    preprocessor = build_preprocessing_pipeline(numeric_features, categorical_features)
    X_train_enc = preprocessor.fit_transform(X_train)
    X_test_enc = preprocessor.transform(X_test)

    all_models: dict[str, Any] = {}

    # 4. Train baselines
    baselines = train_baselines(X_train_enc, y_train_np, config)
    all_models.update(baselines)

    # 5. Train regularized models
    regularized = train_regularized(X_train_enc, y_train_np, config)
    all_models.update(regularized)

    # 6. Create UNFITTED base estimators for Voting/Stacking
    base_estimators = {
        "rf": RandomForestRegressor(
            n_estimators=config.rf_n_estimators,
            max_features=config.rf_max_features,
            random_state=config.random_state,
            n_jobs=config.cv_n_jobs,
        ),
        "ridge": RidgeCV(alphas=config.ridge_alphas, cv=config.cv_folds),
        "enet": ElasticNetCV(
            alphas=config.elasticnet_alphas,
            l1_ratio=config.elasticnet_l1_ratios,
            cv=config.cv_folds,
            max_iter=config.elasticnet_max_iter,
            random_state=config.random_state,
        ),
    }
    ensembles_with_base = train_ensembles(X_train_enc, y_train_np, config, base_estimators)
    all_models.update(ensembles_with_base)

    # 7. Hyperparameter tuning
    rf_tuned = tune_random_forest(X_train_enc, y_train_np, config)
    gb_tuned = tune_gradient_boosting(X_train_enc, y_train_np, config)
    all_models["RandomForestRegressor_Tuned"] = rf_tuned.best_estimator_
    all_models["GradientBoostingRegressor_Tuned"] = gb_tuned.best_estimator_

    # 8. Select best model by test RMSE
    best_name, best_pipeline = select_best_model(all_models, X_test_enc, y_test_np)

    # 9. Evaluate on test set
    test_metrics = evaluate_model(best_pipeline, X_test_enc, y_test_np)

    # 10. Cross-validation on best model
    cv_results = cross_validate_model(best_pipeline, X_train_enc, y_train_np, cv=config.cv_folds)

    # 11. Save comparison data for /model/comparison endpoint
    _save_comparison(config, all_models, X_test_enc, y_test_np)

    # 11. Save preprocessing + best estimator so /predict can accept raw features
    full_pipeline = save_training_artifact(preprocessor, best_pipeline, config)

    # 12. Update best model flag in comparison
    _update_best_in_comparison(config, best_name)

    return {
        "artifact": str(full_pipeline),
        "model": best_name,
        "metrics": test_metrics,
        "cv_rmse": cv_results["cv_rmse_mean"],
        "cv_rmse_std": cv_results["cv_rmse_std"],
    }


@router.post("")
async def train_model() -> dict:
    """Trigger full model training pipeline.

    Returns:
        Dict with best model name, test metrics, and CV RMSE.
    """
    try:
        config = Config()
        result = run_full_training_pipeline(config)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Training failed: {e}") from e


if __name__ == "__main__":
    import json

    result = run_full_training_pipeline(Config())
    print(json.dumps(result, indent=2, default=str))
