"""Custom scikit-learn transformers for HomeValue."""

from typing import Self

import numpy as np
import pandas as pd
from sklearn.base import BaseEstimator, TransformerMixin  # type: ignore[import-untyped]

_REQUIRED_COLUMNS = ("AveRooms", "AveBedrms", "Population", "AveOccup")


class FeatureEngineeringTransformer(TransformerMixin, BaseEstimator):
    """Add the Week 02 housing ratio features.

    ``rooms_per_household`` mirrors ``AveRooms`` because the bundled California
    dataset already stores per-household averages instead of raw totals.
    """

    def fit(self, X: pd.DataFrame, y: pd.Series | None = None) -> Self:
        """Validate the input schema."""
        self._validate(X)
        return self

    def transform(self, X: pd.DataFrame) -> pd.DataFrame:
        """Return a copy of ``X`` with the engineered ratio columns appended."""
        self._validate(X)
        engineered = X.copy()
        engineered["rooms_per_household"] = X["AveRooms"]
        engineered["bedrooms_per_room"] = X["AveBedrms"] / X["AveRooms"]
        engineered["population_per_household"] = X["Population"] / X["AveOccup"]
        return engineered.replace([np.inf, -np.inf], np.nan)

    @staticmethod
    def _validate(X: pd.DataFrame) -> None:
        if not isinstance(X, pd.DataFrame):
            raise TypeError("FeatureEngineeringTransformer expects a pandas DataFrame")
        missing = [column for column in _REQUIRED_COLUMNS if column not in X.columns]
        if missing:
            raise ValueError(f"Missing required columns for feature engineering: {missing}")


def infer_feature_types(X: pd.DataFrame) -> tuple[list[str], list[str]]:
    """Split DataFrame columns into numeric and categorical feature names."""
    numeric = [str(column) for column in X.select_dtypes(include=[np.number]).columns]
    categorical = [
        str(column) for column in X.select_dtypes(include=["object", "string", "category"]).columns
    ]
    return numeric, categorical
