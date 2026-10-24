"""FastAPI application for HomeValue ML Backend."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ml_backend.api import train_router
from ml_backend.config import Config
from ml_backend.models.selection import load_model

_model = None


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Load model on startup."""
    global _model
    config = Config()
    model_file = config.models_dir / "best_model.joblib"
    if model_file.exists():
        _model = load_model(model_file)
    else:
        _model = None
    yield


app = FastAPI(
    title="HomeValue ML API",
    description="House price prediction API",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(train_router)


@app.get("/health")
async def health_check() -> dict:
    return {"status": "ok", "model_loaded": _model is not None}


@app.get("/model_info")
async def model_info() -> dict:
    if _model is None:
        return {"model": None, "loaded": False}
    return {
        "model": "best_model.joblib",
        "loaded": True,
        "steps": list(_model.named_steps.keys()),
    }
