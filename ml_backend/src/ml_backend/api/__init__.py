"""FastAPI routers for HomeValue API."""

from ml_backend.api.models import router as model_router
from ml_backend.api.predict import router as predict_router
from ml_backend.api.train import router as train_router

__all__ = ["train_router", "predict_router", "model_router"]
