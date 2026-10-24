"""Tests for baseline models, evaluation metrics, and regularized models."""

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import ElasticNetCV, LassoCV, LinearRegression, RidgeCV
from sklearn.pipeline import Pipeline

from ml_backend.config import Config
from ml_backend.models.baselines import train_baselines
from ml_backend.models.evaluation import (
    cross_validate_model,
    cv_scores,
    evaluate_model,
    regression_metrics,
)
from ml_backend.models.regularized import train_regularized
from ml_backend.preprocessing import build_preprocessing_pipeline, infer_feature_types


def _housing_frame(n_rows: int = 50) -> pd.DataFrame:
    rng = np.random.default_rng(0)
    return pd.DataFrame(
        {
            "MedInc": rng.uniform(0.5, 15.0, n_rows),
            "HouseAge": rng.uniform(1.0, 52.0, n_rows),
            "AveRooms": rng.uniform(2.0, 10.0, n_rows),
            "AveBedrms": rng.uniform(0.5, 4.0, n_rows),
            "Population": rng.uniform(100.0, 5000.0, n_rows),
            "AveOccup": rng.uniform(1.0, 8.0, n_rows),
            "Latitude": rng.uniform(32.5, 42.0, n_rows),
            "Longitude": rng.uniform(-124.5, -114.0, n_rows),
        }
    )


def _target(n_rows: int = 50) -> pd.Series:
    rng = np.random.default_rng(1)
    return pd.Series(rng.uniform(0.5, 5.0, n_rows), name="MedHouseVal")


def _preprocessed_frame(n_rows: int = 50) -> tuple[pd.DataFrame, pd.Series]:
    """Create preprocessed features and target."""
    X = _housing_frame(n_rows)
    y = _target(n_rows)
    numeric, categorical = infer_feature_types(X)
    preprocessor = build_preprocessing_pipeline(numeric, categorical)
    X_transformed = preprocessor.fit_transform(X)
    return X_transformed, y


def test_regression_metrics_computes_rmse_mae_r2():
    y_true = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    y_pred = np.array([1.1, 1.9, 3.2, 3.8, 5.1])

    metrics = regression_metrics(y_true, y_pred)

    assert set(metrics.keys()) == {"rmse", "mae", "r2"}
    assert metrics["rmse"] == pytest.approx(np.sqrt(np.mean((y_true - y_pred) ** 2)))
    assert metrics["mae"] == pytest.approx(np.mean(np.abs(y_true - y_pred)))
    ss_res = np.sum((y_true - y_pred) ** 2)
    ss_tot = np.sum((y_true - np.mean(y_true)) ** 2)
    assert metrics["r2"] == pytest.approx(1 - ss_res / ss_tot)


def test_regression_metrics_raises_on_mismatched_shapes():
    with pytest.raises(ValueError, match="same length"):
        regression_metrics(np.array([1.0, 2.0]), np.array([1.0]))


def test_cv_scores_returns_mean_and_std():
    X, y = _preprocessed_frame(100)
    model = Pipeline([("model", LinearRegression())])

    scores = cv_scores(model, X, y, cv=5, scoring="neg_root_mean_squared_error")

    assert set(scores.keys()) == {"mean", "std"}
    assert scores["mean"] < 0  # neg RMSE
    assert scores["std"] >= 0


def test_evaluate_model_returns_metrics_dict():
    X, y = _preprocessed_frame(60)
    model = Pipeline([("model", LinearRegression())])
    model.fit(X, y)

    metrics = evaluate_model(model, X, y)

    assert set(metrics.keys()) == {"rmse", "mae", "r2"}
    assert metrics["rmse"] >= 0
    assert metrics["mae"] >= 0


def test_cross_validate_model_returns_cv_dict():
    X, y = _preprocessed_frame(60)
    model = Pipeline([("model", LinearRegression())])

    cv_results = cross_validate_model(model, X, y, cv=5)

    assert set(cv_results.keys()) == {"cv_rmse_mean", "cv_rmse_std"}
    assert cv_results["cv_rmse_mean"] >= 0
    assert cv_results["cv_rmse_std"] >= 0


def test_train_baselines_returns_fitted_pipelines():
    X, y = _preprocessed_frame(80)
    config = Config()

    baselines = train_baselines(X, y, config)

    assert set(baselines.keys()) == {"LinearRegression", "DecisionTreeRegressor"}
    for _, pipeline in baselines.items():
        assert isinstance(pipeline, Pipeline)
        assert "preprocessor" in pipeline.named_steps
        assert "model" in pipeline.named_steps
        assert hasattr(pipeline.named_steps["model"], "predict")


