"""Tests for the data loading module."""

import os
import stat
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


def _california_frame(n_rows: int = 10, include_target: bool = True) -> pd.DataFrame:
    frame = pd.DataFrame(
        {
            "MedInc": [3.0 + i for i in range(n_rows)],
            "HouseAge": [20.0 + i for i in range(n_rows)],
            "AveRooms": [5.0 + i for i in range(n_rows)],
            "AveBedrms": [1.0 + i for i in range(n_rows)],
            "Population": [1000.0 + i for i in range(n_rows)],
            "AveOccup": [2.5 + i for i in range(n_rows)],
            "Latitude": [34.0 + i for i in range(n_rows)],
            "Longitude": [-118.0 + i for i in range(n_rows)],
        }
    )
    if include_target:
        frame["MedHouseVal"] = [1.5 + i for i in range(n_rows)]
    return frame


def _ames_frame(n_rows: int = 10) -> pd.DataFrame:
    """Build an OpenML-shaped frame: the target is embedded as Sale_Price."""
    return pd.DataFrame(
        {
            "MSSubClass": [60] * n_rows,
            "LotArea": [8000 + i for i in range(n_rows)],
            "Sale_Price": [200000.0 + i for i in range(n_rows)],
        }
    )


def _ames_target(frame: pd.DataFrame) -> pd.Series:
    return frame["Sale_Price"].astype(float).rename("Sale_Price")


def test_get_cache_path_uses_parquet_suffix(cache_dir):
    assert loader._get_cache_path("demo") == cache_dir / "demo.parquet"
    assert loader._get_checksum_path("demo") == cache_dir / "demo.parquet.sha256"


def test_cache_roundtrip_writes_checksum_and_restricted_permissions(cache_dir):
    frame = _california_frame()

    loader._save_to_cache(frame, "demo")

    cache_path = cache_dir / "demo.parquet"
    checksum_path = cache_dir / "demo.parquet.sha256"
    assert stat.S_IMODE(cache_path.stat().st_mode) == 0o640
    assert stat.S_IMODE(checksum_path.stat().st_mode) == 0o640
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


def test_load_from_cache_discards_unverified_legacy_cache(cache_dir):
    frame = _california_frame()
    frame.to_parquet(cache_dir / "legacy.parquet")

    assert loader._load_from_cache("legacy") is None
    assert not (cache_dir / "legacy.parquet").exists()


def test_load_from_cache_discards_corrupt_parquet_with_matching_checksum(cache_dir):
    cache_path = cache_dir / "corrupt.parquet"
    cache_path.write_bytes(b"garbage")
    (cache_dir / "corrupt.parquet.sha256").write_text(loader._sha256(cache_path), encoding="utf-8")

    assert loader._load_from_cache("corrupt") is None
    assert not cache_path.exists()


def test_load_california_housing_fetches_then_serves_from_cache(cache_dir, monkeypatch):
    frame = _california_frame()
    calls = []

    def fake_fetch(**kwargs):
        calls.append(kwargs)
        return SimpleNamespace(frame=frame)

    monkeypatch.setattr(loader, "fetch_california_housing", fake_fetch)

    X, y = loader.load_california_housing()

    assert len(calls) == 1
    assert calls[0]["as_frame"] is True
    assert calls[0]["n_retries"] == loader._FETCH_RETRIES
    assert calls[0]["data_home"] == str(cache_dir / "sklearn")
    assert (cache_dir / "california_housing.parquet").exists()
    assert "MedHouseVal" not in X.columns
    assert y.name == "MedHouseVal"
    assert len(X) == len(y) == len(frame)

    monkeypatch.setattr(
        loader, "fetch_california_housing", lambda **kwargs: pytest.fail("cache miss")
    )
    X_cached, y_cached = loader.load_california_housing()
    pd.testing.assert_frame_equal(X_cached, X)
    pd.testing.assert_series_equal(y_cached, y)


def test_load_california_housing_rejects_cache_without_target(cache_dir):
    loader._save_to_cache(_california_frame(include_target=False), "california_housing")

    with pytest.raises(ValueError, match="MedHouseVal"):
        loader.load_california_housing()


