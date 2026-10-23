"""Preprocessing pipeline construction for HomeValue."""

from collections.abc import Sequence

from sklearn.compose import ColumnTransformer  # type: ignore[import-untyped]
from sklearn.impute import SimpleImputer  # type: ignore[import-untyped]
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]
from sklearn.preprocessing import OneHotEncoder, StandardScaler  # type: ignore[import-untyped]

from ml_backend.preprocessing.transformers import (
    FeatureEngineeringTransformer,
    infer_feature_types,
)

_ENGINEERING_COLUMNS = frozenset({"AveRooms", "AveBedrms", "Population", "AveOccup"})

__all__ = ["build_preprocessing_pipeline", "infer_feature_types"]


def build_preprocessing_pipeline(
    numeric_features: Sequence[str],
    categorical_features: Sequence[str] = (),
) -> ColumnTransformer:
    """Build an unfitted preprocessing pipeline.

    Numeric features are imputed with the median and standardized; categorical
    features are imputed with the most frequent value and one-hot encoded with
    the first level dropped. Columns outside the declared lists are discarded.

    The feature-engineering step is only added when the California housing
    columns it needs are present, so the same builder serves Ames housing.
    """
    numeric = list(numeric_features)
    categorical = list(categorical_features)
    if not numeric and not categorical:
        raise ValueError("At least one feature is required to build a pipeline")

    overlap = sorted(set(numeric) & set(categorical))
    if overlap:
        raise ValueError(f"Features declared as both numeric and categorical: {overlap}")

    transformers: list[tuple[str, object, list[str]]] = []

    if numeric:
        numeric_steps: list[tuple[str, object]] = []
        if _ENGINEERING_COLUMNS.issubset(numeric):
            numeric_steps.append(("engineer", FeatureEngineeringTransformer()))
        numeric_steps.extend(
            [
                ("imputer", SimpleImputer(strategy="median")),
                ("scaler", StandardScaler()),
            ]
        )
        transformers.append(("numeric", Pipeline(numeric_steps), numeric))

    if categorical:
        categorical_steps = [
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("encoder", OneHotEncoder(drop="first", handle_unknown="ignore")),
        ]
        transformers.append(("categorical", Pipeline(categorical_steps), categorical))

    return ColumnTransformer(transformers, remainder="drop")
