"""Tests for hyperparameter tuning with RandomizedSearchCV."""

import numpy as np
import pytest
from sklearn.ensemble import GradientBoostingRegressor, RandomForestRegressor
from sklearn.model_selection import RandomizedSearchCV

from ml_backend.config import Config
from ml_backend.models.tuning import (
    tune_gradient_boosting,
    tune_random_forest,
)


def _preprocessed_frame(n_rows: int = 80) -> tuple[np.ndarray, np.ndarray]:
    """Create preprocessed features and target."""
    rng = np.random.default_rng(0)
    X = rng.uniform(-1, 1, (n_rows, 10))
    y = rng.uniform(0.5, 5.0, n_rows)
    return X, y


def test_tune_random_forest_returns_randomized_search_cv():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_random_forest(X, y, config)

    assert isinstance(search, RandomizedSearchCV)
    assert search.best_estimator_ is not None
    assert isinstance(search.best_estimator_, RandomForestRegressor)


def test_tune_random_forest_correct_param_distributions():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_random_forest(X, y, config)
    distributions = search.param_distributions

    expected_keys = {
        "n_estimators",
        "max_depth",
        "min_samples_split",
        "min_samples_leaf",
        "max_features",
    }
    assert set(distributions.keys()) == expected_keys


def test_tune_random_forest_n_iter_and_cv():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_random_forest(X, y, config)

    assert search.n_iter == config.rf_n_iter_search
    assert search.cv == config.cv_folds
    assert search.refit is True


def test_tune_random_forest_n_jobs_from_config():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_random_forest(X, y, config)

    assert search.n_jobs == config.cv_n_jobs


def test_tune_random_forest_random_state_from_config():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_random_forest(X, y, config)

    assert search.random_state == config.random_state


def test_tune_gradient_boosting_returns_randomized_search_cv():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_gradient_boosting(X, y, config)

    assert isinstance(search, RandomizedSearchCV)
    assert search.best_estimator_ is not None
    assert isinstance(search.best_estimator_, GradientBoostingRegressor)


def test_tune_gradient_boosting_correct_param_distributions():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_gradient_boosting(X, y, config)
    distributions = search.param_distributions

    expected_keys = {
        "n_estimators",
        "learning_rate",
        "max_depth",
        "subsample",
    }
    assert set(distributions.keys()) == expected_keys


def test_tune_gradient_boosting_n_iter_and_cv():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_gradient_boosting(X, y, config)

    assert search.n_iter == config.gb_n_iter_search
    assert search.cv == config.cv_folds
    assert search.refit is True


def test_tune_gradient_boosting_n_jobs_from_config():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_gradient_boosting(X, y, config)

    assert search.n_jobs == config.cv_n_jobs


def test_tune_gradient_boosting_random_state_from_config():
    X, y = _preprocessed_frame(100)
    config = Config()

    search = tune_gradient_boosting(X, y, config)

    assert search.random_state == config.random_state


def test_tuning_functions_reject_empty_data():
    config = Config()

    with pytest.raises(ValueError, match="Training data must not be empty"):
        tune_random_forest(np.empty((0, 5)), np.empty(0), config)

    with pytest.raises(ValueError, match="Training data must not be empty"):
        tune_gradient_boosting(np.empty((0, 5)), np.empty(0), config)


def test_tuning_functions_reject_mismatched_samples():
    config = Config()
    X = np.zeros((5, 3))
    y = np.zeros(4)

    with pytest.raises(ValueError, match="same number of samples"):
        tune_random_forest(X, y, config)

    with pytest.raises(ValueError, match="same number of samples"):
        tune_gradient_boosting(X, y, config)


def test_tuning_functions_reject_zero_features():
    config = Config()
    X = np.zeros((5, 0))
    y = np.zeros(5)

    with pytest.raises(ValueError, match="at least one feature"):
        tune_random_forest(X, y, config)

    with pytest.raises(ValueError, match="at least one feature"):
        tune_gradient_boosting(X, y, config)


def test_tuning_functions_reject_non_finite_x():
    config = Config()
    X = np.array([[1.0, np.inf], [2.0, 3.0]])
    y = np.array([1.0, 2.0])

    with pytest.raises(ValueError, match="finite values"):
        tune_random_forest(X, y, config)

    with pytest.raises(ValueError, match="finite values"):
        tune_gradient_boosting(X, y, config)


def test_tuning_functions_reject_non_finite_y():
    config = Config()
    X = np.array([[1.0, 2.0], [3.0, 4.0]])
    y = np.array([1.0, np.nan])

    with pytest.raises(ValueError, match="finite values"):
        tune_random_forest(X, y, config)

    with pytest.raises(ValueError, match="finite values"):
        tune_gradient_boosting(X, y, config)


def test_tuning_functions_reject_non_numeric_dtype():
    config = Config()
    X = np.array([["a", "b"], ["c", "d"]], dtype=object)
    y = np.array([1.0, 2.0])

    with pytest.raises(ValueError, match="numeric array"):
        tune_random_forest(X, y, config)

    with pytest.raises(ValueError, match="numeric array"):
        tune_gradient_boosting(X, y, config)
