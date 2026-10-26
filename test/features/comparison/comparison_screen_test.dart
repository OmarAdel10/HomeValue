import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:home_value/features/comparison/presentation/screens/comparison_screen.dart';
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

  group('ComparisonScreen', () {
    late MockComparisonRepository mockRepository;

    setUp(() {
      mockRepository = MockComparisonRepository();
    });

    tearDown(() {});

    testWidgets('shows comparison data when loaded',
        (WidgetTester tester) async {
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

      when(() => mockRepository.getModelComparison()).thenAnswer(
        (_) async => testComparison,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<ComparisonBloc>(
            create: (_) => ComparisonBloc(repository: mockRepository),
            child: const ComparisonScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check that chart and table are rendered
      expect(find.text('Model Performance Metrics'), findsOneWidget);
      expect(find.text('RMSE Comparison'), findsOneWidget);
      expect(find.text('RandomForestRegressor'), findsWidgets);
      expect(find.text('LinearRegression'), findsWidgets);
      expect(find.text('BEST'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (WidgetTester tester) async {
      when(() => mockRepository.getModelComparison()).thenThrow(
        Exception('Network error'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<ComparisonBloc>(
            create: (_) => ComparisonBloc(repository: mockRepository),
            child: const ComparisonScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load comparison'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('can switch between metrics', (WidgetTester tester) async {
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

      when(() => mockRepository.getModelComparison()).thenAnswer(
        (_) async => testComparison,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<ComparisonBloc>(
            create: (_) => ComparisonBloc(repository: mockRepository),
            child: const ComparisonScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap MAE segment - find the MAE text inside the SegmentedButton
      await tester.tap(find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.text('MAE'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('MAE Comparison'), findsOneWidget);
    });

    testWidgets('refresh button triggers reload', (WidgetTester tester) async {
      const testComparison = ModelComparison(metrics: [
        ModelMetric(
          name: 'RandomForestRegressor',
          rmse: 0.52,
          mae: 0.41,
          r2: 0.85,
          cvStd: 0.03,
          isBest: true,
        ),
      ]);

      when(() => mockRepository.getModelComparison()).thenAnswer(
        (_) async => testComparison,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<ComparisonBloc>(
            create: (_) => ComparisonBloc(repository: mockRepository),
            child: const ComparisonScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap refresh button
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      verify(() => mockRepository.getModelComparison()).called(2);
    });
  });
}
