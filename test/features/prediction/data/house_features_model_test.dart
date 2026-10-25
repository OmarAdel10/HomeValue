import 'package:test/test.dart';
import 'package:home_value/features/prediction/data/models/house_features_model.dart';
import 'package:home_value/features/prediction/domain/entities/house_features.dart';

void main() {
  group('HouseFeaturesModel', () {
    const testEntity = HouseFeatures(
      medInc: 8.3252,
      houseAge: 41.0,
      aveRooms: 6.984127,
      aveBedrms: 1.02381,
      population: 322.0,
      aveOccup: 2.555556,
      latitude: 37.88,
      longitude: -122.23,
      oceanProximity: OceanProximity.nearBay,
    );

    const testJson = {
      'MedInc': 8.3252,
      'HouseAge': 41.0,
      'AveRooms': 6.984127,
      'AveBedrms': 1.02381,
      'Population': 322.0,
      'AveOccup': 2.555556,
      'Latitude': 37.88,
      'Longitude': -122.23,
      'ocean_proximity': 'NEAR BAY',
    };

    group('fromEntity', () {
      test('creates model from entity correctly', () {
        final model = HouseFeaturesModel.fromEntity(HouseFeatures(
          medInc: 8.3252,
          houseAge: 41.0,
          aveRooms: 6.984127,
          aveBedrms: 1.02381,
          population: 322.0,
          aveOccup: 2.555556,
          latitude: 37.88,
          longitude: -122.23,
          oceanProximity: OceanProximity.nearBay,
        ));

        expect(model.medInc, 8.3252);
        expect(model.houseAge, 41.0);
        expect(model.aveRooms, 6.984127);
        expect(model.aveBedrms, 1.02381);
        expect(model.population, 322.0);
        expect(model.aveOccup, 2.555556);
        expect(model.latitude, 37.88);
        expect(model.longitude, -122.23);
        expect(model.oceanProximity, 'NEAR BAY');
      });
    });

    group('toEntity', () {
      test('converts model back to entity correctly', () {
        const model = HouseFeaturesModel(
          medInc: 8.3252,
          houseAge: 41.0,
          aveRooms: 6.984127,
          aveBedrms: 1.02381,
          population: 322.0,
          aveOccup: 2.555556,
          latitude: 37.88,
          longitude: -122.23,
          oceanProximity: 'NEAR BAY',
        );

        final entity = model.toEntity();

        expect(entity.medInc, 8.3252);
        expect(entity.houseAge, 41.0);
        expect(entity.aveRooms, 6.984127);
        expect(entity.aveBedrms, 1.02381);
        expect(entity.population, 322.0);
        expect(entity.aveOccup, 2.555556);
        expect(entity.latitude, 37.88);
        expect(entity.longitude, -122.23);
        expect(entity.oceanProximity, OceanProximity.nearBay);
      });
    });

    group('toJson', () {
      test('serializes to JSON correctly', () {
        const model = HouseFeaturesModel(
          medInc: 8.3252,
          houseAge: 41.0,
          aveRooms: 6.984127,
          aveBedrms: 1.02381,
          population: 322.0,
          aveOccup: 2.555556,
          latitude: 37.88,
          longitude: -122.23,
          oceanProximity: 'NEAR BAY',
        );

        final json = model.toJson();

        expect(json['MedInc'], 8.3252);
        expect(json['HouseAge'], 41.0);
        expect(json['AveRooms'], 6.984127);
        expect(json['AveBedrms'], 1.02381);
        expect(json['Population'], 322.0);
        expect(json['AveOccup'], 2.555556);
        expect(json['Latitude'], 37.88);
        expect(json['Longitude'], -122.23);
        expect(json['ocean_proximity'], 'NEAR BAY');
      });
    });

    group('fromJson', () {
      test('deserializes from JSON correctly', () {
        final json = {
          'MedInc': 8.3252,
          'HouseAge': 41.0,
          'AveRooms': 6.984127,
          'AveBedrms': 1.02381,
          'Population': 322.0,
          'AveOccup': 2.555556,
          'Latitude': 37.88,
          'Longitude': -122.23,
          'ocean_proximity': 'NEAR BAY',
        };

        final model = HouseFeaturesModel.fromJson(json);

        expect(model.medInc, 8.3252);
        expect(model.houseAge, 41.0);
        expect(model.aveRooms, 6.984127);
        expect(model.aveBedrms, 1.02381);
        expect(model.population, 322.0);
        expect(model.aveOccup, 2.555556);
        expect(model.latitude, 37.88);
        expect(model.longitude, -122.23);
        expect(model.oceanProximity, 'NEAR BAY');
      });

      test('handles integer values in JSON', () {
        final json = {
          'MedInc': 8,
          'HouseAge': 41,
          'AveRooms': 7,
          'AveBedrms': 1,
          'Population': 322,
          'AveOccup': 3,
          'Latitude': 38,
          'Longitude': -122,
          'ocean_proximity': 'INLAND',
        };

        final model = HouseFeaturesModel.fromJson(json);

        expect(model.medInc, 8.0);
        expect(model.houseAge, 41.0);
        expect(model.aveRooms, 7.0);
        expect(model.aveBedrms, 1.0);
        expect(model.population, 322.0);
        expect(model.aveOccup, 3.0);
        expect(model.latitude, 38.0);
        expect(model.longitude, -122.0);
        expect(model.oceanProximity, 'INLAND');
      });
    });

    group('equatable', () {
      test('equals returns true for equal models', () {
        const model1 = HouseFeaturesModel(
          medInc: 8.3252,
          houseAge: 41.0,
          aveRooms: 6.984127,
          aveBedrms: 1.02381,
          population: 322.0,
          aveOccup: 2.555556,
          latitude: 37.88,
          longitude: -122.23,
          oceanProximity: 'NEAR BAY',
        );

        const model2 = HouseFeaturesModel(
          medInc: 8.3252,
          houseAge: 41.0,
          aveRooms: 6.984127,
          aveBedrms: 1.02381,
          population: 322.0,
          aveOccup: 2.555556,
          latitude: 37.88,
          longitude: -122.23,
          oceanProximity: 'NEAR BAY',
        );

        expect(model1, equals(model2));
      });

      test('equals returns false for different models', () {
        const model1 = HouseFeaturesModel(
          medInc: 8.3252,
          houseAge: 41.0,
          aveRooms: 6.984127,
          aveBedrms: 1.02381,
          population: 322.0,
          aveOccup: 2.555556,
          latitude: 37.88,
          longitude: -122.23,
          oceanProximity: 'NEAR BAY',
        );

        const model2 = HouseFeaturesModel(
          medInc: 4.0,
          houseAge: 20.0,
          aveRooms: 5.0,
          aveBedrms: 2.0,
          population: 100.0,
          aveOccup: 3.0,
          latitude: 34.0,
          longitude: -118.0,
          oceanProximity: 'INLAND',
        );

        expect(model1, isNot(equals(model2)));
      });
    });
  });
}
