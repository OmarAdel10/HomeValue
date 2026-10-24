"""Preprocessing pipeline construction for HomeValue."""

from collections.abc import Hashable, Sequence
from typing import Self

import numpy as np
import pandas as pd
from sklearn.base import BaseEstimator, TransformerMixin  # type: ignore[import-untyped]
from sklearn.compose import ColumnTransformer  # type: ignore[import-untyped]
from sklearn.impute import SimpleImputer  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]
from sklearn.preprocessing import (  # type: ignore[import-untyped]
    FunctionTransformer,
    OneHotEncoder,
    StandardScaler,
)

from ml_backend.preprocessing.transformers import (
    _REQUIRED_COLUMNS,
    FeatureEngineeringTransformer,
    infer_feature_types,
)

__all__ = ["build_preprocessing_pipeline", "infer_feature_types"]


def _to_object_with_nan(X: pd.DataFrame) -> pd.DataFrame:
    """Convert nullable dtypes to object with ``np.nan`` for the imputer."""
    return X.astype(object).where(pd.notna(X), np.nan)


class _AllMissingCategoricalGuard(TransformerMixin, BaseEstimator):
    """Fail closed when a declared categorical column has no observed values."""

    def fit(self, X: pd.DataFrame, y: pd.Series | None = None) -> Self:
        """Reject categorical columns that are entirely missing."""
        if isinstance(X, pd.DataFrame):
            empty = [column for column in X.columns if X[column].isna().all()]
            if empty:
                raise ValueError(
                    "Categorical features have no observed values: "
                    f"{list(empty)}; populate or drop them from categorical_features"
                )
        self.n_features_in_ = X.shape[1]
        self.feature_names_in_ = np.asarray(getattr(X, "columns", []), dtype=object)
        return self

    def transform(self, X: pd.DataFrame) -> pd.DataFrame:
        """Pass the validated categorical frame through unchanged."""
        return X

    def get_feature_names_out(self, input_features: Sequence[Hashable] | None = None) -> np.ndarray:
        """Return unchanged feature names."""
        if input_features is not None:
            return np.asarray(input_features, dtype=object)
        return np.asarray(self.feature_names_in_, dtype=object)


def _validate_feature_argument(features: Sequence[Hashable], label: str) -> list[Hashable]:
    """Normalize a feature sequence and reject bare strings."""
    if isinstance(features, (str, bytes)):
        raise TypeError(
            f"{label}_features must be a sequence of column labels, not a single string"
        )
    return list(features)


def build_preprocessing_pipeline(
    numeric_features: Sequence[Hashable],
    categorical_features: Sequence[Hashable] = (),
    *,
    feature_engineering: bool | None = None,
) -> ColumnTransformer:
    """Build an unfitted preprocessing pipeline.

    Numeric features are imputed with the median and standardized; categorical
    features are imputed with the most frequent value and one-hot encoded. All
    levels are kept because dropping a reference level would make an unseen
    category indistinguishable from that reference. Columns outside the
    declared lists are discarded.

    Feature engineering is enabled automatically when all California source
    columns are declared. Passing ``None`` with a partial source set raises,
    ``True`` requires every source column, and ``False`` disables the step.
    """
    numeric = _validate_feature_argument(numeric_features, "numeric")
    categorical = _validate_feature_argument(categorical_features, "categorical")
    if not numeric and not categorical:
        raise ValueError("At least one feature is required to build a pipeline")

    for label, features in (("numeric", numeric), ("categorical", categorical)):
        duplicates = sorted(
            {feature for feature in features if features.count(feature) > 1}, key=str
        )
        if duplicates:
            raise ValueError(f"Duplicate {label} features: {duplicates}")

    overlap = sorted(set(numeric) & set(categorical), key=str)
    if overlap:
        raise ValueError(f"Features declared as both numeric and categorical: {overlap}")

    present = [column for column in _REQUIRED_COLUMNS if column in numeric]
    engineering_available = len(present) == len(_REQUIRED_COLUMNS)
    if feature_engineering is True and not engineering_available:
        missing = [column for column in _REQUIRED_COLUMNS if column not in numeric]
        raise ValueError(
            f"Feature engineering requires {list(_REQUIRED_COLUMNS)}; missing {missing}"
        )
    if feature_engineering is None:
        if present and not engineering_available:
            raise ValueError(
                "Feature engineering receives a partial set of source columns; pass all "
                f"of {list(_REQUIRED_COLUMNS)} or feature_engineering=False"
            )
        engineer = engineering_available
    else:
        engineer = feature_engineering

    transformers: list[tuple[str, object, list[Hashable]]] = []

    if numeric:
        numeric_steps: list[tuple[str, object]] = []
        if engineer:
            numeric_steps.append(("engineer", FeatureEngineeringTransformer()))
        numeric_steps.extend(
            [
                ("imputer", SimpleImputer(strategy="median", keep_empty_features=True)),
                ("scaler", StandardScaler()),
            ]
        )
        transformers.append(("numeric", Pipeline(numeric_steps), numeric))

    if categorical:
        categorical_steps = [
            ("guard", _AllMissingCategoricalGuard()),
            ("normalize", FunctionTransformer(_to_object_with_nan, feature_names_out="one-to-one")),
            (
                "imputer",
                SimpleImputer(strategy="most_frequent", keep_empty_features=True),
            ),
            ("encoder", OneHotEncoder(handle_unknown="ignore")),
        ]
        transformers.append(("categorical", Pipeline(categorical_steps), categorical))

    return ColumnTransformer(transformers, remainder="drop")
