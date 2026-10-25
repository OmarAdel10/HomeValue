import 'package:test/test.dart';
import 'package:home_value/features/prediction/data/models/model_info_model.dart';
import 'package:home_value/features/prediction/domain/entities/model_info.dart';

void main() {
  group('ModelInfoModel', () {
    const testEntity = ModelInfo(
      model: 'best_model.joblib',
      loaded: true,
      steps: ['preprocessor', 'model'],
    );

    const testJson = {
      'model': 'best_model.joblib',
      'loaded': true,
      'steps': ['preprocessor', 'model'],
    };

    group('fromEntity', () {
      test('creates model from entity correctly', () {
        final model = ModelInfoModel.fromEntity(const ModelInfo(
          model: 'best_model.joblib',
          loaded: true,
          steps: ['preprocessor', 'model'],
        ));

        expect(model.model, 'best_model.joblib');
        expect(model.loaded, true);
        expect(model.steps, ['preprocessor', 'model']);
      });

      test('handles null model and steps', () {
        final model = ModelInfoModel.fromEntity(const ModelInfo(
          model: null,
          loaded: false,
          steps: null,
        ));

        expect(model.model, isNull);
        expect(model.loaded, false);
        expect(model.steps, isNull);
      });
    });

    group('toEntity', () {
      test('converts model back to entity correctly', () {
        const model = ModelInfoModel(
          model: 'best_model.joblib',
          loaded: true,
          steps: ['preprocessor', 'model'],
        );

        final entity = model.toEntity();

        expect(entity.model, 'best_model.joblib');
        expect(entity.loaded, true);
        expect(entity.steps, ['preprocessor', 'model']);
      });

      test('handles null values', () {
        const model = ModelInfoModel(
          model: null,
          loaded: false,
          steps: null,
        );

        final entity = model.toEntity();

        expect(entity.model, isNull);
        expect(entity.loaded, false);
        expect(entity.steps, isNull);
      });
    });

    group('toJson', () {
      test('serializes to JSON correctly', () {
        const model = ModelInfoModel(
          model: 'best_model.joblib',
          loaded: true,
          steps: ['preprocessor', 'model'],
        );

        final json = model.toJson();

        expect(json['model'], 'best_model.joblib');
        expect(json['loaded'], true);
        expect(json['steps'], ['preprocessor', 'model']);
      });

      test('handles null values in JSON', () {
        const model = ModelInfoModel(
          model: null,
          loaded: false,
          steps: null,
        );

        final json = model.toJson();

        expect(json['model'], isNull);
        expect(json['loaded'], false);
        expect(json['steps'], isNull);
      });
    });

    group('fromJson', () {
      test('deserializes from JSON correctly', () {
        final json = {
          'model': 'best_model.joblib',
          'loaded': true,
          'steps': ['preprocessor', 'model'],
        };

        final model = ModelInfoModel.fromJson(json);

        expect(model.model, 'best_model.joblib');
        expect(model.loaded, true);
        expect(model.steps, ['preprocessor', 'model']);
      });

      test('handles null values in JSON', () {
        final json = {
          'model': null,
          'loaded': false,
          'steps': null,
        };

        final model = ModelInfoModel.fromJson(json);

        expect(model.model, isNull);
        expect(model.loaded, false);
        expect(model.steps, isNull);
      });

      test('handles missing optional fields', () {
        final json = {
          'loaded': true,
        };

        final model = ModelInfoModel.fromJson(json);

        expect(model.model, isNull);
        expect(model.loaded, true);
        expect(model.steps, isNull);
      });
    });

    group('equatable', () {
      test('equals returns true for equal models', () {
        const model1 = ModelInfoModel(
          model: 'best_model.joblib',
          loaded: true,
          steps: ['preprocessor', 'model'],
        );

        const model2 = ModelInfoModel(
          model: 'best_model.joblib',
          loaded: true,
          steps: ['preprocessor', 'model'],
        );

        expect(model1, equals(model2));
      });

      test('equals returns false for different models', () {
        const model1 = ModelInfoModel(
          model: 'best_model.joblib',
          loaded: true,
          steps: ['preprocessor', 'model'],
        );

        const model2 = ModelInfoModel(
          model: 'other_model.joblib',
          loaded: false,
          steps: ['model'],
        );

        expect(model1, isNot(equals(model2)));
      });

      test('equals returns true for both null fields', () {
        const model1 = ModelInfoModel(
          model: null,
          loaded: false,
          steps: null,
        );

        const model2 = ModelInfoModel(
          model: null,
          loaded: false,
          steps: null,
        );

        expect(model1, equals(model2));
      });
    });
  });
}
