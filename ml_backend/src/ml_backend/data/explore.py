"""Data exploration utilities for HomeValue ML Backend."""

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from ml_backend.config import config


def explore_dataset(df: pd.DataFrame) -> dict[str, Any]:
    """
    Perform basic exploratory data analysis on a DataFrame.

    Args:
        df: DataFrame to explore

    Returns:
        Dictionary with exploration results
    """
    result = {
        "shape": df.shape,
        "dtypes": df.dtypes.astype(str).to_dict(),
        "missing_counts": df.isnull().sum().to_dict(),
        "missing_percentages": (df.isnull().sum() / len(df) * 100).round(2).to_dict(),
        "describe": {},
        "correlations": {},
        "unique_counts": df.nunique().to_dict(),
    }

    # Describe numeric columns
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    if len(numeric_cols) > 0:
        result["describe"] = df[numeric_cols].describe().to_dict()

        # Correlation matrix for numeric columns
        if len(numeric_cols) > 1:
            corr_matrix = df[numeric_cols].corr()
            result["correlations"] = corr_matrix.round(4).to_dict()

    # Describe categorical columns
    categorical_cols = df.select_dtypes(include=["object", "category"]).columns
    if len(categorical_cols) > 0:
        cat_describe = {}
        for col in categorical_cols:
            cat_describe[col] = {
                "unique": df[col].nunique(),
                "top": df[col].mode().iloc[0] if not df[col].mode().empty else None,
                "freq": df[col].value_counts().iloc[0] if not df[col].empty else 0,
            }
        result["categorical_describe"] = cat_describe

    return result


def save_exploration_plots(df: pd.DataFrame, target_col: str | None = None) -> list[Path]:
    """
    Save exploration plots to data/exploration/ directory.

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

    exploration_dir = config.data_dir / "exploration"
    exploration_dir.mkdir(parents=True, exist_ok=True)

    saved_paths = []

    # Target distribution plot
    if target_col and target_col in df.columns:
        fig, ax = plt.subplots(figsize=(10, 6))
        sns.histplot(data=df, x=target_col, kde=True, ax=ax)
        ax.set_title(f"Distribution of {target_col}")
        path = exploration_dir / f"target_distribution_{target_col}.png"
        fig.savefig(path, dpi=150, bbox_inches="tight")
        plt.close(fig)
        saved_paths.append(path)

    # Correlation heatmap
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    if len(numeric_cols) > 1:
        fig, ax = plt.subplots(figsize=(12, 10))
        corr_matrix = df[numeric_cols].corr()
        sns.heatmap(corr_matrix, annot=False, cmap="coolwarm", center=0, ax=ax)
        ax.set_title("Feature Correlation Matrix")
        path = exploration_dir / "correlation_heatmap.png"
        fig.savefig(path, dpi=150, bbox_inches="tight")
        plt.close(fig)
        saved_paths.append(path)

    # Missing values heatmap
    if df.isnull().any().any():
        fig, ax = plt.subplots(figsize=(12, 8))
        sns.heatmap(df.isnull(), cbar=False, yticklabels=False, ax=ax)
        ax.set_title("Missing Values Pattern")
        path = exploration_dir / "missing_values_heatmap.png"
        fig.savefig(path, dpi=150, bbox_inches="tight")
        plt.close(fig)
        saved_paths.append(path)

    return saved_paths
