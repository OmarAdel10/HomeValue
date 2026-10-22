"""Configuration for HomeValue ML Backend."""

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Config:
    """Central configuration for ML pipeline."""

    # Paths
    project_root: Path = field(default_factory=lambda: Path(__file__).parents[3])
    data_dir: Path = field(default_factory=lambda: Path(__file__).parents[3] / "data")
    models_dir: Path = field(default_factory=lambda: Path(__file__).parents[3] / "models")
    logs_dir: Path = field(default_factory=lambda: Path(__file__).parents[3] / "logs")

    # Data
    test_size: float = 0.2
    random_state: int = 42
    stratify_col: str = "income_cat"  # for California housing

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

    def __post_init__(self):
        """Create directories if they don't exist."""
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.models_dir.mkdir(parents=True, exist_ok=True)
        self.logs_dir.mkdir(parents=True, exist_ok=True)


config = Config()
