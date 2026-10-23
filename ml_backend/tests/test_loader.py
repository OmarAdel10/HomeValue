"""Tests for the data loading module."""

import hashlib
import os
import stat
from pathlib import Path
from types import SimpleNamespace

import pandas as pd
import pytest

from ml_backend.config import config
from ml_backend.data import loader


@pytest.fixture
def cache_dir(tmp_path, monkeypatch):
    """Redirect every dataset directory into a temporary directory."""
    monkeypatch.setattr(config, "data_dir", tmp_path / "data")
    monkeypatch.setattr(config, "models_dir", tmp_path / "models")
    monkeypatch.setattr(config, "logs_dir", tmp_path / "logs")
    config.data_dir.mkdir(parents=True, exist_ok=True)
    return config.data_dir


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


def _california_fetch(frame: pd.DataFrame):
    return lambda **kwargs: SimpleNamespace(frame=frame)


def test_get_cache_path_uses_parquet_suffix(cache_dir):
    assert loader._get_cache_path("demo") == cache_dir / "demo.parquet"
    assert loader._get_checksum_path("demo") == cache_dir / "demo.parquet.sha256"


def test_sha256_matches_known_vector(tmp_path):
    path = tmp_path / "vector.bin"
    path.write_bytes(b"abc")

    assert loader._sha256(path) == hashlib.sha256(b"abc").hexdigest()


def test_cache_roundtrip_writes_checksum_and_restricted_permissions(cache_dir):
    frame = _california_frame()

    loader._save_to_cache(frame, "demo")

    cache_path = cache_dir / "demo.parquet"
    checksum_path = cache_dir / "demo.parquet.sha256"
    assert stat.S_IMODE(cache_path.stat().st_mode) == 0o640
    assert stat.S_IMODE(checksum_path.stat().st_mode) == 0o640
    assert (
        checksum_path.read_text(encoding="utf-8")
        == hashlib.sha256(cache_path.read_bytes()).hexdigest()
    )
    pd.testing.assert_frame_equal(loader._load_from_cache("demo"), frame)


def test_save_to_cache_overwrites_previous_entry(cache_dir):
    loader._save_to_cache(_california_frame(3), "demo")
    replacement = _california_frame(4)
    loader._save_to_cache(replacement, "demo")

    pd.testing.assert_frame_equal(loader._load_from_cache("demo"), replacement)
    assert (cache_dir / "demo.parquet.sha256").read_text(encoding="utf-8") == (
        loader._sha256(cache_dir / "demo.parquet")
    )


def test_atomic_write_preserves_target_and_cleans_up_on_failure(cache_dir):
    target = cache_dir / "nested" / "stable.bin"
    target.parent.mkdir(parents=True)
    target.write_bytes(b"original")

    def failing_writer(path):
        path.write_bytes(b"partial")
        raise RuntimeError("writer failed")

    with pytest.raises(RuntimeError, match="writer failed"):
        loader._atomic_write(target, failing_writer)

    assert target.read_bytes() == b"original"
    assert list(target.parent.glob(".*.tmp")) == []


def test_discard_cache_tolerates_unlink_errors(cache_dir, monkeypatch):
    cache_path = cache_dir / "demo.parquet"
    cache_path.write_bytes(b"x")

    def failing_unlink(self, missing_ok=False):
        raise OSError("denied")

    monkeypatch.setattr(Path, "unlink", failing_unlink)

    loader._discard_cache("demo")

    assert cache_path.exists()


def test_load_from_cache_returns_none_when_missing(cache_dir):
    assert loader._load_from_cache("absent") is None


def test_load_from_cache_discards_tampered_file(cache_dir):
    loader._save_to_cache(_california_frame(), "demo")
    (cache_dir / "demo.parquet").write_bytes(b"not a parquet file")

    assert loader._load_from_cache("demo") is None
    assert not (cache_dir / "demo.parquet").exists()
    assert not (cache_dir / "demo.parquet.sha256").exists()


def test_load_from_cache_discards_unverified_legacy_cache(cache_dir):
    _california_frame().to_parquet(cache_dir / "legacy.parquet")

    assert loader._load_from_cache("legacy") is None
    assert not (cache_dir / "legacy.parquet").exists()


def test_load_from_cache_discards_corrupt_parquet_with_matching_checksum(cache_dir):
    cache_path = cache_dir / "corrupt.parquet"
    cache_path.write_bytes(b"garbage")
    (cache_dir / "corrupt.parquet.sha256").write_text(loader._sha256(cache_path), encoding="utf-8")

    assert loader._load_from_cache("corrupt") is None
    assert not cache_path.exists()
    assert not (cache_dir / "corrupt.parquet.sha256").exists()


