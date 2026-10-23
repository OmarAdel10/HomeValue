"""Data loading utilities for HomeValue ML Backend."""

import hashlib
import logging
import os
import shutil
import tempfile
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

import pandas as pd
from pyarrow import ArrowException  # type: ignore[import-untyped]
from sklearn.datasets import fetch_california_housing, fetch_openml  # type: ignore[import-untyped]

from ml_backend.config import config

logger = logging.getLogger(__name__)

CALIFORNIA_TARGET = "MedHouseVal"
AMES_TARGET = "SalePrice"
# The current OpenML record spells the target with an underscore, both as a frame
# column and as the separate target series.
_OPENML_AMES_TARGET = "Sale_Price"

_MAX_ROWS = 1_000_000
_MAX_COLUMNS = 500
_CHECKSUM_SUFFIX = ".sha256"
_FETCH_RETRIES = 3
_FETCH_RETRY_DELAY = 1.0


def _get_cache_path(name: str) -> Path:
    """Get cache file path for a dataset."""
    return config.data_dir / f"{name}.parquet"


def _get_checksum_path(name: str) -> Path:
    """Get the path of the SHA-256 sidecar for a cached dataset."""
    return config.data_dir / f"{name}.parquet{_CHECKSUM_SUFFIX}"


def _sha256(path: Path) -> str:
    """Compute the SHA-256 digest of a file."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_write(path: Path, writer: Callable[[Path], None]) -> None:
    """Write a file through a temporary sibling and atomically replace it."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
    descriptor, temp_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    os.close(descriptor)
    temp_path = Path(temp_name)
    try:
        writer(temp_path)
        temp_path.chmod(0o640)
        os.replace(temp_path, path)
    finally:
        temp_path.unlink(missing_ok=True)


def _save_to_cache(df: pd.DataFrame, name: str) -> None:
    """Save a DataFrame to the parquet cache with an integrity sidecar."""
    cache_path = _get_cache_path(name)
    _atomic_write(cache_path, df.to_parquet)

    def write_checksum(path: Path) -> None:
        path.write_text(_sha256(cache_path), encoding="utf-8")

    _atomic_write(_get_checksum_path(name), write_checksum)
    logger.info("Cached dataset %s (%d rows, %d columns)", name, *df.shape)


def _discard_cache(name: str) -> None:
    """Best-effort removal of a cache entry and its checksum sidecar."""
    for path in (_get_cache_path(name), _get_checksum_path(name)):
        try:
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path, ignore_errors=True)
            else:
                path.unlink(missing_ok=True)
        except OSError:
            logger.warning("Could not remove cache file %s", path)


@contextmanager
def _ephemeral_data_home() -> Iterator[Path]:
    """Yield a throwaway scikit-learn data directory that is always removed.

    Some fetchers persist joblib payloads inside ``data_home`` and deserialize
    them on the next call. Keeping that directory ephemeral means no executable
    pickle survives between runs.
    """
    data_home = Path(tempfile.mkdtemp(prefix="homevalue-sklearn-"))
    try:
        yield data_home
    finally:
        shutil.rmtree(data_home, ignore_errors=True)


def _load_from_cache(name: str) -> pd.DataFrame | None:
    """Load a verified cached DataFrame, or None when it is missing or invalid."""
    cache_path = _get_cache_path(name)
    if not cache_path.exists():
        logger.info("Cache miss for dataset %s", name)
        return None

    checksum_path = _get_checksum_path(name)
    if not checksum_path.exists():
        logger.warning("Ignoring unverified cache %s (missing checksum sidecar)", name)
        _discard_cache(name)
        return None

    try:
        expected = checksum_path.read_text(encoding="utf-8").strip()
        actual = _sha256(cache_path)
    except OSError:
        logger.exception("Unreadable checksum for cached dataset %s; discarding it", name)
        _discard_cache(name)
        return None

    if actual != expected:
        logger.warning("Checksum mismatch for cached dataset %s; discarding it", name)
        _discard_cache(name)
        return None

    try:
        frame = _validate_frame(pd.read_parquet(cache_path), name)
    except (OSError, ValueError, ArrowException):
        logger.exception("Unreadable cache for dataset %s; discarding it", name)
        _discard_cache(name)
        return None

    logger.info("Cache hit for dataset %s", name)
    return frame


