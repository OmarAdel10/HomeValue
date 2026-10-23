"""Data exploration utilities for HomeValue ML Backend."""

import logging
import re
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from ml_backend.config import config

logger = logging.getLogger(__name__)

_MAX_HEATMAP_FEATURES = 100
_MAX_HEATMAP_ROWS = 5_000
_MAX_SLUG_LENGTH = 80


def _safe_filename_part(value: str) -> str:
    """Reduce an arbitrary column name to a safe, bounded filename fragment."""
    slug = re.sub(r"[^A-Za-z0-9_-]+", "_", value).strip("_")
    return (slug or "target")[:_MAX_SLUG_LENGTH]


def explore_dataset(df: pd.DataFrame) -> dict[str, Any]:
    """
    Perform basic exploratory data analysis on a DataFrame.

    Args:
        df: DataFrame to explore

    Returns:
        Dictionary with exploration results
    """
    result: dict[str, Any] = {
        "shape": df.shape,
        "dtypes": df.dtypes.astype(str).to_dict(),
        "missing_counts": df.isnull().sum().to_dict(),
        "missing_percentages": (
            (df.isnull().sum() / len(df) * 100).round(2).to_dict() if len(df) else {}
        ),
        "describe": {},
        "correlations": {},
        "unique_counts": df.nunique().to_dict(),
    }

    # Describe numeric columns
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    if len(numeric_cols) > 0:
        result["describe"] = df[numeric_cols].describe().to_dict()

        # Correlation matrix for numeric columns (bounded for wide frames)
        if 1 < len(numeric_cols) <= _MAX_HEATMAP_FEATURES:
            corr_matrix = df[numeric_cols].corr()
            result["correlations"] = corr_matrix.round(4).to_dict()

    # Describe categorical columns
    categorical_cols = df.select_dtypes(include=["object", "string", "category"]).columns
    if len(categorical_cols) > 0:
        cat_describe = {}
        for col in categorical_cols:
            value_counts = df[col].value_counts()
            modes = df[col].mode()
            cat_describe[col] = {
                "unique": df[col].nunique(),
                "top": modes.iloc[0] if not modes.empty else None,
                "freq": int(value_counts.iloc[0]) if not value_counts.empty else 0,
            }
        result["categorical_describe"] = cat_describe

    return result


def save_exploration_plots(df: pd.DataFrame, target_col: str | None = None) -> list[Path]:
    """
    Save exploration plots to data/exploration/.

    Plotting is imported lazily so the base package does not require the
    optional visualisation dependencies.

    Args:
        df: DataFrame to plot
        target_col: Optional target column name for target-specific plots

    Returns:
        List of saved plot file paths
    """
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import seaborn as sns

    exploration_dir = (config.data_dir / "exploration").resolve()
    exploration_dir.mkdir(parents=True, exist_ok=True, mode=0o750)

    if target_col is not None and target_col not in df.columns:
        logger.warning("Target column %r is not present; skipping its plot", target_col)

    saved_paths: list[Path] = []

    # Target distribution plot
    if target_col and target_col in df.columns:
        path = exploration_dir / f"target_distribution_{_safe_filename_part(target_col)}.png"
        fig, ax = plt.subplots(figsize=(10, 6))
        try:
            target = df[target_col]
            sns.histplot(
                data=df,
                x=target_col,
                kde=bool(pd.api.types.is_numeric_dtype(target)),
                ax=ax,
            )
            ax.set_title(f"Distribution of {target_col}")
            fig.savefig(path, dpi=150, bbox_inches="tight")
        finally:
            plt.close(fig)
        saved_paths.append(path)

    numeric_cols = df.select_dtypes(include=[np.number]).columns

    # Correlation heatmap (skipped for very wide frames to bound memory use)
    if 1 < len(numeric_cols) <= _MAX_HEATMAP_FEATURES:
        path = exploration_dir / "correlation_heatmap.png"
        fig, ax = plt.subplots(figsize=(12, 10))
        try:
            sns.heatmap(df[numeric_cols].corr(), annot=False, cmap="coolwarm", center=0, ax=ax)
            ax.set_title("Feature Correlation Matrix")
            fig.savefig(path, dpi=150, bbox_inches="tight")
        finally:
            plt.close(fig)
        saved_paths.append(path)

    # Missing values heatmap (row-capped to bound rendering memory)
    if df.isnull().any().any():
        path = exploration_dir / "missing_values_heatmap.png"
        fig, ax = plt.subplots(figsize=(12, 8))
        try:
            sns.heatmap(df.isnull().iloc[:_MAX_HEATMAP_ROWS], cbar=False, yticklabels=False, ax=ax)
            ax.set_title("Missing Values Pattern")
            fig.savefig(path, dpi=150, bbox_inches="tight")
        finally:
            plt.close(fig)
        saved_paths.append(path)

    return saved_paths
