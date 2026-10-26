"""FastAPI router for model info and comparison endpoints."""

import json

from fastapi import APIRouter

from ml_backend.api.state import get_model
from ml_backend.config import Config

router = APIRouter(prefix="/model", tags=["model"])


def _load_comparison() -> list[dict]:
    """Load model comparison data from disk."""
    config = Config()
    comparison_path = config.models_dir / "model_comparison.json"
    if comparison_path.exists():
        with open(comparison_path) as f:
            return json.load(f)
    return []


def _save_comparison(models: list[dict]) -> None:
    """Save model comparison data to disk."""
    config = Config()
    config.ensure_dirs()
    comparison_path = config.models_dir / "model_comparison.json"
    with open(comparison_path, "w") as f:
        json.dump(models, f, indent=2)


@router.get("/info")
async def model_info() -> dict:
    """Get information about the currently loaded model.

    Returns:
        Dict with model name, loaded status, and pipeline steps.
    """
    model = get_model()
    if model is None:
        return {"model": None, "loaded": False}

    steps = list(model.named_steps.keys()) if hasattr(model, "named_steps") else []

    return {
        "model": "best_model.joblib",
        "loaded": True,
        "steps": steps,
    }


@router.get("/comparison")
async def model_comparison() -> dict:
    """Get comparison metrics for all trained models.

    Returns:
        Dict with list of models and their metrics (RMSE, MAE, R², CV std).
    """
    models = _load_comparison()
    return {"models": models}
