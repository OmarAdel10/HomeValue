"""Tests for data exploration module."""

import numpy as np
import pandas as pd

from ml_backend.data.explore import explore_dataset


def test_explore_returns_stats_dict():
    """Test that explore_dataset returns a dict with expected keys."""
    np.random.seed(42)
    df = pd.DataFrame(
        {
            "numeric_1": np.random.randn(100),
            "numeric_2": np.random.randn(100),
            "categorical": np.random.choice(["A", "B", "C"], 100),
        }
    )

    result = explore_dataset(df)

    assert isinstance(result, dict)
    assert "shape" in result
    assert "dtypes" in result
    assert "missing_counts" in result
    assert "describe" in result
    assert "correlations" in result
    assert result["shape"] == (100, 3)


def test_explore_handles_missing_values():
    """Test that explore_dataset reports missing values correctly."""
    df = pd.DataFrame(
        {
            "col1": [1, 2, np.nan, 4],
            "col2": [np.nan, np.nan, np.nan, np.nan],
            "col3": [1, 2, 3, 4],
        }
    )

    result = explore_dataset(df)

    assert result["missing_counts"]["col1"] == 1
    assert result["missing_counts"]["col2"] == 4
    assert result["missing_counts"]["col3"] == 0


def test_explore_categorical_columns():
    """Test that explore_dataset handles categorical columns."""
    df = pd.DataFrame(
        {
            "cat": pd.Categorical(["A", "B", "A", "C"]),
            "num": [1, 2, 3, 4],
        }
    )

    result = explore_dataset(df)

    assert "cat" in result["dtypes"]
    assert str(result["dtypes"]["cat"]).startswith("category")


def test_explore_empty_dataframe():
    """Test that explore_dataset handles empty DataFrame."""
    df = pd.DataFrame()
    result = explore_dataset(df)

    assert result["shape"] == (0, 0)
    assert result["describe"] == {}
