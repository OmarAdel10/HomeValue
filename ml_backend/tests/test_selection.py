"""Tests for model selection and serialization."""

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


def test_select_best_model_returns_pipeline_tuple():
    X_test = np.random.default_rng(1).normal(size=(20, 5))
    y_test = np.random.default_rng(1).normal(size=20)
    models = {"A": _dummy_pipeline("A"), "B": _dummy_pipeline("B")}

    name, pipe = select_best_model(models, X_test, y_test)

    assert isinstance(name, str)
    assert isinstance(pipe, Pipeline)


def test_select_best_model_raises_on_empty_dict():
    X_test = np.random.default_rng(2).normal(size=(10, 5))
    y_test = np.random.default_rng(2).normal(size=10)

    with pytest.raises(ValueError, match="No models provided"):
        select_best_model({}, X_test, y_test)


def test_select_best_model_raises_on_mismatched_shapes():
    X_test = np.random.default_rng(3).normal(size=(10, 3))
    y_test = np.random.default_rng(3).normal(size=9)  # mismatched
    models = {"A": _dummy_pipeline("A")}

    with pytest.raises(ValueError, match="same number of samples"):
        select_best_model(models, X_test, y_test)


def test_save_model_creates_file(tmp_path):
    pipe = _dummy_pipeline("TestModel")
    path = tmp_path / "model.joblib"

    save_model(pipe, path)

    assert path.exists()
    assert path.stat().st_size > 0


def test_save_model_creates_parent_dirs(tmp_path):
    pipe = _dummy_pipeline("TestModel")
    path = tmp_path / "nested" / "deep" / "model.joblib"

    save_model(pipe, path)

    assert path.exists()


def test_load_model_returns_pipeline(tmp_path):
    original = _dummy_pipeline("Original")
    path = tmp_path / "model.joblib"
    save_model(original, path)

    loaded = load_model(path)

    assert isinstance(loaded, Pipeline)
    assert hasattr(loaded.named_steps["model"], "predict")


def test_load_model_predictions_match(tmp_path):
    rng = np.random.default_rng(42)
    X = rng.normal(size=(20, 5))
    y = rng.normal(size=20)

    original = Pipeline(
        [
            ("scaler", StandardScaler()),
            ("model", LinearRegression()),
        ]
    )
    original.fit(X, y)

    path = tmp_path / "model.joblib"
    save_model(original, path)
    loaded = load_model(path)

    original_preds = original.predict(X)
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


def test_select_best_model_with_three_models():
    X_test = np.random.default_rng(5).normal(size=(25, 5))
    y_test = np.random.default_rng(5).normal(size=25)

    models = {
        "Model1": _dummy_pipeline("Model1"),
        "Model2": _dummy_pipeline("Model2"),
        "Model3": _dummy_pipeline("Model3"),
    }

    best_name, best_pipe = select_best_model(models, X_test, y_test)

    assert best_name in {"Model1", "Model2", "Model3"}
    assert best_pipe in models.values()
