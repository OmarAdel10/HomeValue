/// Application-wide constants for HomeValue Flutter app.
library;

class AppConstants {
  // API Configuration
  static const String apiBaseUrl = 'http://localhost:8000';
  static const Duration apiTimeout = Duration(seconds: 30);

  // API Endpoints
  static const String predictEndpoint = '/predict';
  static const String predictBatchEndpoint = '/predict/batch';
  static const String healthEndpoint = '/health';
  static const String modelInfoEndpoint = '/model/info';
  static const String modelComparisonEndpoint = '/model/comparison';
  static const String trainEndpoint = '/train';

  // Feature field definitions for California Housing dataset
  static const List<String> featureNames = [
    'MedInc',
    'HouseAge',
    'AveRooms',
    'AveBedrms',
    'Population',
    'AveOccup',
    'Latitude',
    'Longitude',
  ];

  static const String oceanProximityField = 'ocean_proximity';

  static const List<String> oceanProximityValues = [
    '<1H OCEAN',
    'INLAND',
    'NEAR OCEAN',
    'NEAR BAY',
    'ISLAND',
  ];

  // Feature field labels for UI
  static const Map<String, String> featureLabels = {
    'MedInc': 'Median Income (in \$100k)',
    'HouseAge': 'House Age (years)',
    'AveRooms': 'Average Rooms per Household',
    'AveBedrms': 'Average Bedrooms per Household',
    'Population': 'Block Group Population',
    'AveOccup': 'Average Household Occupancy',
    'Latitude': 'Latitude',
    'Longitude': 'Longitude',
    'ocean_proximity': 'Ocean Proximity',
  };

  // Feature field hints for UI
  static const Map<String, String> featureHints = {
    'MedInc': 'e.g., 8.3252',
    'HouseAge': 'e.g., 41',
    'AveRooms': 'e.g., 6.98',
    'AveBedrms': 'e.g., 1.02',
    'Population': 'e.g., 322',
    'AveOccup': 'e.g., 2.55',
    'Latitude': 'e.g., 37.88',
    'Longitude': 'e.g., -122.23',
  };

  // Model names for selection
  static const List<String> modelNames = [
    'LinearRegression',
    'DecisionTreeRegressor',
    'RidgeCV',
    'LassoCV',
    'ElasticNetCV',
    'RandomForestRegressor',
    'ExtraTreesRegressor',
    'VotingRegressor',
    'StackingRegressor',
    'RandomForestRegressor_Tuned',
    'GradientBoostingRegressor_Tuned',
  ];

  // App info
  static const String appName = 'HomeValue';
  static const String appVersion = '1.0.0';
  static const String appDescription =
      'House price prediction using machine learning';
}
