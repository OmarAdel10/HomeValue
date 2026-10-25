import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:home_value/features/prediction/presentation/bloc/prediction_bloc.dart';
import 'package:home_value/features/prediction/presentation/bloc/prediction_event.dart';
import 'package:home_value/features/prediction/presentation/bloc/prediction_state.dart';
import 'package:home_value/features/prediction/domain/entities/house_features.dart';
import 'package:home_value/features/prediction/domain/entities/prediction_result.dart';
import 'package:home_value/features/prediction/domain/entities/model_info.dart';
import 'package:home_value/features/prediction/domain/repositories/prediction_repository.dart';

class MockPredictionRepository extends Mock implements PredictionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const HouseFeatures(
      medInc: 0.0,
      houseAge: 0.0,
      aveRooms: 0.0,
      aveBedrms: 0.0,
      population: 0.0,
      aveOccup: 0.0,
      latitude: 0.0,
      longitude: 0.0,
      oceanProximity: OceanProximity.inland,
    ));
  });

  group('PredictionBloc', () {
    late PredictionBloc predictionBloc;
    late MockPredictionRepository mockRepository;

    setUp(() {
      mockRepository = MockPredictionRepository();
      predictionBloc = PredictionBloc(repository: mockRepository);
    });

    tearDown(() {
      predictionBloc.close();
    });

    const testFeatures = HouseFeatures(
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

    const testResult = PredictionResult(
      prediction: 4.52,
      model: 'RandomForestRegressor',
      modelVersion: '1.0.0',
    );

    blocTest<PredictionBloc, PredictionState>(
      'emits [PredictionLoading, PredictionSuccess] when PredictRequested succeeds',
      build: () {
        when(() => mockRepository.predict(any())).thenAnswer(
          (_) async => testResult,
        );
        return PredictionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(PredictRequested(const HouseFeatures(
        medInc: 8.3252,
        houseAge: 41.0,
        aveRooms: 6.984127,
        aveBedrms: 1.02381,
        population: 322.0,
        aveOccup: 2.555556,
        latitude: 37.88,
        longitude: -122.23,
        oceanProximity: OceanProximity.nearBay,
      ))),
      expect: () => [
        PredictionLoading(),
        isA<PredictionSuccess>(),
      ],
    );

    blocTest<PredictionBloc, PredictionState>(
      'emits [PredictionLoading, PredictionFailure] when PredictRequested fails',
      build: () {
        when(() => mockRepository.predict(any())).thenThrow(
          Exception('Prediction failed'),
        );
        return PredictionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(PredictRequested(const HouseFeatures(
        medInc: 8.3252,
        houseAge: 41.0,
        aveRooms: 6.984127,
        aveBedrms: 1.02381,
        population: 322.0,
        aveOccup: 2.555556,
        latitude: 37.88,
        longitude: -122.23,
        oceanProximity: OceanProximity.nearBay,
      ))),
      expect: () => [
        PredictionLoading(),
        isA<PredictionFailure>(),
      ],
    );

    blocTest<PredictionBloc, PredictionState>(
      'emits [ModelInfoLoaded] when LoadModelInfo succeeds',
      build: () {
        when(() => mockRepository.getModelInfo()).thenAnswer(
          (_) async => ModelInfo(
            model: 'best_model.joblib',
            loaded: true,
            steps: ['preprocessor', 'model'],
          ),
        );
        return PredictionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const LoadModelInfo()),
      expect: () => [
        isA<ModelInfoLoaded>(),
      ],
    );

    blocTest<PredictionBloc, PredictionState>(
      'emits [ModelComparisonLoaded] when LoadModelComparison succeeds',
      build: () {
        when(() => mockRepository.getModelComparison()).thenAnswer(
          (_) async => [],
        );
        return PredictionBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const LoadModelComparison()),
      expect: () => [
        isA<ModelComparisonLoaded>(),
      ],
    );

    group('FormFieldChanged', () {
      blocTest<PredictionBloc, PredictionState>(
        'does not emit new state on FormFieldChanged',
        build: () => PredictionBloc(repository: mockRepository),
        act: (bloc) => bloc.add(const FormFieldChanged(
          field: 'MedInc',
          value: '8.3252',
        )),
        expect: () => [],
      );
    });

    group('ModelChanged', () {
      blocTest<PredictionBloc, PredictionState>(
        'emits [PredictionFailure] on ModelChanged (not implemented)',
        build: () => PredictionBloc(repository: mockRepository),
        act: (bloc) => bloc.add(const ModelChanged('RandomForestRegressor')),
        expect: () => [
          isA<PredictionFailure>(),
        ],
      );
    });
  });
}
