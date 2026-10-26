import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:home_value/features/comparison/presentation/bloc/comparison_bloc.dart';
import 'package:home_value/features/comparison/domain/entities/model_comparison.dart';
import 'package:home_value/features/comparison/domain/repositories/comparison_repository.dart';

class MockComparisonRepository extends Mock implements ComparisonRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ModelMetric(
      name: 'test',
      rmse: 0.0,
      mae: 0.0,
      r2: 0.0,
      cvStd: 0.0,
      isBest: false,
    ));
    registerFallbackValue(const ModelComparison(metrics: []));
  });

  group('ComparisonBloc', () {
    late ComparisonBloc comparisonBloc;
    late MockComparisonRepository mockRepository;

    setUp(() {
      mockRepository = MockComparisonRepository();
      comparisonBloc = ComparisonBloc(repository: mockRepository);
    });

    tearDown(() {
      comparisonBloc.close();
    });

    const testComparison = ModelComparison(metrics: [
      ModelMetric(
        name: 'RandomForestRegressor',
        rmse: 0.52,
        mae: 0.41,
        r2: 0.85,
        cvStd: 0.03,
        isBest: true,
      ),
      ModelMetric(
        name: 'LinearRegression',
        rmse: 0.68,
        mae: 0.52,
        r2: 0.72,
        cvStd: 0.05,
        isBest: false,
      ),
    ]);

    blocTest<ComparisonBloc, ComparisonState>(
      'emits [ComparisonLoading, ComparisonLoaded] when LoadComparison succeeds',
      build: () {
        when(() => mockRepository.getModelComparison()).thenAnswer(
          (_) async => testComparison,
        );
        return ComparisonBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const LoadComparison()),
      expect: () => [
        const ComparisonLoading(),
        isA<ComparisonLoaded>(),
      ],
    );

    blocTest<ComparisonBloc, ComparisonState>(
      'emits [ComparisonFailure] when LoadComparison fails',
      build: () {
        when(() => mockRepository.getModelComparison()).thenThrow(
          Exception('Network error'),
        );
        return ComparisonBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const LoadComparison()),
      expect: () => [
        const ComparisonLoading(),
        isA<ComparisonFailure>(),
      ],
    );

    blocTest<ComparisonBloc, ComparisonState>(
      'emits [ComparisonLoaded] when RefreshComparison succeeds',
      build: () {
        when(() => mockRepository.getModelComparison()).thenAnswer(
          (_) async => testComparison,
        );
        return ComparisonBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const RefreshComparison()),
      expect: () => [
        isA<ComparisonLoaded>(),
      ],
    );

    blocTest<ComparisonBloc, ComparisonState>(
      'emits [ComparisonFailure] when RefreshComparison fails',
      build: () {
        when(() => mockRepository.getModelComparison()).thenThrow(
          Exception('Network error'),
        );
        return ComparisonBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const RefreshComparison()),
      expect: () => [
        isA<ComparisonFailure>(),
      ],
    );
  });
}
