"""Ensemble model training for HomeValue."""

import numpy as np
from sklearn.ensemble import (  # type: ignore[import-untyped]
    ExtraTreesRegressor,
    RandomForestRegressor,
    StackingRegressor,
    VotingRegressor,
)
from sklearn.linear_model import ElasticNetCV, LassoCV, RidgeCV  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]

from ml_backend.config import Config
from ml_backend.models._identity import _IdentityPreprocessor

_ALLOWED_BASE_ESTIMATORS = (
    RandomForestRegressor,
    ExtraTreesRegressor,
    RidgeCV,
    LassoCV,
    ElasticNetCV,
)


def _validate_base_estimators(base_estimators: dict | None) -> None:
    """Validate base_estimators dict contains only allowed estimator types."""
    if base_estimators is None:
        return
    for key, est in base_estimators.items():
        if not isinstance(est, _ALLOWED_BASE_ESTIMATORS):
            allowed_names = [cls.__name__ for cls in _ALLOWED_BASE_ESTIMATORS]
            raise ValueError(
                f"base_estimators['{key}'] must be one of {allowed_names}, got {type(est).__name__}"
            )


def train_ensembles(
    X: np.ndarray,
    y: np.ndarray,
    config: Config,
    base_estimators: dict | None,
) -> dict[str, Pipeline]:
    """Train ensemble models wrapped with an identity preprocessing pipeline.

    Args:
        X: Preprocessed training features (n_samples, n_features).
        y: Training targets (n_samples,).
        config: ML pipeline configuration.
        base_estimators: Optional dict with keys "rf", "ridge", "enet" mapping to
            unfitted sklearn estimators (RandomForestRegressor, ExtraTreesRegressor,
            RidgeCV, LassoCV, ElasticNetCV). If None, only RandomForest and
            ExtraTrees are trained. If provided, must contain all three keys.

    Returns:
        Dict of fitted Pipelines keyed by model name:
        - "RandomForestRegressor"
        - "ExtraTreesRegressor"
        - "VotingRegressor" (if base_estimators provided)
        - "StackingRegressor" (if base_estimators provided)

    Raises:
        ValueError: If input validation fails or base_estimators is malformed.
    """
    if X.shape[0] == 0 or y.shape[0] == 0:
        raise ValueError("Training data must not be empty")
    if X.shape[0] != y.shape[0]:
        raise ValueError("X and y must have the same number of samples")
    if X.shape[1] == 0:
        raise ValueError("X must have at least one feature")
    if X.dtype.kind not in "biufc":
        raise ValueError("X must be numeric array")
    if not np.isfinite(X).all() or not np.isfinite(y).all():
        raise ValueError("Training data must contain only finite values")

    _validate_base_estimators(base_estimators)

    ensembles: dict[str, Pipeline] = {}

    # RandomForestRegressor
    rf = RandomForestRegressor(
        n_estimators=config.rf_n_estimators,
        max_features=config.rf_max_features,
        random_state=config.random_state,
        n_jobs=config.cv_n_jobs,
    )
    rf_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", rf)])
    rf_pipeline.fit(X, y)
    ensembles["RandomForestRegressor"] = rf_pipeline

    # ExtraTreesRegressor
    et = ExtraTreesRegressor(
        n_estimators=config.rf_n_estimators,
        max_features=config.rf_max_features,
        random_state=config.random_state,
        n_jobs=config.cv_n_jobs,
    )
    et_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", et)])
    et_pipeline.fit(X, y)
    ensembles["ExtraTreesRegressor"] = et_pipeline

    # VotingRegressor and StackingRegressor require base_estimators
    if base_estimators is not None:
        required_keys = {"rf", "ridge", "enet"}
        missing = required_keys - set(base_estimators.keys())
        if missing:
            raise ValueError(f"base_estimators missing required keys: {missing}")

        # VotingRegressor (soft voting is default for regressors)
        voting = VotingRegressor(
            estimators=[(name, base_estimators[name]) for name in ["rf", "ridge", "enet"]],
        )
        voting_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", voting)])
        voting_pipeline.fit(X, y)
        ensembles["VotingRegressor"] = voting_pipeline

        # StackingRegressor with RidgeCV as final estimator.
        # base_estimators must be UNFITTED — sklearn clones and fits them internally via CV.
        stacking = StackingRegressor(
            estimators=[(name, base_estimators[name]) for name in ["rf", "ridge", "enet"]],
            final_estimator=RidgeCV(alphas=config.ridge_alphas, cv=config.cv_folds),
            cv=config.cv_folds,
            n_jobs=config.cv_n_jobs,
        )
        stacking_pipeline = Pipeline(
            [("preprocessor", _IdentityPreprocessor()), ("model", stacking)]
        )
        stacking_pipeline.fit(X, y)
        ensembles["StackingRegressor"] = stacking_pipeline

    return ensembles
