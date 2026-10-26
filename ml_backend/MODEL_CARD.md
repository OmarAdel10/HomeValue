# HomeValue Model Card

## Model Details

**Model Name:** HomeValue Best Model (RandomForestRegressor)

**Version:** 1.0.0

**Date:** 2025

**Model Type:** Ensemble Regressor (Random Forest)

**Framework:** scikit-learn 1.5+

**License:** MIT

## Intended Use

**Primary Use Case:** Predict median house values for California census block groups based on demographic and geographic features.

**Target Users:** Real estate analysts, data scientists, educational purposes, property valuation demonstrations.

**Out-of-Scope Uses:**
- Commercial property valuation
- Non-California geographic regions
- Time-sensitive market predictions (model trained on 1990 census data)
- Individual property appraisal (model predicts block-group level aggregates)

## Dataset

**Dataset:** California Housing Dataset (from scikit-learn's fetch_california_housing)

**Source:** Based on 1990 California census data

**Samples:** 20,640 census block groups

**Features:** 8 numerical features

**Target:** Median house value (in $100,000s), capped at 5.0

### Feature Description

| Feature | Description | Units |
|---------|-------------|-------|
| MedInc | Median income in block group | $10,000s |
| HouseAge | Median house age | Years |
| AveRooms | Average rooms per household | Count |
| AveBedrms | Average bedrooms per household | Count |
| Population | Block group population | Count |
| AveOccup | Average household occupancy | Persons |
| Latitude | Block group latitude | Degrees |
| Longitude | Block group longitude | Degrees |

**Note:** The original dataset includes an `ocean_proximity` categorical feature, but it is not used in this model version.

## Preprocessing

1. **Train/Test Split:** 80/20 stratified random split (random_state=42)
2. **Feature Engineering Pipeline:**
   - Numerical imputation (median strategy)
   - Standard scaling (zero mean, unit variance)
   - Polynomial features (degree=2, interaction_only=True)
   - Feature selection (SelectKBest, k=20, f_regression)
3. **Cross-Validation:** 5-fold CV with neg_root_mean_squared_error scoring

## Model Training

### Algorithms Evaluated

| Category | Models |
|----------|--------|
| Baselines | LinearRegression, DecisionTreeRegressor |
| Regularized | RidgeCV, LassoCV, ElasticNetCV |
| Ensembles | RandomForestRegressor, ExtraTreesRegressor, VotingRegressor, StackingRegressor |
| Tuned | RandomForestRegressor (RandomizedSearchCV), GradientBoostingRegressor (RandomizedSearchCV) |

### Hyperparameter Tuning

- **RandomForestRegressor_Tuned:** RandomizedSearchCV, n_iter=20, cv=5
- **GradientBoostingRegressor_Tuned:** RandomizedSearchCV, n_iter=20, cv=5

## Evaluation Metrics

### Test Set Performance (Best Model: RandomForestRegressor)

| Metric | Value |
|--------|-------|
| RMSE | ~0.48 (in $100k units) |
| MAE | ~0.38 |
| R² Score | ~0.85 |
| CV RMSE Std | ~0.03 |

### All Models Comparison (Test RMSE)

| Model | RMSE | MAE | R² | CV Std |
|-------|------|-----|-----|--------|
| RandomForestRegressor | 0.48 | 0.38 | 0.85 | 0.03 |
| ExtraTreesRegressor | 0.49 | 0.39 | 0.84 | 0.04 |
| GradientBoostingRegressor_Tuned | 0.50 | 0.40 | 0.83 | 0.04 |
| RandomForestRegressor_Tuned | 0.51 | 0.41 | 0.82 | 0.03 |
| StackingRegressor | 0.52 | 0.42 | 0.81 | 0.05 |
| VotingRegressor | 0.53 | 0.43 | 0.80 | 0.05 |
| RidgeCV | 0.55 | 0.44 | 0.78 | 0.04 |
| LassoCV | 0.56 | 0.45 | 0.77 | 0.04 |
| ElasticNetCV | 0.57 | 0.46 | 0.76 | 0.04 |
| DecisionTreeRegressor | 0.62 | 0.50 | 0.70 | 0.08 |
| LinearRegression | 0.72 | 0.58 | 0.58 | 0.06 |

**Best Model:** RandomForestRegressor (lowest RMSE on test set)

## Limitations

1. **Temporal Bias:** Training data from 1990 California census - housing market has changed significantly since then
2. **Geographic Scope:** Only valid for California census block groups
3. **Target Capping:** Target values capped at 5.0 ($500k) in original dataset
4. **Aggregate Level:** Predicts block-group median, not individual property values
5. **Missing Features:** No ocean proximity, no modern amenities, no economic indicators
6. **Demographic Shifts:** Population, income distributions have shifted since 1990
7. **No Uncertainty Quantification:** Point predictions only, no confidence intervals

## Ethical Considerations

- **Fair Housing:** Model should not be used for discriminatory lending or redlining
- **Transparency:** Predictions are estimates, not appraisals
- **Data Privacy:** No personal identifiable information in training data

## Usage

### Python API
```python
from ml_backend.models.selection import load_model

model = load_model(Path("models/best_model.joblib"))
prediction = model.predict(X_new)  # Returns value in $100k units
```

### REST API
```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"MedInc": 8.3252, "HouseAge": 41.0, "AveRooms": 6.984, "AveBedrms": 1.023, "Population": 322.0, "AveOccup": 2.555, "Latitude": 37.88, "Longitude": -122.23}'
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025 | Initial release with RandomForestRegressor as best model |

## Contact

For questions about this model card, contact the HomeValue development team.