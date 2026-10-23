"""Tests for the data exploration module."""

import numpy as np
import pandas as pd
import pytest

from ml_backend.config import config
from ml_backend.data import explore


@pytest.fixture
def plots_dir(tmp_path, monkeypatch):
    """Redirect exploration output into a temporary directory."""
    monkeypatch.setattr(config, "data_dir", tmp_path)
    return tmp_path


def test_explore_returns_stats_dict():
    np.random.seed(42)
    df = pd.DataFrame(
        {
            "numeric_1": np.random.randn(100),
            "numeric_2": np.random.randn(100),
            "categorical": np.random.choice(["A", "B", "C"], 100),
        }
    )

    result = explore.explore_dataset(df)

    assert isinstance(result, dict)
    assert result["shape"] == (100, 3)
    assert set(result["describe"]) == {"numeric_1", "numeric_2"}
    assert set(result["correlations"]) == {"numeric_1", "numeric_2"}
    assert result["correlations"]["numeric_1"]["numeric_2"] != 0


def test_explore_reports_missing_values_and_percentages():
    df = pd.DataFrame(
        {
            "col1": [1, 2, np.nan, 4],
            "col2": [np.nan, np.nan, np.nan, np.nan],
            "col3": [1, 2, 3, 4],
        }
    )

    result = explore.explore_dataset(df)

    assert result["missing_counts"] == {"col1": 1, "col2": 4, "col3": 0}
    assert result["missing_percentages"]["col1"] == 25.0
    assert result["missing_percentages"]["col2"] == 100.0
    assert result["unique_counts"] == {"col1": 3, "col2": 0, "col3": 4}


def test_explore_describes_object_columns():
    df = pd.DataFrame({"cat": ["A", "B", "A", "C"], "num": [1, 2, 3, 4]})

    result = explore.explore_dataset(df)

    assert result["categorical_describe"]["cat"] == {"unique": 3, "top": "A", "freq": 2}


def test_explore_handles_all_nan_categorical_column():
    df = pd.DataFrame({"cat": pd.Series([None, None], dtype="object")})

    result = explore.explore_dataset(df)

    assert result["categorical_describe"]["cat"] == {"unique": 0, "top": None, "freq": 0}


def test_explore_handles_categorical_dtype():
    df = pd.DataFrame({"cat": pd.Categorical(["A", "B", "A", "C"]), "num": [1, 2, 3, 4]})

    result = explore.explore_dataset(df)

    assert result["dtypes"]["cat"].startswith("category")
    assert result["categorical_describe"]["cat"]["freq"] == 2


def test_explore_single_numeric_column_has_no_correlations():
    result = explore.explore_dataset(pd.DataFrame({"num": [1.0, 2.0, 3.0]}))

    assert result["correlations"] == {}
    assert "categorical_describe" not in result


def test_explore_empty_dataframe():
    result = explore.explore_dataset(pd.DataFrame())

    assert result["shape"] == (0, 0)
    assert result["describe"] == {}
    assert result["missing_percentages"] == {}


def test_save_exploration_plots_writes_all_plots(plots_dir):
    df = pd.DataFrame(
        {
            "x": [1.0, 2.0, 3.0, 4.0],
            "y": [1.0, np.nan, 3.0, 4.0],
            "cat": ["A", "B", "A", "B"],
        }
    )

    paths = explore.save_exploration_plots(df, target_col="y")

    names = sorted(path.name for path in paths)
    assert names == [
        "correlation_heatmap.png",
        "missing_values_heatmap.png",
        "target_distribution_y.png",
    ]
    for path in paths:
        assert path.exists()
        assert path.stat().st_size > 0
        assert path.parent == (plots_dir / "exploration").resolve()


def test_save_exploration_plots_without_target_or_missing_values(plots_dir):
    df = pd.DataFrame({"x": [1.0, 2.0, 3.0], "y": [4.0, 5.0, 6.0]})

    paths = explore.save_exploration_plots(df)

    assert [path.name for path in paths] == ["correlation_heatmap.png"]


def test_save_exploration_plots_single_numeric_column(plots_dir):
    df = pd.DataFrame({"x": [1.0, 2.0, np.nan], "cat": ["A", "B", "A"]})

    paths = explore.save_exploration_plots(df)

    assert [path.name for path in paths] == ["missing_values_heatmap.png"]


def test_save_exploration_plots_without_numeric_columns(plots_dir):
    df = pd.DataFrame({"cat": ["A", "B", "A"]})

    assert explore.save_exploration_plots(df) == []


def test_save_exploration_plots_sanitizes_target_column_name(plots_dir):
    df = pd.DataFrame({"../evil": [1.0, 2.0, 3.0], "x": [4.0, 5.0, 6.0]})

    paths = explore.save_exploration_plots(df, target_col="../evil")

    assert paths[0].name == "target_distribution_evil.png"
    assert paths[0].parent == (plots_dir / "exploration").resolve()


def test_save_exploration_plots_closes_figures(plots_dir):
    import matplotlib.pyplot as plt

    df = pd.DataFrame({"x": [1.0, 2.0], "y": [3.0, 4.0]})
    explore.save_exploration_plots(df, target_col="y")

    assert plt.get_fignums() == []
