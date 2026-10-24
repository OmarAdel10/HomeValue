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

    # Lasso/ElasticNet convergence
    lasso_max_iter: int = 10000
    elasticnet_max_iter: int = 10000

    # Decision Tree
    dt_max_depth: int = 10
    dt_min_samples_split: int = 5
    dt_min_samples_leaf: int = 2

    # Cross-validation resources
    cv_n_jobs: int = -1

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

        # Validate hyperparameter bounds
        if not 0 < self.test_size < 1:
            raise ValueError("test_size must be strictly between 0 and 1")
        if self.cv_folds < 2 or self.cv_folds > 10:
            raise ValueError("cv_folds must be between 2 and 10")
        if len(self.ridge_alphas) == 0 or len(self.ridge_alphas) > 100:
            raise ValueError("ridge_alphas must have 1-100 values")
        if any(a <= 0 for a in self.ridge_alphas):
            raise ValueError("ridge_alphas must be positive")
        if len(self.lasso_alphas) == 0 or len(self.lasso_alphas) > 100:
            raise ValueError("lasso_alphas must have 1-100 values")
        if any(a <= 0 for a in self.lasso_alphas):
            raise ValueError("lasso_alphas must be positive")
        if len(self.elasticnet_alphas) == 0 or len(self.elasticnet_alphas) > 100:
            raise ValueError("elasticnet_alphas must have 1-100 values")
        if any(a <= 0 for a in self.elasticnet_alphas):
            raise ValueError("elasticnet_alphas must be positive")
        if len(self.elasticnet_l1_ratios) == 0 or len(self.elasticnet_l1_ratios) > 100:
            raise ValueError("elasticnet_l1_ratios must have 1-100 values")
        if any(not 0 <= r <= 1 for r in self.elasticnet_l1_ratios):
            raise ValueError("elasticnet_l1_ratios must be in [0, 1]")
        if self.lasso_max_iter < 1:
            raise ValueError("lasso_max_iter must be positive")
        if self.elasticnet_max_iter < 1:
            raise ValueError("elasticnet_max_iter must be positive")
        if self.dt_max_depth < 1:
            raise ValueError("dt_max_depth must be positive")
        if self.dt_min_samples_split < 2:
            raise ValueError("dt_min_samples_split must be at least 2")
        if self.dt_min_samples_leaf < 1:
            raise ValueError("dt_min_samples_leaf must be positive")

        # Ensemble hyperparameters
        if self.rf_n_estimators < 1 or self.rf_n_estimators > 1000:
            raise ValueError("rf_n_estimators must be between 1 and 1000")
        if self.rf_max_features not in ("sqrt", "log2", None) and not (
            isinstance(self.rf_max_features, float) and 0 < self.rf_max_features <= 1
        ):
            raise ValueError("rf_max_features must be 'sqrt', 'log2', None, or a float in (0, 1]")
        if self.cv_n_jobs < -1 or self.cv_n_jobs == 0:
            raise ValueError("cv_n_jobs must be -1 (all cores) or a positive integer")

    def ensure_dirs(self) -> None:
        """Create the configured working directories."""
        for directory in (self.data_dir, self.models_dir, self.logs_dir):
            directory.mkdir(parents=True, exist_ok=True, mode=0o750)


config = Config()