def test_load_from_cache_tolerates_unreadable_checksum(cache_dir):
    loader._save_to_cache(_california_frame(), "demo")
    checksum_path = cache_dir / "demo.parquet.sha256"
    checksum_path.unlink()
    checksum_path.mkdir()

    assert loader._load_from_cache("demo") is None


def test_load_from_cache_tolerates_directory_in_place_of_parquet(cache_dir):
    cache_path = cache_dir / "directory.parquet"
    cache_path.mkdir()

    assert loader._load_from_cache("directory") is None
    assert not cache_path.exists()


def test_load_from_cache_rejects_empty_checksum(cache_dir):
    loader._save_to_cache(_california_frame(), "demo")
    (cache_dir / "demo.parquet.sha256").write_text("", encoding="utf-8")

    assert loader._load_from_cache("demo") is None


def test_load_california_housing_fetches_then_serves_from_cache(cache_dir, monkeypatch):
    frame = _california_frame()
    calls = []
    data_homes = []

    def fake_fetch(**kwargs):
        calls.append(kwargs)
        data_home = Path(kwargs["data_home"])
        assert data_home.is_dir()
        data_homes.append(data_home)
        return SimpleNamespace(frame=frame)

    monkeypatch.setattr(loader, "fetch_california_housing", fake_fetch)

    X, y = loader.load_california_housing()

    assert len(calls) == 1
    assert calls[0]["as_frame"] is True
    assert calls[0]["n_retries"] == loader._FETCH_RETRIES
    assert data_homes and not data_homes[0].exists()
    assert (cache_dir / "california_housing.parquet").exists()
    assert "MedHouseVal" not in X.columns
    assert y.name == "MedHouseVal"
    pd.testing.assert_frame_equal(X, frame.drop(columns=["MedHouseVal"]))
    pd.testing.assert_series_equal(y, frame["MedHouseVal"].rename("MedHouseVal"))

    monkeypatch.setattr(
        loader, "fetch_california_housing", lambda **kwargs: pytest.fail("cache miss")
    )
    X_cached, y_cached = loader.load_california_housing()
    pd.testing.assert_frame_equal(X_cached, X)
    pd.testing.assert_series_equal(y_cached, y)


def test_load_california_housing_recovers_from_invalid_cache(cache_dir, monkeypatch):
    loader._save_to_cache(_california_frame(include_target=False), "california_housing")
    replacement = _california_frame()
    monkeypatch.setattr(loader, "fetch_california_housing", _california_fetch(replacement))

    X, y = loader.load_california_housing()

    assert "MedHouseVal" not in X.columns
    assert y.name == "MedHouseVal"
    pd.testing.assert_frame_equal(
        pd.read_parquet(cache_dir / "california_housing.parquet"), replacement
    )


def test_load_california_housing_does_not_cache_invalid_fetch(cache_dir, monkeypatch):
    monkeypatch.setattr(
        loader,
        "fetch_california_housing",
        _california_fetch(_california_frame(include_target=False)),
    )

    with pytest.raises(ValueError, match="MedHouseVal"):
        loader.load_california_housing()

    assert not (cache_dir / "california_housing.parquet").exists()


def test_load_california_housing_rejects_non_numeric_cached_target(cache_dir, monkeypatch):
    bad = _california_frame()
    bad["MedHouseVal"] = ["high"] * len(bad)
    loader._save_to_cache(bad, "california_housing")
    monkeypatch.setattr(loader, "fetch_california_housing", _california_fetch(bad))

    with pytest.raises(ValueError, match="non-numeric"):
        loader.load_california_housing()


def test_load_california_housing_rejects_dropped_target_on_refetch(cache_dir, monkeypatch):
    loader._save_to_cache(_california_frame(include_target=False), "california_housing")
    monkeypatch.setattr(
        loader,
        "fetch_california_housing",
        _california_fetch(_california_frame(include_target=False)),
    )

    with pytest.raises(ValueError, match="MedHouseVal"):
        loader.load_california_housing()

    assert not (cache_dir / "california_housing.parquet").exists()


def test_load_ames_housing_drops_all_target_aliases(cache_dir, monkeypatch):
    frame = _ames_frame()
    target = _ames_target(frame)
    captured = {}
    data_homes = []

    def fake_fetch(**kwargs):
        captured.update(kwargs)
        data_home = Path(kwargs["data_home"])
        assert data_home.is_dir()
        data_homes.append(data_home)
        return SimpleNamespace(frame=frame, target=target)

    monkeypatch.setattr(loader, "fetch_openml", fake_fetch)

    X, y = loader.load_ames_housing()

    assert captured["name"] == "ames_housing"
    assert captured["n_retries"] == loader._FETCH_RETRIES
    assert data_homes and not data_homes[0].exists()
    assert y.name == "SalePrice"
    assert y.dtype == float
    assert "SalePrice" not in X.columns
    assert "Sale_Price" not in X.columns
    pd.testing.assert_frame_equal(X, frame.drop(columns=["Sale_Price"]))
    pd.testing.assert_series_equal(y, target.astype(float).rename("SalePrice"))

    cached = pd.read_parquet(cache_dir / "ames_housing.parquet")
    assert "SalePrice" in cached.columns
    assert "Sale_Price" not in cached.columns

    monkeypatch.setattr(loader, "fetch_openml", lambda **kwargs: pytest.fail("cache miss"))
    X_cached, y_cached = loader.load_ames_housing()
    pd.testing.assert_frame_equal(X_cached, X)
    pd.testing.assert_series_equal(y_cached, y)


