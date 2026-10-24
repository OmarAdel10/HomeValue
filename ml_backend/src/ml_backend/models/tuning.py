"""Hyperparameter tuning with RandomizedSearchCV for HomeValue."""

import numpy as np
from scipy.stats import randint, uniform
from sklearn.ensemble import (  # type: ignore[import-untyped]
    GradientBoostingRegressor,
    RandomForestRegressor,
)
from sklearn.model_selection import RandomizedSearchCV  # type: ignore[import-untyped]

from ml_backend.config import Config


def _validate_training_data(X: np.ndarray, y: np.ndarray) -> None:
    """Validate training data for tuning functions."""
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


def tune_random_forest(
    X: np.ndarray,
    y: np.ndarray,
    config: Config,
) -> RandomizedSearchCV:
    """Tune RandomForestRegressor hyperparameters using RandomizedSearchCV.

    Returns a fitted RandomizedSearchCV with best estimator available via best_estimator_.
    """
    _validate_training_data(X, y)

    param_distributions = {
        "n_estimators": randint(50, 500),
        "max_depth": randint(3, 30),
        "min_samples_split": randint(2, 20),
        "min_samples_leaf": randint(1, 10),
        "max_features": ["sqrt", "log2", None],
    }

    rf = RandomForestRegressor(random_state=config.random_state)

    search = RandomizedSearchCV(
        estimator=rf,
        param_distributions=param_distributions,
        n_iter=config.rf_n_iter_search,
        cv=config.cv_folds,
        n_jobs=config.cv_n_jobs,
        random_state=config.random_state,
        refit=True,
        scoring="neg_root_mean_squared_error",
    )

    search.fit(X, y)
    return search


def tune_gradient_boosting(
    X: np.ndarray,
    y: np.ndarray,
    config: Config,
) -> RandomizedSearchCV:
    """Tune GradientBoostingRegressor hyperparameters using RandomizedSearchCV.

    Returns a fitted RandomizedSearchCV with best estimator available via best_estimator_.
    """
    _validate_training_data(X, y)

    param_distributions = {
        "n_estimators": randint(50, 500),
        "learning_rate": uniform(0.01, 0.3),
        "max_depth": randint(3, 15),
        "subsample": uniform(0.6, 0.4),  # 0.6 to 1.0
    }

    gb = GradientBoostingRegressor(random_state=config.random_state)

    search = RandomizedSearchCV(
        estimator=gb,
        param_distributions=param_distributions,
        n_iter=config.gb_n_iter_search,
        cv=config.cv_folds,
        n_jobs=config.cv_n_jobs,
        random_state=config.random_state,
        refit=True,
        scoring="neg_root_mean_squared_error",
    )

    search.fit(X, y)
    return search
