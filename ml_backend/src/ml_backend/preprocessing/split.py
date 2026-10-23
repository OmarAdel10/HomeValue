"""Train/test splitting utilities."""

import pandas as pd
from sklearn.model_selection import train_test_split  # type: ignore[import-untyped]

from ml_backend.config import Config


def split_train_test(
    X: pd.DataFrame,
    y: pd.Series,
    config: Config,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.Series, pd.Series]:
    """Split features and target into reproducible train/test partitions."""
    if len(X) != len(y):
        raise ValueError("Features and target must have the same number of rows")
    if not X.index.equals(y.index):
        raise ValueError("Features and target must share the same index")
    if len(X) == 0:
        raise ValueError("Cannot split an empty dataset")

    test_size = config.test_size
    if not 0 < test_size < 1:
        raise ValueError(f"test_size must be strictly between 0 and 1, got {test_size}")

    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=test_size,
        random_state=config.random_state,
        shuffle=True,
    )
    return X_train, X_test, y_train, y_test