def _validate_frame(df: pd.DataFrame, name: str) -> pd.DataFrame:
    """Reject empty or unreasonably large datasets before caching them."""
    if df.empty:
        raise ValueError(f"Dataset {name!r} is empty")
    if len(df) > _MAX_ROWS or len(df.columns) > _MAX_COLUMNS:
        raise ValueError(
            f"Dataset {name!r} exceeds the safety limits "
            f"({len(df)} rows, {len(df.columns)} columns)"
        )
    return df


def _split_target(df: pd.DataFrame, target: str, name: str) -> tuple[pd.DataFrame, pd.Series]:
    """Split a frame into features and a named, numeric target series."""
    if target not in df.columns:
        raise ValueError(f"Dataset {name!r} is missing the target column {target!r}")
    X = df.drop(columns=[target])
    y = df[target]
    if not pd.api.types.is_numeric_dtype(y):
        raise ValueError(f"Dataset {name!r} has a non-numeric target column {target!r}")
    return X, y.rename(target)


def load_california_housing() -> tuple[pd.DataFrame, pd.Series]:
    """
    Load the California Housing dataset.

    The target is capped at 5.00001 by the source dataset.

    Returns:
        Tuple of (features DataFrame, target Series)
    """
    cached = _load_from_cache("california_housing")
    if cached is not None:
        try:
            return _split_target(cached, CALIFORNIA_TARGET, "california_housing")
        except ValueError:
            logger.exception("Invalid California cache; discarding it")
            _discard_cache("california_housing")

    logger.info("Fetching California Housing from scikit-learn")
    config.ensure_dirs()
    with _ephemeral_data_home() as data_home:
        data = fetch_california_housing(
            as_frame=True,
            data_home=str(data_home),
            n_retries=_FETCH_RETRIES,
            delay=_FETCH_RETRY_DELAY,
        )
    df = _validate_frame(data.frame, "california_housing")
    X, y = _split_target(df, CALIFORNIA_TARGET, "california_housing")
    _save_to_cache(df, "california_housing")
    return X, y


def load_ames_housing() -> tuple[pd.DataFrame, pd.Series]:
    """
    Load the Ames Housing dataset from OpenML.

    Returns:
        Tuple of (features DataFrame, target Series)
    """
    cached = _load_from_cache("ames_housing")
    if cached is not None:
        if AMES_TARGET not in cached.columns and _OPENML_AMES_TARGET in cached.columns:
            cached = cached.rename(columns={_OPENML_AMES_TARGET: AMES_TARGET})
        cached = cached.drop(columns=[_OPENML_AMES_TARGET], errors="ignore")
        try:
            return _split_target(cached, AMES_TARGET, "ames_housing")
        except ValueError:
            logger.exception("Invalid Ames cache; discarding it")
            _discard_cache("ames_housing")

    logger.info("Fetching Ames Housing from OpenML")
    config.ensure_dirs()
    with _ephemeral_data_home() as data_home:
        data = fetch_openml(
            name="ames_housing",
            version=1,
            as_frame=True,
            data_home=str(data_home),
            n_retries=_FETCH_RETRIES,
            delay=_FETCH_RETRY_DELAY,
        )
    if data.target is None:
        raise ValueError("Ames Housing fetch returned no target column")

    df = _validate_frame(data.frame, "ames_housing")
    target = data.target.astype(float).rename(AMES_TARGET)
    # OpenML's frame embeds the target under the legacy name; drop every target
    # alias so it can never leak into the feature matrix.
    features = df.drop(
        columns=[AMES_TARGET, _OPENML_AMES_TARGET],
        errors="ignore",
    )

    df_with_target = features.copy()
    df_with_target[AMES_TARGET] = target.reindex(features.index).to_numpy()
    _save_to_cache(df_with_target, "ames_housing")

    return features, target
