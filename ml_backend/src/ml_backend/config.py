"""Configuration for HomeValue ML Backend."""

from dataclasses import dataclass, field
from pathlib import Path


def _find_repo_root(start: Path) -> Path:
    """Locate the repository root by walking up to the Flutter/pubspec marker."""
    for candidate in (start, *start.parents):
        if (candidate / "pubspec.yaml").is_file() and (candidate / "ml_backend").is_dir():
            return candidate
    raise RuntimeError(f"Could not locate the HomeValue repository root above {start}")


_REPO_ROOT = _find_repo_root(Path(__file__).resolve())


@dataclass
class Config:
    """Central configuration for ML pipeline."""

    # Paths
    project_root: Path = field(default_factory=lambda: _REPO_ROOT)
    data_dir: Path = field(default_factory=lambda: _REPO_ROOT / "data")
    models_dir: Path = field(default_factory=lambda: _REPO_ROOT / "models")
    logs_dir: Path = field(default_factory=lambda: _REPO_ROOT / "logs")

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
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_workers: int = 1

    # Model selection
    model_selection_metric: str = "rmse"  # rmse, mae, r2

    def __post_init__(self) -> None:
        """Create directories if they don't exist."""
        for directory in (self.data_dir, self.models_dir, self.logs_dir):
            directory.mkdir(parents=True, exist_ok=True, mode=0o750)


config = Config()
