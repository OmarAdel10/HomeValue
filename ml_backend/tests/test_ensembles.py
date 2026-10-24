"""Tests for ensemble models."""

import numpy as np
import pytest
from sklearn.ensemble import (
    ExtraTreesRegressor,
    RandomForestRegressor,
    StackingRegressor,
    VotingRegressor,
)
from sklearn.linear_model import RidgeCV
from sklearn.pipeline import Pipeline

from ml_backend.config import Config
from ml_backend.models import train_ensembles
from ml_backend.models._identity import _IdentityPreprocessor


def _preprocessed_frame(n_rows: int = 80) -> tuple[np.ndarray, np.ndarray]:
    """Create preprocessed features and target."""
    rng = np.random.default_rng(0)
    X = rng.uniform(-1, 1, (n_rows, 10))
    y = rng.uniform(0.5, 5.0, n_rows)
    return X, y


def _base_estimators(config: Config) -> dict:
    """Create base estimators for Voting and Stacking."""
    return {
        "rf": RandomForestRegressor(n_estimators=50, random_state=config.random_state),
        "ridge": RidgeCV(alphas=[0.1, 1.0, 10.0]),
        "enet": RidgeCV(alphas=[0.1, 1.0, 10.0]),
    }


def test_train_ensembles_returns_fitted_pipelines():
    X, y = _preprocessed_frame(100)
    config = Config()

    # Provide base estimators from previous tasks
    base_estimators = {
        "rf": RandomForestRegressor(n_estimators=50, random_state=config.random_state),
        "ridge": RidgeCV(alphas=[0.1, 1.0, 10.0]),
        "enet": RidgeCV(alphas=[0.1, 1.0, 10.0]),  # Using Ridge as placeholder
    }

    ensembles = train_ensembles(X, y, config, base_estimators)

    assert set(ensembles.keys()) == {
        "RandomForestRegressor",
        "ExtraTreesRegressor",
        "VotingRegressor",
        "StackingRegressor",
    }
    for _, pipeline in ensembles.items():
        assert isinstance(pipeline, Pipeline)
        assert "preprocessor" in pipeline.named_steps
        assert "model" in pipeline.named_steps
        assert hasattr(pipeline.named_steps["model"], "predict")


def test_train_ensembles_random_forest_predicts():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = _base_estimators(config)

    ensembles = train_ensembles(X, y, config, base_estimators)
    rf = ensembles["RandomForestRegressor"]

    preds = rf.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_ensembles_extra_trees_predicts():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = _base_estimators(config)

    ensembles = train_ensembles(X, y, config, base_estimators)
    et = ensembles["ExtraTreesRegressor"]

    preds = et.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_ensembles_voting_regressor_predicts():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = {
        "rf": RandomForestRegressor(n_estimators=50, random_state=config.random_state),
        "ridge": RidgeCV(alphas=[0.1, 1.0, 10.0]),
        "enet": RidgeCV(alphas=[0.1, 1.0, 10.0]),
    }

    ensembles = train_ensembles(X, y, config, base_estimators)
    voting = ensembles["VotingRegressor"]

    preds = voting.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_ensembles_stacking_regressor_predicts():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = {
        "rf": RandomForestRegressor(n_estimators=50, random_state=config.random_state),
        "ridge": RidgeCV(alphas=[0.1, 1.0, 10.0]),
        "enet": RidgeCV(alphas=[0.1, 1.0, 10.0]),
    }

    ensembles = train_ensembles(X, y, config, base_estimators)
    stacking = ensembles["StackingRegressor"]

    preds = stacking.predict(X[:5])

    assert len(preds) == 5
    assert np.isfinite(preds).all()


def test_train_ensembles_random_forest_uses_config_params():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = _base_estimators(config)

    ensembles = train_ensembles(X, y, config, base_estimators)
    rf = ensembles["RandomForestRegressor"].named_steps["model"]

    assert isinstance(rf, RandomForestRegressor)
    assert rf.n_estimators == config.rf_n_estimators
    assert rf.max_features == config.rf_max_features
    assert rf.random_state == config.random_state


def test_train_ensembles_extra_trees_uses_config_params():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = _base_estimators(config)

    ensembles = train_ensembles(X, y, config, base_estimators)
    et = ensembles["ExtraTreesRegressor"].named_steps["model"]

    assert isinstance(et, ExtraTreesRegressor)
    assert et.n_estimators == config.rf_n_estimators
    assert et.max_features == config.rf_max_features
    assert et.random_state == config.random_state


