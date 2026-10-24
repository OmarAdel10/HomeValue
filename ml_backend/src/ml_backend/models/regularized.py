"""Regularized model training for HomeValue."""

import numpy as np
from sklearn.linear_model import ElasticNetCV, LassoCV, RidgeCV  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]

from ml_backend.config import Config
from ml_backend.models._identity import _IdentityPreprocessor


def train_regularized(
    X: np.ndarray,
    y: np.ndarray,
    config: Config,
) -> dict[str, Pipeline]:
    """Train regularized models wrapped with an identity preprocessing pipeline.

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

    regularized: dict[str, Pipeline] = {}

    # RidgeCV
    ridge_cv = RidgeCV(
        alphas=np.array(config.ridge_alphas),
        cv=config.cv_folds,
    )
    ridge_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", ridge_cv)])
    ridge_pipeline.fit(X, y)
    regularized["RidgeCV"] = ridge_pipeline

    # LassoCV
    lasso_cv = LassoCV(
        alphas=np.array(config.lasso_alphas),
        cv=config.cv_folds,
        max_iter=config.lasso_max_iter,
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
        max_iter=config.elasticnet_max_iter,
        random_state=config.random_state,
    )
    elasticnet_pipeline = Pipeline(
        [("preprocessor", _IdentityPreprocessor()), ("model", elasticnet_cv)]
    )
    elasticnet_pipeline.fit(X, y)
    regularized["ElasticNetCV"] = elasticnet_pipeline

    return regularized
