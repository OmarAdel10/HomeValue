"""Tests for the full training orchestration pipeline.

The heavy learners are replaced by constant predictors so the orchestration,
artifact persistence, and comparison bookkeeping run end to end without
downloading the California housing dataset or fitting real ensembles.
"""

import json
from contextlib import contextmanager
from types import SimpleNamespace
from unittest.mock import patch

import joblib
from sklearn.dummy import DummyRegressor
from sklearn.pipeline import Pipeline

from ml_backend.api.train import (
    _update_best_in_comparison,
    run_full_training_pipeline,
)
from ml_backend.config import Config


def _constant(value: float) -> DummyRegressor:
    return DummyRegressor(strategy="constant", constant=value).fit([[0.0]], [value])


def _trained_models() -> dict[str, object]:
    """Return one deterministic model per training stage."""
    return {
        "baselines": {
            "LinearRegression": _constant(2.0),
            "DecisionTreeRegressor": _constant(1.5),
        },
        "regularized": {"RidgeCV": _constant(2.4)},
        "ensembles": {
            "VotingRegressor": _constant(2.2),
            "StackingRegressor": _constant(2.6),
        },
        "random_forest": SimpleNamespace(best_estimator_=_constant(2.1)),
        "gradient_boosting": SimpleNamespace(best_estimator_=_constant(2.3)),
    }


def _model_names(models: dict[str, object]) -> set[str]:
    names = {
        name
        for key in ("baselines", "regularized", "ensembles")
        for name in models[key]  # type: ignore[union-attr]
    }
    return names | {
        "RandomForestRegressor_Tuned",
        "GradientBoostingRegressor_Tuned",
    }


@contextmanager
def _patched_training_stages(X, y, models):
    """Patch the data load and every training stage of the pipeline."""
    with (
        patch("ml_backend.api.train.load_california_housing", return_value=(X, y)) as load_data,
        patch(
            "ml_backend.api.train.train_baselines", return_value=models["baselines"]
        ) as baselines,
        patch(
            "ml_backend.api.train.train_regularized", return_value=models["regularized"]
        ) as regularized,
        patch(
            "ml_backend.api.train.train_ensembles", return_value=models["ensembles"]
        ) as ensembles,
        patch(
            "ml_backend.api.train.tune_random_forest", return_value=models["random_forest"]
        ) as tune_rf,
        patch(
            "ml_backend.api.train.tune_gradient_boosting", return_value=models["gradient_boosting"]
        ) as tune_gb,
    ):
        yield SimpleNamespace(
            load_data=load_data,
            baselines=baselines,
            regularized=regularized,
            ensembles=ensembles,
            tune_rf=tune_rf,
            tune_gb=tune_gb,
        )


def test_run_full_training_pipeline_persists_artifact_and_comparison(
    sample_housing_data, sample_target, tmp_path
):
    config = Config(project_root=tmp_path)
    models = _trained_models()

    with _patched_training_stages(sample_housing_data, sample_target, models) as stages:
        result = run_full_training_pipeline(config)

    stages.load_data.assert_called_once_with()
    stages.baselines.assert_called_once()
    stages.regularized.assert_called_once()
    stages.ensembles.assert_called_once()
    stages.tune_rf.assert_called_once()
    stages.tune_gb.assert_called_once()

    # The ensemble stage receives unfitted base estimators keyed for the API.
    base_estimators = stages.ensembles.call_args.args[3]
    assert set(base_estimators) == {"rf", "ridge", "enet"}

    # Returned metrics come from the selected model.
    assert set(result["metrics"]) == {"rmse", "mae", "r2"}
    assert isinstance(result["cv_rmse"], float)
    assert isinstance(result["cv_rmse_std"], float)
    assert result["cv_rmse"] >= 0.0

    # The artifact bundles preprocessing with the winning estimator.
    artifact_path = config.models_dir / "best_model.joblib"
    assert result["artifact"] == str(artifact_path)
    assert artifact_path.is_file()
    artifact = joblib.load(artifact_path)
    assert isinstance(artifact, Pipeline)
    assert list(artifact.named_steps) == ["preprocessing", "model"]

    # Every candidate is recorded, and exactly the winner is flagged.
    with open(config.models_dir / "model_comparison.json") as handle:
        comparison = json.load(handle)

    expected_names = _model_names(models)
    assert {entry["model_name"] for entry in comparison} == expected_names
    winners = [entry for entry in comparison if entry["is_best"]]
    assert len(winners) == 1
    assert winners[0]["model_name"] == result["model"]
    assert result["model"] in expected_names
    for entry in comparison:
        assert entry["cv_std"] == entry["cv_rmse_std"]


def test_run_full_training_pipeline_defaults_to_new_config(
    sample_housing_data, sample_target, tmp_path
):
    config = Config(project_root=tmp_path)
    models = _trained_models()

    with (
        _patched_training_stages(sample_housing_data, sample_target, models),
        patch("ml_backend.api.train.Config", return_value=config) as config_cls,
    ):
        result = run_full_training_pipeline()

    assert config_cls.called
    assert result["model"] in _model_names(models)
    assert (config.models_dir / "best_model.joblib").is_file()
    assert (config.models_dir / "model_comparison.json").is_file()


def test_update_best_in_comparison_ignores_missing_file(tmp_path):
    _update_best_in_comparison(Config(project_root=tmp_path), "RidgeCV")


def test_update_best_in_comparison_flags_only_named_model(tmp_path):
    config = Config(project_root=tmp_path)
    config.ensure_dirs()
    path = config.models_dir / "model_comparison.json"
    entries = [{"model_name": "RidgeCV", "is_best": True}, {"model_name": "LinearRegression"}]
    with open(path, "w") as handle:
        json.dump(entries, handle)

    _update_best_in_comparison(config, "LinearRegression")

    with open(path) as handle:
        updated = json.load(handle)
    assert [entry["is_best"] for entry in updated] == [False, True]
