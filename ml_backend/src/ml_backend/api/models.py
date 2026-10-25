"""FastAPI router for model info and comparison endpoints."""

from fastapi import APIRouter

from ml_backend.api.state import get_model

router = APIRouter(prefix="/model", tags=["model"])


@router.get("/info")
async def model_info() -> dict:
    """Get information about the currently loaded model.

    Returns:
        Dict with model name, loaded status, and pipeline steps.
    """
    model = get_model()
    if model is None:
        return {"model": None, "loaded": False}

    return {
        "model": "best_model.joblib",
        "loaded": True,
        "steps": list(model.named_steps.keys()),
    }


@router.get("/comparison")
async def model_comparison() -> dict:
    """Get comparison metrics for all trained models.

    Returns:
        Dict with list of models and their metrics (RMSE, MAE, R², CV std).
    """
    # TODO: Load comparison data from saved metadata when available
    # For now, return empty list - will be populated when model metadata is saved
    return {"models": []}
