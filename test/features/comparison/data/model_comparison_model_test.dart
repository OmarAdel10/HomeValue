import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_value/features/comparison/data/models/model_comparison_model.dart';

void main() {
  group('ModelComparisonModel', () {
    test('parses the backend {"models": [...]} envelope', () {
      final payload = json.encode({
        'models': [
          {
            'model_name': 'RandomForestRegressor',
            'rmse': 0.48,
            'mae': 0.38,
            'r2': 0.85,
            'cv_std': 0.03,
            'is_best': true,
          },
        ],
      });

      final comparison = ModelComparisonModel.fromJson(payload);

      expect(comparison.metrics, hasLength(1));
      expect(comparison.metrics.single.name, 'RandomForestRegressor');
      expect(comparison.metrics.single.rmse, 0.48);
      expect(comparison.metrics.single.isBest, isTrue);
    });

    test('accepts legacy list payloads and alternate metric keys', () {
      final payload = json.encode([
        {
          'model': 'RidgeCV',
          'rmse': 0.55,
          'mae': 0.44,
          'r2': 0.78,
          'cv_rmse_std': 0.04,
        },
      ]);

      final comparison = ModelComparisonModel.fromJson(payload);

      expect(comparison.metrics.single.name, 'RidgeCV');
      expect(comparison.metrics.single.cvStd, 0.04);
      expect(comparison.metrics.single.isBest, isFalse);
    });

    test('tolerates missing metric fields', () {
      final comparison = ModelComparisonModel.fromJson(json.encode({
        'models': [{}]
      }));

      final metric = comparison.metrics.single;
      expect(metric.name, 'Unknown');
      expect(metric.rmse, 0.0);
      expect(metric.mae, 0.0);
      expect(metric.r2, 0.0);
      expect(metric.cvStd, 0.0);
    });
  });
}
