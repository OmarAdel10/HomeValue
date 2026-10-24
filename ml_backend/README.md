# HomeValue ML Backend

scikit-learn training pipeline and FastAPI service for the HomeValue house price
prediction project.

> Phase 4 status: data loading, dataset integrity caching, exploratory analysis, the
> preprocessing pipeline, baseline models, regularized models, evaluation metrics, and
> ensemble models (RandomForest, ExtraTrees, Voting, Stacking) are implemented.
> Hyperparameter tuning and the HTTP API arrive in later phases.

## Setup

```bash
pip install -e ".[dev]"
```

## Commands

```bash
make format   # black + ruff format
make lint     # ruff + mypy
make test     # pytest with branch coverage
```

`make train` and `make serve` intentionally exit with a roadmap message until the
training pipeline and API land.
