import 'package:flutter_test/flutter_test.dart';
import 'package:home_value/main.dart';
import 'package:home_value/core/di.dart' as di;

void main() {
  setUpAll(() async {
    await di.initDependencies();
  });

  testWidgets('App starts and shows home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Should find the home screen with prediction form
    expect(find.text('HomeValue'), findsOneWidget);
    expect(find.text('Predict House Price'), findsOneWidget);
  });
}