def test_load_ames_housing_fetch_drops_both_target_aliases(cache_dir, monkeypatch):
    frame = _ames_frame()
    frame["SalePrice"] = frame["Sale_Price"]
    target = _ames_target(frame)
    monkeypatch.setattr(
        loader,
        "fetch_openml",
        lambda **kwargs: SimpleNamespace(frame=frame, target=target),
    )

    X, y = loader.load_ames_housing()

    assert y.name == "SalePrice"
    assert "SalePrice" not in X.columns
    assert "Sale_Price" not in X.columns
    cached = pd.read_parquet(cache_dir / "ames_housing.parquet")
    assert "SalePrice" in cached.columns
    assert "Sale_Price" not in cached.columns


def test_ephemeral_data_home_is_removed_after_fetch_failure(cache_dir, monkeypatch):
    seen = {}

    def failing_fetch(**kwargs):
        seen["data_home"] = Path(kwargs["data_home"])
        assert seen["data_home"].is_dir()
        raise RuntimeError("fetch failed")

    monkeypatch.setattr(loader, "fetch_california_housing", failing_fetch)

    with pytest.raises(RuntimeError, match="fetch failed"):
        loader.load_california_housing()

    assert not seen["data_home"].exists()


def test_load_ames_housing_renames_openml_cache_target(cache_dir):
    loader._save_to_cache(_ames_frame(), "ames_housing")

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


def test_load_ames_housing_recovers_from_invalid_cache(cache_dir, monkeypatch):
    loader._save_to_cache(pd.DataFrame({"MSSubClass": [60], "LotArea": [8000]}), "ames_housing")
    replacement = _ames_frame()
    monkeypatch.setattr(
        loader,
        "fetch_openml",
        lambda **kwargs: SimpleNamespace(frame=replacement, target=_ames_target(replacement)),
    )

    X, y = loader.load_ames_housing()

    assert y.name == "SalePrice"
    assert "Sale_Price" not in X.columns


def test_load_ames_housing_recovers_from_non_numeric_cache(cache_dir, monkeypatch):
    frame = _ames_frame()
    frame["SalePrice"] = ["high"] * len(frame)
    loader._save_to_cache(frame, "ames_housing")
    good = _ames_frame()
    monkeypatch.setattr(
        loader,
        "fetch_openml",
        lambda **kwargs: SimpleNamespace(frame=good, target=_ames_target(good)),
    )

    X, y = loader.load_ames_housing()

    assert y.name == "SalePrice"
    assert "SalePrice" not in X.columns


def test_load_ames_housing_rejects_fetch_without_target(cache_dir, monkeypatch):
    monkeypatch.setattr(
        loader,
        "fetch_openml",
        lambda **kwargs: SimpleNamespace(frame=_ames_frame(), target=None),
    )

    with pytest.raises(ValueError, match="no target"):
        loader.load_ames_housing()
    assert not (cache_dir / "ames_housing.parquet").exists()


def test_load_ames_housing_rejects_non_numeric_fetch_target(cache_dir, monkeypatch):
    frame = _ames_frame()
    monkeypatch.setattr(
        loader,
        "fetch_openml",
        lambda **kwargs: SimpleNamespace(frame=frame, target=pd.Series(["high"] * len(frame))),
    )

    with pytest.raises(ValueError):
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


def test_validate_frame_accepts_exact_limits(monkeypatch):
    monkeypatch.setattr(loader, "_MAX_ROWS", 2)
    monkeypatch.setattr(loader, "_MAX_COLUMNS", 2)
    frame = pd.DataFrame({"a": [1.0, 2.0], "b": [3.0, 4.0]})

    assert loader._validate_frame(frame, "exact") is frame


def test_split_target_rejects_non_numeric_target():
    frame = pd.DataFrame({"feature": [1.0], "target": ["high"]})
    with pytest.raises(ValueError, match="non-numeric"):
        loader._split_target(frame, "target", "demo")


@pytest.mark.integration
@pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION") != "1", reason="set RUN_INTEGRATION=1 to hit the network"
)
def test_load_california_housing_real_dataset(cache_dir):
    X, y = loader.load_california_housing()
    assert X.shape[0] == y.shape[0] > 0
    assert y.name == "MedHouseVal"
    assert "MedHouseVal" not in X.columns
