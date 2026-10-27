"""Tests for model selection and serialization."""

import warnings

import numpy as np
import pytest
from sklearn.linear_model import LinearRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from ml_backend.models.selection import (
    load_model,
    save_model,
    select_best_model,
)

# Suppress sklearn RuntimeWarning for division by zero in SelectKBest
warnings.filterwarnings("ignore", "invalid value encountered in divide", RuntimeWarning)


def _dummy_pipeline(name: str) -> Pipeline:
    """Create a dummy fitted pipeline for testing."""
    pipe = Pipeline(
        [
            ("scaler", StandardScaler()),
            ("model", LinearRegression()),
        ]
    )
    X = np.random.default_rng(42).normal(size=(20, 5))
    y = np.random.default_rng(42).normal(size=20)
    pipe.fit(X, y)
    return pipe


def test_select_best_model_picks_lowest_rmse():
    rng = np.random.default_rng(0)
    X_test = rng.normal(size=(30, 5))
    y_test = rng.normal(size=30)

    # Model A: RMSE ~ 0.5
    pipe_a = _dummy_pipeline("ModelA")
    # Model B: RMSE ~ 0.2 (better)
    pipe_b = _dummy_pipeline("ModelB")
    pipe_b.named_steps["model"].coef_ *= 0.1  # make it fit better

    models = {"ModelA": pipe_a, "ModelB": pipe_b}

    best_name, best_pipe = select_best_model(models, X_test, y_test)

    assert best_name == "ModelB"
    assert best_pipe is pipe_b


def test_select_best_model_with_empty_dict_raises():
    with pytest.raises(ValueError, match="No models provided for selection"):
        select_best_model({}, np.array([[1.0]]), np.array([1.0]))


def test_select_best_model_with_mismatched_samples_raises():
    pipe = _dummy_pipeline("Model1")
    X_test = np.random.default_rng(1).normal(size=(10, 5))
    y_test = np.random.default_rng(1).normal(size=5)  # different size

    with pytest.raises(ValueError, match="X_test and y_test must have the same number of samples"):
        select_best_model({"Model1": pipe}, X_test, y_test)


def test_save_model_creates_file(tmp_path):
    pipe = _dummy_pipeline("TestModel")
    path = tmp_path / "model.joblib"

    save_model(pipe, path)

    assert path.exists()


def test_save_model_creates_parent_dirs(tmp_path):
    pipe = _dummy_pipeline("TestModel")
    path = tmp_path / "subdir" / "model.joblib"

    save_model(pipe, path)

    assert path.exists()


def test_load_model_returns_pipeline(tmp_path):
    pipe = _dummy_pipeline("TestModel")
    path = tmp_path / "model.joblib"
    save_model(pipe, path)

    loaded = load_model(path)

    assert isinstance(loaded, Pipeline)
    assert set(loaded.named_steps.keys()) == {"scaler", "model"}


def test_load_model_predictions_match(tmp_path):
    pipe = _dummy_pipeline("TestModel")
    X = np.random.default_rng(0).normal(size=(10, 5))
    y = np.random.default_rng(0).normal(size=10)
    pipe.fit(X, y)

    path = tmp_path / "model.joblib"
    save_model(pipe, path)
    loaded = load_model(path)

    original_preds = pipe.predict(X)
    loaded_preds = loaded.predict(X)

    np.testing.assert_array_almost_equal(original_preds, loaded_preds)


def test_load_model_raises_on_missing_file():
    with pytest.raises(FileNotFoundError):
        load_model("/nonexistent/path/model.joblib")


def test_save_load_preserves_all_steps(tmp_path):
    from sklearn.feature_selection import SelectKBest

    pipe = Pipeline(
        [
            ("scaler", StandardScaler()),
            ("select", SelectKBest(k=3)),
            ("model", LinearRegression()),
        ]
    )
    pipe.fit(
        np.random.default_rng(0).normal(size=(20, 10)), np.random.default_rng(0).normal(size=20)
    )

    path = tmp_path / "model.joblib"
    save_model(pipe, path)
    loaded = load_model(path)

    assert set(loaded.named_steps.keys()) == set(pipe.named_steps.keys())
    for step_name in pipe.named_steps:
        assert step_name in loaded.named_steps
