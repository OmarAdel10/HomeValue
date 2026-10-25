# HomeValue ML Backend

scikit-learn training pipeline and FastAPI service for the HomeValue house price
prediction project.

> Phase 6 status: data loading, dataset integrity caching, exploratory analysis, the
> preprocessing pipeline, baseline models, regularized models, evaluation metrics,
> ensemble models, hyperparameter tuning, model selection, joblib serialization, and
> training API endpoint are implemented. The FastAPI prediction service and the Flutter
> UI arrive in the next phases.

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

`make train` and `make serve` intentionally exit with a roadmap message until the
training pipeline and API land.