def test_train_ensembles_voting_uses_base_estimators():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = {
        "rf": RandomForestRegressor(n_estimators=50, random_state=config.random_state),
        "ridge": RidgeCV(alphas=[0.1, 1.0, 10.0]),
        "enet": RidgeCV(alphas=[0.1, 1.0, 10.0]),
    }

    ensembles = train_ensembles(X, y, config, base_estimators)
    voting = ensembles["VotingRegressor"].named_steps["model"]

    assert isinstance(voting, VotingRegressor)
    assert len(voting.estimators) == 3
    estimator_names = [name for name, _ in voting.estimators]
    assert set(estimator_names) == {"rf", "ridge", "enet"}


def test_train_ensembles_stacking_uses_base_estimators_and_final_ridgecv():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = {
        "rf": RandomForestRegressor(n_estimators=50, random_state=config.random_state),
        "ridge": RidgeCV(alphas=[0.1, 1.0, 10.0]),
        "enet": RidgeCV(alphas=[0.1, 1.0, 10.0]),
    }

    ensembles = train_ensembles(X, y, config, base_estimators)
    stacking = ensembles["StackingRegressor"].named_steps["model"]

    assert isinstance(stacking, StackingRegressor)
    assert len(stacking.estimators) == 3
    estimator_names = [name for name, _ in stacking.estimators]
    assert set(estimator_names) == {"rf", "ridge", "enet"}
    assert isinstance(stacking.final_estimator, RidgeCV)


def test_train_ensembles_shares_identity_preprocessor():
    X, y = _preprocessed_frame(80)
    config = Config()
    base_estimators = _base_estimators(config)

    ensembles = train_ensembles(X, y, config, base_estimators)

    for pipeline in ensembles.values():
        assert "preprocessor" in pipeline.named_steps
        assert isinstance(pipeline.named_steps["preprocessor"], _IdentityPreprocessor)


def test_train_ensembles_rejects_empty_data():
    config = Config()
    base_estimators = {}

    with pytest.raises(ValueError, match="Training data must not be empty"):
        train_ensembles(np.empty((0, 5)), np.empty(0), config, base_estimators)

    with pytest.raises(ValueError, match="same number of samples"):
        train_ensembles(np.empty((5, 3)), np.empty(4), config, base_estimators)

    with pytest.raises(ValueError, match="at least one feature"):
        train_ensembles(np.empty((5, 0)), np.empty(5), config, base_estimators)

    with pytest.raises(ValueError, match="finite values"):
        train_ensembles(np.array([[1.0, np.inf]]), np.array([1.0]), config, base_estimators)


def test_train_ensembles_rejects_missing_base_estimators_for_voting():
    X, y = _preprocessed_frame(80)
    config = Config()

    with pytest.raises(ValueError, match="base_estimators missing required keys"):
        train_ensembles(X, y, config, {})


def test_train_ensembles_rejects_missing_base_estimators_for_stacking():
    X, y = _preprocessed_frame(80)
    config = Config()

    with pytest.raises(ValueError, match="base_estimators missing required keys"):
        train_ensembles(X, y, config, {})


def test_identity_preprocessor_in_ensembles_module():
    from ml_backend.models._identity import _IdentityPreprocessor as _IdentityPreprocessorBase
    from ml_backend.models.ensembles import _IdentityPreprocessor as _IdentityPreprocessorEnsembles

    # Should be the same class (imported from shared module)
    assert _IdentityPreprocessorEnsembles is _IdentityPreprocessorBase


def test_train_ensembles_without_base_estimators_returns_rf_and_et_only():
    X, y = _preprocessed_frame(80)
    config = Config()

    ensembles = train_ensembles(X, y, config, None)

    assert set(ensembles.keys()) == {"RandomForestRegressor", "ExtraTreesRegressor"}
    assert "VotingRegressor" not in ensembles
    assert "StackingRegressor" not in ensembles

    for pipeline in ensembles.values():
        assert "preprocessor" in pipeline.named_steps
        assert isinstance(pipeline.named_steps["preprocessor"], _IdentityPreprocessor)
        preds = pipeline.predict(X[:5])
        assert len(preds) == 5
        assert np.isfinite(preds).all()


def test_train_ensembles_without_base_estimators_still_validates_input():
    config = Config()

    with pytest.raises(ValueError, match="Training data must not be empty"):
        train_ensembles(np.empty((0, 5)), np.empty(0), config, None)

    with pytest.raises(ValueError, match="same number of samples"):
        train_ensembles(np.empty((5, 3)), np.empty(4), config, None)

    with pytest.raises(ValueError, match="at least one feature"):
        train_ensembles(np.empty((5, 0)), np.empty(5), config, None)

    with pytest.raises(ValueError, match="finite values"):
        train_ensembles(np.array([[1.0, np.inf]]), np.array([1.0]), config, None)
