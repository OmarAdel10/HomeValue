import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:home_value/features/prediction/presentation/screens/home_screen.dart';
import 'package:home_value/features/prediction/presentation/bloc/prediction_bloc.dart';
import 'package:home_value/features/prediction/presentation/bloc/prediction_event.dart';
import 'package:home_value/features/prediction/presentation/bloc/prediction_state.dart';
import 'package:home_value/features/prediction/domain/entities/house_features.dart';
import 'package:home_value/features/prediction/domain/entities/prediction_result.dart';
import 'package:home_value/features/prediction/domain/repositories/prediction_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bloc_test/bloc_test.dart';

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
  group('HomeScreen', () {
    late MockPredictionRepository mockRepository;

    setUp(() {
      mockRepository = MockPredictionRepository();
    });

    tearDown(() {});

    testWidgets('renders prediction form with all fields',
        (WidgetTester tester) async {
      when(() => mockRepository.predict(any()))
          .thenAnswer((_) async => const PredictionResult(
                prediction: 4.52,
                model: 'RandomForestRegressor',
                modelVersion: '1.0.0',
              ));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<PredictionBloc>(
            create: (_) => PredictionBloc(repository: mockRepository),
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check that all form fields are present
      expect(find.text('Median Income (in \$100k)'), findsOneWidget);
      expect(find.text('House Age (years)'), findsOneWidget);
      expect(find.text('Average Rooms per Household'), findsOneWidget);
      expect(find.text('Average Bedrooms per Household'), findsOneWidget);
      expect(find.text('Block Group Population'), findsOneWidget);
      expect(find.text('Average Household Occupancy'), findsOneWidget);
      expect(find.text('Latitude'), findsOneWidget);
      expect(find.text('Longitude'), findsOneWidget);
      expect(find.text('Ocean Proximity'), findsOneWidget);
    });

    testWidgets('shows validation error when fields are empty',
        (WidgetTester tester) async {
      when(() => mockRepository.predict(any()))
          .thenAnswer((_) async => const PredictionResult(
                prediction: 4.52,
                model: 'RandomForestRegressor',
                modelVersion: '1.0.0',
              ));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<PredictionBloc>(
            create: (_) => PredictionBloc(repository: mockRepository),
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll to and tap predict button without filling form
      await tester.ensureVisible(find.text('Predict Price'));
      await tester.tap(find.text('Predict Price'));
      await tester.pumpAndSettle();

      // Should show validation errors
      expect(
          find.text('Please enter Median Income (in \$100k)'), findsOneWidget);
    });

    testWidgets('shows prediction result dialog on success',
        (WidgetTester tester) async {
      when(() => mockRepository.predict(any()))
          .thenAnswer((_) async => const PredictionResult(
                prediction: 4.52,
                model: 'RandomForestRegressor',
                modelVersion: '1.0.0',
              ));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<PredictionBloc>(
            create: (_) => PredictionBloc(repository: mockRepository),
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Fill form with valid data - use byWidgetPredicate with labels to target specific fields
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Median Income (in \$100k)'),
          '8.3252');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'House Age (years)'), '41.0');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Average Rooms per Household'),
          '6.984127');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Average Bedrooms per Household'),
          '1.02381');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Block Group Population'),
          '322.0');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Average Household Occupancy'),
          '2.555556');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Latitude'), '37.88');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Longitude'), '-122.23');

      // Select ocean proximity - scroll to dropdown, tap it, then select from menu
      await tester
          .ensureVisible(find.byKey(const Key('ocean_proximity_dropdown')));
      await tester.tap(find.byKey(const Key('ocean_proximity_dropdown')));
      await tester.pumpAndSettle();

      // Select NEAR BAY from dropdown menu
      await tester.tap(find.text('NEAR BAY').first);
      await tester.pumpAndSettle();

      // Tap predict button - scroll to it first
      await tester.ensureVisible(find.text('Predict Price'));
      await tester.tap(find.text('Predict Price'));
      await tester.pumpAndSettle();

      // Should show prediction dialog
      expect(find.text('Prediction Result'), findsOneWidget);
      expect(find.textContaining('452000'), findsOneWidget);
    });
  });
}
