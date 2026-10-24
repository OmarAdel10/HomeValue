"""Ensemble model training for HomeValue."""

import numpy as np
from sklearn.ensemble import (  # type: ignore[import-untyped]
    ExtraTreesRegressor,
    RandomForestRegressor,
    StackingRegressor,
    VotingRegressor,
)
from sklearn.linear_model import RidgeCV  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]

from ml_backend.config import Config
from ml_backend.models._identity import _IdentityPreprocessor


def train_ensembles(
    X: np.ndarray,
    y: np.ndarray,
    config: Config,
    base_estimators: dict,
) -> dict[str, Pipeline]:
    """Train ensemble models wrapped with an identity preprocessing pipeline.

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

    ensembles: dict[str, Pipeline] = {}

    # RandomForestRegressor
    rf = RandomForestRegressor(
        n_estimators=config.rf_n_estimators,
        max_features=config.rf_max_features,
        random_state=config.random_state,
        n_jobs=config.cv_n_jobs,
    )
    rf_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", rf)])
    rf_pipeline.fit(X, y)
    ensembles["RandomForestRegressor"] = rf_pipeline

    # ExtraTreesRegressor
    et = ExtraTreesRegressor(
        n_estimators=config.rf_n_estimators,
        max_features=config.rf_max_features,
        random_state=config.random_state,
        n_jobs=config.cv_n_jobs,
    )
    et_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", et)])
    et_pipeline.fit(X, y)
    ensembles["ExtraTreesRegressor"] = et_pipeline

    # VotingRegressor and StackingRegressor require base_estimators
    if base_estimators is not None:
        required_keys = {"rf", "ridge", "enet"}
        missing = required_keys - set(base_estimators.keys())
        if missing:
            raise ValueError(f"base_estimators missing required keys: {missing}")

        # VotingRegressor (hard voting by default)
        voting = VotingRegressor(
            estimators=[(name, base_estimators[name]) for name in ["rf", "ridge", "enet"]]
        )
        voting_pipeline = Pipeline([("preprocessor", _IdentityPreprocessor()), ("model", voting)])
        voting_pipeline.fit(X, y)
        ensembles["VotingRegressor"] = voting_pipeline

        # StackingRegressor with RidgeCV as final estimator
        stacking = StackingRegressor(
            estimators=[(name, base_estimators[name]) for name in ["rf", "ridge", "enet"]],
            final_estimator=RidgeCV(alphas=np.array(config.ridge_alphas), cv=config.cv_folds),
            cv=config.cv_folds,
            n_jobs=config.cv_n_jobs,
        )
        stacking_pipeline = Pipeline(
            [("preprocessor", _IdentityPreprocessor()), ("model", stacking)]
        )
        stacking_pipeline.fit(X, y)
        ensembles["StackingRegressor"] = stacking_pipeline

    return ensembles
