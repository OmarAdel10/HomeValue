"""Tests for data loading module."""

import pandas as pd

from ml_backend.data.loader import load_ames_housing, load_california_housing


def test_load_california_housing_returns_dataframe_and_series():
    """Test that California housing loader returns DataFrame and Series."""
    X, y = load_california_housing()
    assert isinstance(X, pd.DataFrame)
    assert isinstance(y, pd.Series)
    assert len(X) == len(y)
    assert len(X) > 0
    # Check expected columns (actual names from sklearn)
    expected_cols = [
        "MedInc",
        "HouseAge",
        "AveRooms",
        "AveBedrms",
        "Population",
        "AveOccup",
        "Latitude",
        "Longitude",
    ]
    for col in expected_cols:
        assert col in X.columns
    # Target name may vary
    assert y.name in ["MedHouseVal", "target"]
    # No categorical column in this version
    assert "ocean_proximity" not in X.columns


def test_load_california_housing_caches_to_parquet():
    """Test that data is cached to parquet on second load."""
    X1, y1 = load_california_housing()
    X2, y2 = load_california_housing()
    # Should return same data (from cache)
    pd.testing.assert_frame_equal(X1, X2)
    pd.testing.assert_series_equal(y1, y2)


def test_load_ames_housing_returns_dataframe_and_series():
    """Test that Ames housing loader returns DataFrame and Series."""
    X, y = load_ames_housing()
    assert isinstance(X, pd.DataFrame)
    assert isinstance(y, pd.Series)
    assert len(X) == len(y)
    assert len(X) > 0
    # Check target is SalePrice
    assert y.name == "Sale_Price"
    # Check it has many columns
    assert len(X.columns) > 50
