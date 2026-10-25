import 'package:test/test.dart';
import 'package:home_value/features/prediction/data/models/prediction_result_model.dart';
import 'package:home_value/features/prediction/domain/entities/prediction_result.dart';

void main() {
  group('PredictionResultModel', () {
    const testEntity = PredictionResult(
      prediction: 4.52,
      model: 'RandomForestRegressor',
      modelVersion: '1.0.0',
    );

    const testJson = {
      'prediction': 4.52,
      'model': 'RandomForestRegressor',
      'model_version': '1.0.0',
    };

    group('fromEntity', () {
      test('creates model from entity correctly', () {
        final model = PredictionResultModel.fromEntity(const PredictionResult(
          prediction: 4.52,
          model: 'RandomForestRegressor',
          modelVersion: '1.0.0',
        ));

        expect(model.prediction, 4.52);
        expect(model.model, 'RandomForestRegressor');
        expect(model.modelVersion, '1.0.0');
      });
    });

    group('toEntity', () {
      test('converts model back to entity correctly', () {
        const model = PredictionResultModel(
          prediction: 4.52,
          model: 'RandomForestRegressor',
          modelVersion: '1.0.0',
        );

        final entity = model.toEntity();

        expect(entity.prediction, 4.52);
        expect(entity.model, 'RandomForestRegressor');
        expect(entity.modelVersion, '1.0.0');
      });
    });

    group('toJson', () {
      test('serializes to JSON correctly', () {
        const model = PredictionResultModel(
          prediction: 4.52,
          model: 'RandomForestRegressor',
          modelVersion: '1.0.0',
        );

        final json = model.toJson();

        expect(json['prediction'], 4.52);
        expect(json['model'], 'RandomForestRegressor');
        expect(json['model_version'], '1.0.0');
      });
    });

    group('fromJson', () {
      test('deserializes from JSON correctly', () {
        final json = {
          'prediction': 4.52,
          'model': 'RandomForestRegressor',
          'model_version': '1.0.0',
        };

        final model = PredictionResultModel.fromJson(json);

        expect(model.prediction, 4.52);
        expect(model.model, 'RandomForestRegressor');
        expect(model.modelVersion, '1.0.0');
      });

      test('handles integer values in JSON', () {
        final json = {
          'prediction': 5,
          'model': 'LinearRegression',
          'model_version': '2.0',
        };

        final model = PredictionResultModel.fromJson(json);

        expect(model.prediction, 5.0);
        expect(model.model, 'LinearRegression');
        expect(model.modelVersion, '2.0');
      });
    });

    group('equatable', () {
      test('equals returns true for equal models', () {
        const model1 = PredictionResultModel(
          prediction: 4.52,
          model: 'RandomForestRegressor',
          modelVersion: '1.0.0',
        );

        const model2 = PredictionResultModel(
          prediction: 4.52,
          model: 'RandomForestRegressor',
          modelVersion: '1.0.0',
        );

        expect(model1, equals(model2));
      });

      test('equals returns false for different models', () {
        const model1 = PredictionResultModel(
          prediction: 4.52,
          model: 'RandomForestRegressor',
          modelVersion: '1.0.0',
        );

        const model2 = PredictionResultModel(
          prediction: 3.2,
          model: 'LinearRegression',
          modelVersion: '2.0.0',
        );

        expect(model1, isNot(equals(model2)));
      });
    });
  });
}
