"""FastAPI application for HomeValue ML Backend."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from ml_backend.api import model_router, predict_router, train_router
from ml_backend.api.state import get_model, load_saved_model


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Load model on startup."""
    load_saved_model()
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
app.include_router(predict_router)
app.include_router(model_router)


@app.get("/health")
async def health_check() -> dict:
    return {"status": "ok", "model_loaded": get_model() is not None}