def test_load_ames_housing_drops_all_target_aliases(cache_dir, monkeypatch):
    frame = _ames_frame()
    target = _ames_target(frame)
    captured = {}

    def fake_fetch(**kwargs):
        captured.update(kwargs)
        return SimpleNamespace(frame=frame, target=target)

    monkeypatch.setattr(loader, "fetch_openml", fake_fetch)

    X, y = loader.load_ames_housing()

    assert captured["name"] == "ames_housing"
    assert captured["n_retries"] == loader._FETCH_RETRIES
    assert y.name == "SalePrice"
    assert y.dtype == float
    assert "SalePrice" not in X.columns
    assert "Sale_Price" not in X.columns
    assert len(X) == len(y) == len(frame)

    cached = pd.read_parquet(cache_dir / "ames_housing.parquet")
    assert "SalePrice" in cached.columns
    assert "Sale_Price" not in cached.columns

    monkeypatch.setattr(loader, "fetch_openml", lambda **kwargs: pytest.fail("cache miss"))
    X_cached, y_cached = loader.load_ames_housing()
    pd.testing.assert_frame_equal(X_cached, X)
    pd.testing.assert_series_equal(y_cached, y)


def test_load_ames_housing_renames_legacy_cache_target(cache_dir):
    frame = _ames_frame()
    loader._save_to_cache(frame, "ames_housing")

    X, y = loader.load_ames_housing()

    assert y.name == "SalePrice"
    assert "Sale_Price" not in X.columns
    assert "SalePrice" not in X.columns


def test_load_ames_housing_drops_duplicate_target_aliases(cache_dir):
    frame = _ames_frame()
    frame["SalePrice"] = frame["Sale_Price"]
    loader._save_to_cache(frame, "ames_housing")

    X, y = loader.load_ames_housing()

    assert y.name == "SalePrice"
    assert "Sale_Price" not in X.columns
    assert "SalePrice" not in X.columns


def test_load_ames_housing_rejects_cache_without_target(cache_dir):
    loader._save_to_cache(pd.DataFrame({"MSSubClass": [60], "LotArea": [8000]}), "ames_housing")

    with pytest.raises(ValueError, match="SalePrice"):
        loader.load_ames_housing()


def test_load_ames_housing_rejects_fetch_without_target(cache_dir, monkeypatch):
    monkeypatch.setattr(
        loader,
        "fetch_openml",
        lambda **kwargs: SimpleNamespace(frame=_ames_frame(), target=None),
    )

    with pytest.raises(ValueError, match="no target"):
        loader.load_ames_housing()
    assert not (cache_dir / "ames_housing.parquet").exists()


def test_validate_frame_accepts_frame_within_limits():
    frame = _california_frame(3)
    assert loader._validate_frame(frame, "ok") is frame


def test_validate_frame_rejects_empty_frame():
    with pytest.raises(ValueError, match="empty"):
        loader._validate_frame(pd.DataFrame(), "empty")


def test_validate_frame_rejects_oversized_row_count(monkeypatch):
    monkeypatch.setattr(loader, "_MAX_ROWS", 2)
    with pytest.raises(ValueError, match="safety limits"):
        loader._validate_frame(pd.DataFrame({"a": [1, 2, 3]}), "tall")


def test_validate_frame_rejects_oversized_column_count():
    frame = pd.DataFrame({f"c{i}": [1.0] for i in range(loader._MAX_COLUMNS + 1)})
    with pytest.raises(ValueError, match="safety limits"):
        loader._validate_frame(frame, "wide")


def test_split_target_rejects_non_numeric_target():
    frame = pd.DataFrame({"feature": [1.0], "target": ["high"]})
    with pytest.raises(ValueError, match="non-numeric"):
        loader._split_target(frame, "target", "demo")


def test_load_california_housing_rejects_non_numeric_cached_target(cache_dir):
    frame = _california_frame()
    frame["MedHouseVal"] = ["high"] * len(frame)
    loader._save_to_cache(frame, "california_housing")

    with pytest.raises(ValueError, match="non-numeric"):
        loader.load_california_housing()


@pytest.mark.integration
@pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION") != "1", reason="set RUN_INTEGRATION=1 to hit the network"
)
def test_load_california_housing_real_dataset():
    X, y = loader.load_california_housing()
    assert X.shape[0] == y.shape[0] > 0
    assert y.name == "MedHouseVal"
