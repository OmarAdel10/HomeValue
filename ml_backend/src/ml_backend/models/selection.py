"""Model selection and serialization for HomeValue."""

from pathlib import Path

import joblib  # type: ignore[import-untyped]
import numpy as np
from sklearn.pipeline import Pipeline  # type: ignore[import-untyped]

from ml_backend.models.evaluation import regression_metrics


def select_best_model(
    models: dict[str, Pipeline],
    X_test: np.ndarray,
    y_test: np.ndarray,
) -> tuple[str, Pipeline]:
    """Select the best model based on lowest RMSE on test set.

    Args:
        models: Dict mapping model names to fitted Pipelines.
        X_test: Test features.
        y_test: Test targets.

    Returns:
        Tuple of (best_model_name, best_fitted_pipeline).
    """
    if not models:
        raise ValueError("No models provided for selection")

    if X_test.shape[0] != y_test.shape[0]:
        raise ValueError("X_test and y_test must have the same number of samples")

    best_name: str | None = None
    best_rmse = float("inf")
    best_pipeline: Pipeline | None = None

    for name, pipeline in models.items():
        metrics = regression_metrics(y_test, pipeline.predict(X_test))
        rmse = metrics["rmse"]
        if rmse < best_rmse:
            best_rmse = rmse
            best_name = name
            best_pipeline = pipeline

    assert best_name is not None and best_pipeline is not None
    return best_name, best_pipeline


def save_model(pipeline: Pipeline, path: Path) -> None:
    """Save a fitted pipeline to disk using joblib.

    Args:
        pipeline: Fitted sklearn Pipeline to save.
        path: Destination path (will create parent directories).
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(pipeline, path)


def load_model(path: Path) -> Pipeline:
    """Load a fitted pipeline from disk.

    Args:
        path: Path to the saved model file.

    Returns:
        Fitted sklearn Pipeline.

    Raises:
        FileNotFoundError: If the model file does not exist.
    """
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Model file not found: {path}")
    return joblib.load(path)
