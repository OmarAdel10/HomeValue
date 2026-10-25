"""Shared state for model loading across API modules."""

from typing import Any

from ml_backend.config import Config
from ml_backend.models.selection import load_model

_model = None


def load_saved_model() -> None:
    """Load the saved model from disk."""
    global _model
    config = Config()
    model_file = config.models_dir / "best_model.joblib"
    if model_file.exists():
        _model = load_model(model_file)
    else:
        _model = None


def get_model() -> Any:
    """Get the loaded model, loading it if necessary."""
    global _model
    if _model is None:
        load_saved_model()
    return _model
