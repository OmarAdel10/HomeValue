"""Data loading utilities for HomeValue ML Backend."""

from pathlib import Path

import pandas as pd
from sklearn.datasets import fetch_california_housing, fetch_openml  # type: ignore[import-untyped]

from ml_backend.config import config


def _get_cache_path(name: str) -> Path:
    """Get cache file path for dataset."""
    return config.data_dir / f"{name}.parquet"


def _save_to_cache(df: pd.DataFrame, name: str) -> None:
    """Save DataFrame to parquet cache."""
    cache_path = _get_cache_path(name)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(cache_path)


def _load_from_cache(name: str) -> pd.DataFrame | None:
    """Load DataFrame from parquet cache if exists."""
    cache_path = _get_cache_path(name)
    if cache_path.exists():
        return pd.read_parquet(cache_path)
    return None


def load_california_housing() -> tuple[pd.DataFrame, pd.Series]:
    """
    Load California Housing dataset.

    Returns:
        Tuple of (features DataFrame, target Series)
    """
    # Try cache first
    cached = _load_from_cache("california_housing")
    if cached is not None:
        X = cached.drop(columns=["MedHouseVal"])
        y = cached["MedHouseVal"]
        return X, y

    # Fetch from sklearn
    data = fetch_california_housing(as_frame=True)
    df = data.frame

    # Cache for future use
    _save_to_cache(df, "california_housing")

    X = df.drop(columns=["MedHouseVal"])
    y = df["MedHouseVal"]
    return X, y


def load_ames_housing() -> tuple[pd.DataFrame, pd.Series]:
    """
    Load Ames Housing dataset from OpenML.

    Returns:
        Tuple of (features DataFrame, target Series)
    """
    # Try cache first
    cached = _load_from_cache("ames_housing")
    if cached is not None:
        # Check if target column exists in cached data
        target_col = "Sale_Price" if "Sale_Price" in cached.columns else "SalePrice"
        if target_col in cached.columns:
            X = cached.drop(columns=[target_col])
            y = cached[target_col]
        else:
            X = cached
            y = pd.Series(dtype=float)
        return X, y

    # Fetch from OpenML
    data = fetch_openml(name="ames_housing", version=1, as_frame=True)
    df = data.frame
    target = data.target

    # Combine for caching
    df_with_target = df.copy()
    df_with_target["Sale_Price"] = target

    # Cache for future use
    _save_to_cache(df_with_target, "ames_housing")

    X = df
    y = target
    y.name = "Sale_Price"
    return X, y
