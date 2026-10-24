"""Baseline model training for HomeValue."""

import numpy as np
from sklearn.linear_model import LinearRegression  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]
from sklearn.tree import DecisionTreeRegressor  # type: ignore[import-untyped]

from ml_backend.config import Config
from ml_backend.models._identity import _IdentityPreprocessor


def train_baselines(
    X: np.ndarray,
    y: np.ndarray,
    config: Config,
) -> dict[str, Pipeline]:
    """Train baseline models wrapped with an identity preprocessing pipeline.

    Returns a dict of fitted Pipelines keyed by model name.
    """
    if X.shape[0] == 0 or y.shape[0] == 0:
        raise ValueError("Training data must not be empty")
    if X.shape[0] != y.shape[0]:
        raise ValueError("X and y must have the same number of samples")
    if X.shape[1] == 0:
        raise ValueError("X must have at least one feature")
    if not np.isfinite(X).all() or not np.isfinite(y).all():
        raise ValueError("Training data must contain only finite values")

    baselines: dict[str, Pipeline] = {}

    # Linear Regression
    lr_pipeline = Pipeline(
        [("preprocessor", _IdentityPreprocessor()), ("model", LinearRegression())]
    )
    lr_pipeline.fit(X, y)
    baselines["LinearRegression"] = lr_pipeline

    # Decision Tree Regressor
    dt_pipeline = Pipeline(
        [
            ("preprocessor", _IdentityPreprocessor()),
            (
                "model",
                DecisionTreeRegressor(
                    random_state=config.random_state,
                    max_depth=config.dt_max_depth,
                    min_samples_split=config.dt_min_samples_split,
                    min_samples_leaf=config.dt_min_samples_leaf,
                ),
            ),
        ]
    )
    dt_pipeline.fit(X, y)
    baselines["DecisionTreeRegressor"] = dt_pipeline

    return baselines
