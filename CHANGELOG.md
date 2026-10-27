# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-10-25

### Added
- **ML Backend (Python/FastAPI):**
  - California Housing data loader with caching and checksum validation
  - Preprocessing pipeline: imputation, scaling, polynomial features, feature selection
  - Baseline models: LinearRegression, DecisionTreeRegressor
  - Regularized models: RidgeCV, LassoCV, ElasticNetCV with cross-validation
  - Ensemble models: RandomForest, ExtraTrees, Voting, Stacking regressors
  - Hyperparameter tuning: RandomizedSearchCV for RandomForest and GradientBoosting
  - Model selection: RMSE-based best model selection with joblib serialization
  - FastAPI server with endpoints: `/predict`, `/predict/batch`, `/health`, `/model/info`, `/model/comparison`, `/train`
  - Comprehensive test suite (250 tests, 96.7% coverage)

- **Flutter Desktop App (Linux):**
  - MVVM + BLoC architecture with GetIt dependency injection
  - Prediction feature: form with 8 numeric fields + ocean proximity dropdown, validation, result dialog
  - Model comparison feature: bar charts (fl_chart), metric selector, data table, best model highlight
  - Settings feature: server URL, theme mode (system/light/dark), auto-retrain toggle with SharedPreferences persistence
  - Dynamic theme switching via SettingsBloc at app level
  - GoRouter navigation with app bar actions for Settings and Model Comparison
  - Material 3 theming with light/dark mode support

- **Testing:**
  - 250 Python backend tests (unit, integration, API)
  - 52 Flutter tests (BLoC, widget, integration)
  - End-to-end integration test script

- **CI/CD:**
  - GitHub Actions workflow for Python (lint, test, coverage) and Flutter (analyze, test, build-linux)

### Changed
- N/A (initial release)

### Fixed
- N/A (initial release)

### Removed
- N/A (initial release)

## [0.1.0] - 2025-10-20 (Pre-release)

### Added
- Project structure and initial ML pipeline
- Basic Flutter app scaffold
- Data loading and preprocessing modules
- Baseline model implementations

---

## Release Notes Template

### Version X.Y.Z - YYYY-MM-DD

#### Added
- Feature description

#### Changed
- Modification description

#### Fixed
- Bug fix description

#### Removed
- Removal description

---

## Links

- [GitHub Repository](https://github.com/OmarAdel10/HomeValue)
- [Issues](https://github.com/OmarAdel10/HomeValue/issues)
- [Pull Requests](https://github.com/OmarAdel10/HomeValue/pulls)