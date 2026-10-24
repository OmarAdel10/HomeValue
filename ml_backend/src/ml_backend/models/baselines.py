"""Baseline model training for HomeValue."""

from typing import Any

import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin  # type: ignore[import-untyped]
from sklearn.linear_model import LinearRegression  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]
from sklearn.tree import DecisionTreeRegressor  # type: ignore[import-untyped]

from ml_backend.config import Config


class _IdentityPreprocessor(TransformerMixin, BaseEstimator):
    """Pass-through preprocessor for already-transformed data."""

    def fit(self, X: Any, y: Any = None) -> "_IdentityPreprocessor":
        return self

    def transform(self, X: Any) -> Any:
        return X

    def get_feature_names_out(self, input_features: Any = None) -> Any:
        return input_features


def train_baselines(
    X: np.ndarray,
    y: np.ndarray,
    config: Config,
) -> dict[str, Pipeline]:
    """Train baseline models wrapped with an identity preprocessing pipeline.

    Returns a dict of fitted Pipelines keyed by model name.
    """
    if len(X) == 0 or len(y) == 0:
        raise ValueError("Training data must not be empty")

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
            ("model", DecisionTreeRegressor(random_state=config.random_state)),
        ]
    )
    dt_pipeline.fit(X, y)
    baselines["DecisionTreeRegressor"] = dt_pipeline

    return baselines
