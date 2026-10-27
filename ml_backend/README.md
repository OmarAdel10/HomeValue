# HomeValue ML Backend

scikit-learn training pipeline and FastAPI service for the HomeValue house price
prediction project.

> Phase 7 status: data loading, dataset integrity caching, exploratory analysis, the
> preprocessing pipeline, baseline models, regularized models, evaluation metrics,
> ensemble models, hyperparameter tuning, model selection, joblib serialization,
> training API endpoint, and prediction API endpoints (`/predict`, `/predict/batch`,
> `/model/info`, `/model/comparison`) are implemented. The Flutter UI is a roadmap item.

## Setup

```bash
pip install -e ".[dev]"
```

## Commands

```bash
make format   # black + ruff format
make lint     # ruff + mypy
make test     # pytest with branch coverage
make train    # run full training pipeline, saves best model
make serve    # start FastAPI server on localhost:8000
```

Pytest configuration lives in the repository-root `pytest.ini`, so `pytest` can be
invoked from the repository root or from `ml_backend/`. Run coverage from
`ml_backend/` (`make test`) so the coverage settings and 95% gate in
`pyproject.toml` apply.

`make train` and `make serve` intentionally exit with a roadmap message until the
training pipeline and API land.
