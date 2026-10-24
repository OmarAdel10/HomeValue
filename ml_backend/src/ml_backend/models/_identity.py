"""Shared identity preprocessor for already-transformed data."""

from typing import Any

from sklearn.base import BaseEstimator, TransformerMixin  # type: ignore[import-untyped]


class _IdentityPreprocessor(TransformerMixin, BaseEstimator):
    """Pass-through preprocessor for already-transformed data."""

    def fit(self, X: Any, y: Any = None) -> "_IdentityPreprocessor":
        return self

    def transform(self, X: Any) -> Any:
        return X

    def get_feature_names_out(self, input_features: Any = None) -> Any:
        if input_features is None:
            return None
        return list(input_features)


__all__ = ["_IdentityPreprocessor"]