def test_train_baselines_linear_regression_predicts():
    X, y = _preprocessed_frame(60)
    config = Config()

    baselines = train_baselines(X, y, config)
    lr = baselines["LinearRegression"]

    preds = lr.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_baselines_decision_tree_predicts():
    X, y = _preprocessed_frame(60)
    config = Config()

    baselines = train_baselines(X, y, config)
    dt = baselines["DecisionTreeRegressor"]

    preds = dt.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_regularized_returns_fitted_pipelines():
    X, y = _preprocessed_frame(80)
    config = Config()

    regularized = train_regularized(X, y, config)

    assert set(regularized.keys()) == {"RidgeCV", "LassoCV", "ElasticNetCV"}
    for _, pipeline in regularized.items():
        assert isinstance(pipeline, Pipeline)
        assert "preprocessor" in pipeline.named_steps
        assert "model" in pipeline.named_steps
        assert hasattr(pipeline.named_steps["model"], "predict")


def test_train_regularized_ridgecv_predicts():
    X, y = _preprocessed_frame(60)
    config = Config()

    regularized = train_regularized(X, y, config)
    ridge = regularized["RidgeCV"]

    preds = ridge.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_regularized_lassocv_predicts():
    X, y = _preprocessed_frame(60)
    config = Config()

    regularized = train_regularized(X, y, config)
    lasso = regularized["LassoCV"]

    preds = lasso.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_regularized_elasticnetcv_predicts():
    X, y = _preprocessed_frame(60)
    config = Config()

    regularized = train_regularized(X, y, config)
    enet = regularized["ElasticNetCV"]

    preds = enet.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_regularized_uses_config_alphas():
    X, y = _preprocessed_frame(60)
    config = Config()

    regularized = train_regularized(X, y, config)

    ridge = regularized["RidgeCV"]
    lasso = regularized["LassoCV"]
    enet = regularized["ElasticNetCV"]

    assert isinstance(ridge.named_steps["model"], RidgeCV)
    assert isinstance(lasso.named_steps["model"], LassoCV)
    assert isinstance(enet.named_steps["model"], ElasticNetCV)


def test_train_regularized_ridgecv_alphas_match_config():
    X, y = _preprocessed_frame(60)
    config = Config()

    regularized = train_regularized(X, y, config)
    ridge = regularized["RidgeCV"].named_steps["model"]

    np.testing.assert_array_equal(np.sort(ridge.alphas), np.sort(config.ridge_alphas))


def test_train_regularized_lassocv_alphas_match_config():
    X, y = _preprocessed_frame(60)
    config = Config()

    regularized = train_regularized(X, y, config)
    lasso = regularized["LassoCV"].named_steps["model"]

    np.testing.assert_array_equal(np.sort(lasso.alphas), np.sort(config.lasso_alphas))


def test_train_regularized_elasticnetcv_alphas_match_config():
    X, y = _preprocessed_frame(60)
    config = Config()

    regularized = train_regularized(X, y, config)
    enet = regularized["ElasticNetCV"].named_steps["model"]

    np.testing.assert_array_equal(np.sort(enet.alphas), np.sort(config.elasticnet_alphas))
    np.testing.assert_array_equal(np.sort(enet.l1_ratio), np.sort(config.elasticnet_l1_ratios))


def test_baselines_and_regularized_share_preprocessing():
    X, y = _preprocessed_frame(80)
    config = Config()

    baselines = train_baselines(X, y, config)
    regularized = train_regularized(X, y, config)

    # Both should have a preprocessor step
    for pipeline in {**baselines, **regularized}.values():
        assert "preprocessor" in pipeline.named_steps


def test_train_baselines_rejects_empty_data():
    config = Config()
    with pytest.raises(ValueError):
        train_baselines(np.empty((0, 5)), np.empty(0), config)


def test_train_regularized_rejects_empty_data():
    config = Config()
    with pytest.raises(ValueError):
        train_regularized(np.empty((0, 5)), np.empty(0), config)


def test_identity_preprocessor_get_feature_names_out():
    from ml_backend.models.baselines import _IdentityPreprocessor
    from ml_backend.models.regularized import _IdentityPreprocessor as _IdentityPreprocessor2

    prep = _IdentityPreprocessor().fit(np.array([[1, 2], [3, 4]]))
    assert prep.get_feature_names_out() is None
    assert prep.get_feature_names_out(["a", "b"]) == ["a", "b"]

    prep2 = _IdentityPreprocessor2().fit(np.array([[1, 2], [3, 4]]))
    assert prep2.get_feature_names_out() is None
    assert prep2.get_feature_names_out(["a", "b"]) == ["a", "b"]
