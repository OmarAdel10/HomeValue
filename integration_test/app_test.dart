import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_value/core/di.dart';
import 'package:home_value/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initDependencies();
  });

  tearDownAll(() async {
    await sl.reset();
  });

  group('End-to-end integration tests', () {
    testWidgets('App launches and shows home screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.text('Predict House Price'), findsOneWidget);
    });

    testWidgets('Prediction form is displayed with all fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

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

    testWidgets('Navigation to settings screen', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Server URL'), findsOneWidget);
    });

    testWidgets('Navigation to comparison screen', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.compare_arrows));
      await tester.pumpAndSettle();

      expect(find.text('Model Comparison'), findsOneWidget);
    });
  });
}
