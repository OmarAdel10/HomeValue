"""Tests for the data loading module."""

import os
from types import SimpleNamespace

import pandas as pd
import pytest

from ml_backend.config import config
from ml_backend.data import loader


@pytest.fixture
def cache_dir(tmp_path, monkeypatch):
    """Redirect the dataset cache into a temporary directory."""
    monkeypatch.setattr(config, "data_dir", tmp_path)
    return tmp_path


def _california_frame(n_rows: int = 10) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "MedInc": [3.0 + i for i in range(n_rows)],
            "HouseAge": [20.0 + i for i in range(n_rows)],
            "AveRooms": [5.0 + i for i in range(n_rows)],
            "AveBedrms": [1.0 + i for i in range(n_rows)],
            "Population": [1000.0 + i for i in range(n_rows)],
            "AveOccup": [2.5 + i for i in range(n_rows)],
            "Latitude": [34.0 + i for i in range(n_rows)],
            "Longitude": [-118.0 + i for i in range(n_rows)],
            "MedHouseVal": [1.5 + i for i in range(n_rows)],
        }
    )


def _ames_frame(n_rows: int = 10) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "MSSubClass": [60] * n_rows,
            "LotArea": [8000 + i for i in range(n_rows)],
        }
    )


def test_get_cache_path_uses_parquet_suffix(cache_dir):
    assert loader._get_cache_path("demo") == cache_dir / "demo.parquet"


def test_cache_roundtrip_writes_checksum(cache_dir):
    frame = _california_frame()

    loader._save_to_cache(frame, "demo")

    assert (cache_dir / "demo.parquet").exists()
    assert (cache_dir / "demo.parquet.sha256").exists()
    pd.testing.assert_frame_equal(loader._load_from_cache("demo"), frame)


def test_load_from_cache_returns_none_when_missing(cache_dir):
    assert loader._load_from_cache("absent") is None


def test_load_from_cache_discards_tampered_file(cache_dir):
    frame = _california_frame()
    loader._save_to_cache(frame, "demo")
    (cache_dir / "demo.parquet").write_bytes(b"not a parquet file")

    assert loader._load_from_cache("demo") is None
    assert not (cache_dir / "demo.parquet").exists()
    assert not (cache_dir / "demo.parquet.sha256").exists()


def test_load_from_cache_accepts_legacy_cache_without_checksum(cache_dir):
    frame = _california_frame()
    frame.to_parquet(cache_dir / "legacy.parquet")

    loaded = loader._load_from_cache("legacy")

    assert loaded is not None
    pd.testing.assert_frame_equal(loaded, frame)


def test_load_california_housing_fetches_then_serves_from_cache(cache_dir, monkeypatch):
    frame = _california_frame()
    calls = []

    def fake_fetch(**kwargs):
        calls.append(kwargs)
        return SimpleNamespace(frame=frame)

    monkeypatch.setattr(loader, "fetch_california_housing", fake_fetch)

    X, y = loader.load_california_housing()

    assert calls and calls[0]["as_frame"] is True
    assert (cache_dir / "california_housing.parquet").exists()
    assert "MedHouseVal" not in X.columns
    assert y.name == "MedHouseVal"
    assert len(X) == len(y) == len(frame)

    def fail_fetch(**kwargs):
        raise AssertionError("cache should have been used")

    monkeypatch.setattr(loader, "fetch_california_housing", fail_fetch)
    X_cached, y_cached = loader.load_california_housing()
    pd.testing.assert_frame_equal(X_cached, X)
    pd.testing.assert_series_equal(y_cached, y)


def test_load_california_housing_rejects_cache_without_target(cache_dir):
    _california_frame().drop(columns=["MedHouseVal"]).to_parquet(
        cache_dir / "california_housing.parquet"
    )

    with pytest.raises(ValueError, match="MedHouseVal"):
        loader.load_california_housing()


def test_load_ames_housing_fetches_and_caches_target(cache_dir, monkeypatch):
    frame = _ames_frame()
    target = pd.Series([200000.0 + i for i in range(len(frame))], name="Sale_Price")

    def fake_fetch(**kwargs):
        return SimpleNamespace(frame=frame, target=target)

    monkeypatch.setattr(loader, "fetch_openml", fake_fetch)

    X, y = loader.load_ames_housing()

    assert y.name == "SalePrice"
    assert y.dtype == float
    assert "SalePrice" not in X.columns
    cached = pd.read_parquet(cache_dir / "ames_housing.parquet")
    assert "SalePrice" in cached.columns

    monkeypatch.setattr(loader, "fetch_openml", lambda **kwargs: pytest.fail("cache miss"))
    X_cached, y_cached = loader.load_ames_housing()
    pd.testing.assert_frame_equal(X_cached, X)
    pd.testing.assert_series_equal(y_cached, y)


def test_load_ames_housing_renames_legacy_target(cache_dir):
    frame = _ames_frame()
    frame["Sale_Price"] = [200000.0 + i for i in range(len(frame))]
    frame.to_parquet(cache_dir / "ames_housing.parquet")

    X, y = loader.load_ames_housing()

    assert y.name == "SalePrice"
    assert "Sale_Price" not in X.columns


def test_load_ames_housing_rejects_cache_without_target(cache_dir):
    _ames_frame().to_parquet(cache_dir / "ames_housing.parquet")

    with pytest.raises(ValueError, match="SalePrice"):
        loader.load_ames_housing()


def test_validate_frame_rejects_empty_and_oversized_frames():
    with pytest.raises(ValueError, match="empty"):
        loader._validate_frame(pd.DataFrame(), "empty")

    wide = pd.DataFrame({f"c{i}": [1.0] for i in range(loader._MAX_COLUMNS + 1)})
    with pytest.raises(ValueError, match="safety limits"):
        loader._validate_frame(wide, "wide")


@pytest.mark.integration
@pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION") != "1", reason="set RUN_INTEGRATION=1 to hit the network"
)
def test_load_california_housing_real_dataset():
    X, y = loader.load_california_housing()
    assert X.shape[0] == y.shape[0] > 0
    assert y.name == "MedHouseVal"
