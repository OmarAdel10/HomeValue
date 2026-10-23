"""Configuration for HomeValue ML Backend."""

import logging
import os
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)

_REPO_MARKERS = ("pubspec.yaml", "ml_backend")


def _find_repo_root(start: Path) -> Path:
    """Locate the repository root by walking up to the project markers."""
    for candidate in (start, *start.parents):
        if (candidate / "pubspec.yaml").is_file() and (candidate / "ml_backend").is_dir():
            return candidate
    raise RuntimeError(f"Could not locate the HomeValue repository root above {start}")


def _default_project_root() -> Path:
    """Resolve the project root, tolerating installed (wheel) deployments."""
    override = os.getenv("HOMEVALUE_ROOT")
    if override:
        return Path(override).expanduser().resolve()
    try:
        return _find_repo_root(Path(__file__).resolve())
    except RuntimeError:
        logger.warning(
            "Could not locate the HomeValue repository root; falling back to the "
            "current directory. Set HOMEVALUE_ROOT to override it."
        )
        return Path.cwd()


_DEFAULT_ROOT = _default_project_root()


@dataclass
class Config:
    """Central configuration for ML pipeline."""

    # Paths
    project_root: Path = field(default_factory=lambda: _DEFAULT_ROOT)
    data_dir: Path = field(default_factory=lambda: _DEFAULT_ROOT / "data")
    models_dir: Path = field(default_factory=lambda: _DEFAULT_ROOT / "models")
    logs_dir: Path = field(default_factory=lambda: _DEFAULT_ROOT / "logs")

    # Data
    test_size: float = 0.2
    random_state: int = 42

    # Cross-validation
    cv_folds: int = 5
    cv_scoring: str = "neg_root_mean_squared_error"

    # Model hyperparameters
    ridge_alphas: list[float] = field(default_factory=lambda: [0.01, 0.1, 1.0, 10.0, 100.0])
    lasso_alphas: list[float] = field(default_factory=lambda: [0.001, 0.01, 0.1, 1.0])
    elasticnet_l1_ratios: list[float] = field(
        default_factory=lambda: [0.1, 0.5, 0.7, 0.9, 0.95, 0.99, 1.0]
    )
    elasticnet_alphas: list[float] = field(default_factory=lambda: [0.001, 0.01, 0.1, 1.0])

    # Random Forest
    rf_n_estimators: int = 200
    rf_max_features: str = "sqrt"
    rf_n_iter_search: int = 20

    # Gradient Boosting
    gb_n_estimators: int = 200
    gb_learning_rate: float = 0.1
    gb_n_iter_search: int = 20

    # API
    api_host: str = "127.0.0.1"
    api_port: int = 8000
    api_workers: int = 1

    # Model selection
    model_selection_metric: str = "rmse"  # rmse, mae, r2

    def __post_init__(self) -> None:
        """Reparent default paths when a custom project root is supplied."""
        for name in ("data", "models", "logs"):
            default_path = _DEFAULT_ROOT / name
            if getattr(self, f"{name}_dir") == default_path:
                setattr(self, f"{name}_dir", self.project_root / name)

    def ensure_dirs(self) -> None:
        """Create the configured working directories."""
        for directory in (self.data_dir, self.models_dir, self.logs_dir):
            directory.mkdir(parents=True, exist_ok=True, mode=0o750)


config = Config()
