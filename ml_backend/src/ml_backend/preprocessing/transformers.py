"""Custom scikit-learn transformers for HomeValue."""

from collections.abc import Hashable, Sequence
from typing import Self

import numpy as np
import pandas as pd
from pandas.api.types import (
    is_bool_dtype,
    is_numeric_dtype,
    is_object_dtype,
    is_string_dtype,
)
from sklearn.base import BaseEstimator, TransformerMixin  # type: ignore[import-untyped]
from sklearn.utils.validation import check_is_fitted  # type: ignore[import-untyped]

_REQUIRED_COLUMNS = ("AveRooms", "AveBedrms", "Population", "AveOccup")
_ENGINEERED_COLUMNS = ("rooms_per_person", "bedrooms_per_room", "households")


class FeatureEngineeringTransformer(TransformerMixin, BaseEstimator):
    """Add non-redundant ratio features derived from the California schema.

    The bundled California dataset stores per-household averages rather than
    raw totals, so the literal Week 02 features ``rooms_per_household`` and
    ``population_per_household`` would duplicate ``AveRooms`` and ``AveOccup``.
    This transformer instead derives the quantities that add information:
    rooms per person, bedrooms per room, and the implied household count.
    """

    def fit(self, X: pd.DataFrame, y: pd.Series | None = None) -> Self:
        """Validate the input schema and record feature metadata."""
        self._validate(X)
        self.n_features_in_ = X.shape[1]
        self.feature_names_in_ = np.asarray(X.columns, dtype=object)
        return self

    def transform(self, X: pd.DataFrame) -> pd.DataFrame:
        """Return a copy of ``X`` with the engineered ratio columns appended."""
        check_is_fitted(self, attributes=["n_features_in_"])
        self._validate(X)
        if list(X.columns) != list(self.feature_names_in_):
            raise ValueError(
                "FeatureEngineeringTransformer input columns changed since fit: "
                f"expected {list(self.feature_names_in_)}, got {list(X.columns)}"
            )
        collisions = sorted(set(_ENGINEERED_COLUMNS) & set(X.columns))
        if collisions:
            raise ValueError(f"Engineered columns already present in input: {collisions}")

        engineered = pd.DataFrame(
            {
                "rooms_per_person": X["AveRooms"] / X["AveOccup"],
                "bedrooms_per_room": X["AveBedrms"] / X["AveRooms"],
                "households": X["Population"] / X["AveOccup"],
            },
            index=X.index,
        )
        engineered = engineered.replace([np.inf, -np.inf], np.nan)
        return pd.concat([X, engineered], axis=1)

    def get_feature_names_out(self, input_features: Sequence[Hashable] | None = None) -> np.ndarray:
        """Return output feature names, including the engineered columns."""
        check_is_fitted(self, attributes=["feature_names_in_"])
        if input_features is None:
            names = np.asarray(self.feature_names_in_, dtype=object)
        else:
            names = np.asarray(input_features, dtype=object)
            if len(names) != len(self.feature_names_in_):
                raise ValueError(
                    "Number of input feature names does not match fitted features: "
                    f"expected {len(self.feature_names_in_)}, got {len(names)}"
                )
        return np.asarray([*names, *_ENGINEERED_COLUMNS], dtype=object)

    @staticmethod
    def _validate(X: pd.DataFrame) -> None:
        if not isinstance(X, pd.DataFrame):
            raise TypeError("FeatureEngineeringTransformer expects a pandas DataFrame")
        missing = [column for column in _REQUIRED_COLUMNS if column not in X.columns]
        if missing:
            raise ValueError(f"Missing required columns for feature engineering: {missing}")


def infer_feature_types(X: pd.DataFrame) -> tuple[list[Hashable], list[Hashable]]:
    """Split DataFrame columns into numeric and categorical feature labels.

    Boolean and datetime-like columns are rejected explicitly instead of being
    silently dropped, so callers must declare how those columns are encoded.
    """
    if not isinstance(X, pd.DataFrame):
        raise TypeError("infer_feature_types expects a pandas DataFrame")

    numeric: list[Hashable] = []
    categorical: list[Hashable] = []
    unsupported: list[tuple[Hashable, str]] = []

    for column, dtype in X.dtypes.items():
        if (
            isinstance(dtype, pd.CategoricalDtype)
            or is_object_dtype(dtype)
            or is_string_dtype(dtype)
        ):
            categorical.append(column)
        elif is_numeric_dtype(dtype) and not is_bool_dtype(dtype):
            numeric.append(column)
        else:
            unsupported.append((column, str(dtype)))

    if unsupported:
        details = ", ".join(f"{column!r} ({dtype})" for column, dtype in unsupported)
        raise ValueError(f"Unsupported column dtypes for preprocessing: {details}")

    return numeric, categorical
