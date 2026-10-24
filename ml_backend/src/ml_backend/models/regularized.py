"""Regularized model training for HomeValue."""

from typing import Any

import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin  # type: ignore[import-untyped]
from sklearn.linear_model import ElasticNetCV, LassoCV, RidgeCV  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]

from ml_backend.config import Config


class _IdentityPreprocessor(TransformerMixin, BaseEstimator):
    """Pass-through preprocessor for already-transformed data."""

    def fit(self, X: Any, y: Any = None) -> "_IdentityPreprocessor":
        return self

    def transform(self, X: Any) -> Any:
        return X

    def get_feature_names_out(self, input_features: Any = None) -> Any:
        return input_features


def train_regularized(
    X: np.ndarray,
    y: np.ndarray,
    config: Config,
) -> dict[str, Pipeline]:
    """Train regularized models wrapped with an identity preprocessing pipeline.

    Returns a dict of fitted Pipelines keyed by model name.
    """
    if len(X) == 0 or len(y) == 0:
        raise ValueError("Training data must not be empty")

    regularized: dict[str, Pipeline] = {}

    # RidgeCV
    ridge_cv = RidgeCV(alphas=np.array(config.ridge_alphas), cv=config.cv_folds)
    ridge_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", ridge_cv)])
    ridge_pipeline.fit(X, y)
    regularized["RidgeCV"] = ridge_pipeline

    # LassoCV
    lasso_cv = LassoCV(
        alphas=np.array(config.lasso_alphas),
        cv=config.cv_folds,
        max_iter=10000,
        random_state=config.random_state,
    )
    lasso_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", lasso_cv)])
    lasso_pipeline.fit(X, y)
    regularized["LassoCV"] = lasso_pipeline

    # ElasticNetCV
    elasticnet_cv = ElasticNetCV(
        alphas=np.array(config.elasticnet_alphas),
        l1_ratio=np.array(config.elasticnet_l1_ratios),
        cv=config.cv_folds,
        max_iter=10000,
        random_state=config.random_state,
    )
    elasticnet_pipeline = Pipeline(
        [("preprocessor", _IdentityPreprocessor()), ("model", elasticnet_cv)]
    )
    elasticnet_pipeline.fit(X, y)
    regularized["ElasticNetCV"] = elasticnet_pipeline

    return regularized
