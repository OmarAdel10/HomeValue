"""Pytest configuration and shared fixtures."""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ml_backend.config import config


@pytest.fixture(scope="session")
def test_config():
    """Provide test configuration."""
    return config


@pytest.fixture
def sample_housing_data():
    """Create sample housing data for testing."""
    np.random.seed(42)
    n_samples = 100
    return pd.DataFrame(
        {
            "MedInc": np.random.uniform(0.5, 15.0, n_samples),
            "HouseAge": np.random.uniform(1.0, 52.0, n_samples),
            "AveRooms": np.random.uniform(2.0, 10.0, n_samples),
            "AveBedrooms": np.random.uniform(0.5, 5.0, n_samples),
            "Population": np.random.uniform(100, 5000, n_samples),
            "AveOccup": np.random.uniform(0.5, 10.0, n_samples),
            "Latitude": np.random.uniform(32.5, 42.0, n_samples),
            "Longitude": np.random.uniform(-124.5, -114.0, n_samples),
            "ocean_proximity": np.random.choice(
                ["<1H OCEAN", "INLAND", "NEAR OCEAN", "NEAR BAY", "ISLAND"], n_samples
            ),
        }
    )


@pytest.fixture
def sample_target():
    """Create sample target values."""
    np.random.seed(42)
    return pd.Series(np.random.uniform(0.5, 5.0, 100), name="MedHouseVal")


@pytest.fixture
def trained_pipeline(sample_housing_data, sample_target):
    """Create a simple trained pipeline for testing."""
    from sklearn.compose import ColumnTransformer
    from sklearn.impute import SimpleImputer
    from sklearn.linear_model import LinearRegression
    from sklearn.pipeline import Pipeline
    from sklearn.preprocessing import OneHotEncoder, StandardScaler

    numeric_features = [
        "MedInc",
        "HouseAge",
        "AveRooms",
        "AveBedrooms",
        "Population",
        "AveOccup",
        "Latitude",
        "Longitude",
    ]
    categorical_features = ["ocean_proximity"]

    numeric_transformer = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
        ]
    )

    categorical_transformer = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("encoder", OneHotEncoder(drop="first", handle_unknown="ignore")),
        ]
    )

    preprocessor = ColumnTransformer(
        [
            ("num", numeric_transformer, numeric_features),
            ("cat", categorical_transformer, categorical_features),
        ]
    )

    pipeline = Pipeline(
        [
            ("preprocessor", preprocessor),
            ("model", LinearRegression()),
        ]
    )

    pipeline.fit(sample_housing_data, sample_target)
    return pipeline
