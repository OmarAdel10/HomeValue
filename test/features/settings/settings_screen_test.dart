import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:home_value/features/settings/presentation/screens/settings_screen.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_event.dart';
import 'package:home_value/features/settings/domain/entities/app_settings.dart';
import 'package:home_value/features/settings/domain/repositories/settings_repository.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings(
      serverUrl: 'http://localhost:8000',
      themeMode: ThemeMode.system,
      autoRetrain: false,
    ));
    registerFallbackValue(ThemeMode.system);
    registerFallbackValue(DateTime(2026));
  });

  group('SettingsScreen', () {
    late MockSettingsRepository mockRepository;
    late SettingsBloc settingsBloc;
    late http.Client mockClient;

    setUp(() {
      mockRepository = MockSettingsRepository();
      mockClient = MockClient(
        (_) async => http.Response('{"status": "ok"}', 200),
      );
      when(() => mockRepository.updateLastAutoRetrain(any())).thenAnswer(
        (_) async => AppSettings.defaults(),
      );
      settingsBloc = SettingsBloc(
        repository: mockRepository,
        httpClient: mockClient,
      );
    });

    tearDown(() {
      settingsBloc.close();
      mockClient.close();
    });

    testWidgets('shows settings form when loaded', (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateServerUrl(any())).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateThemeMode(any())).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
        (_) async => testSettings,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Server URL'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Auto Retrain'), findsOneWidget);
    });

    testWidgets('updates server URL when form is submitted',
        (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      const updatedSettings = AppSettings(
        serverUrl: 'http://192.168.1.100:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateServerUrl('http://192.168.1.100:8000/'))
          .thenAnswer(
        (_) async => updatedSettings,
      );
      when(() => mockRepository.updateThemeMode(any())).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
        (_) async => testSettings,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter new server URL with trailing slash to pass validation
      await tester.enterText(
          find.byType(TextFormField), 'http://192.168.1.100:8000/');
      await tester.pumpAndSettle();

      // Tap save button
      await tester.tap(find.text('Save Server URL'));
      await tester.pumpAndSettle();

      verify(() => mockRepository.updateServerUrl('http://192.168.1.100:8000/'))
          .called(1);
    });

    testWidgets('toggles theme mode', (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      const darkSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.dark,
        autoRetrain: false,
      );

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateThemeMode(ThemeMode.dark)).thenAnswer(
        (_) async => darkSettings,
      );
      when(() => mockRepository.updateServerUrl(any())).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
        (_) async => testSettings,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap theme dropdown
      await tester.tap(find.byType(DropdownButtonFormField<ThemeMode>));
      await tester.pumpAndSettle();

      // Select Dark theme
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      verify(() => mockRepository.updateThemeMode(ThemeMode.dark)).called(1);
    });

    testWidgets('toggles auto retrain switch', (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      const updatedSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: true,
      );

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateAutoRetrain(true)).thenAnswer(
        (_) async => updatedSettings,
      );
      when(() => mockRepository.updateServerUrl(any())).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateThemeMode(any())).thenAnswer(
        (_) async => testSettings,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap auto retrain switch
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      verify(() => mockRepository.updateAutoRetrain(true)).called(1);
    });

    testWidgets('shows about section', (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateServerUrl(any())).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateThemeMode(any())).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
        (_) async => testSettings,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll to about section
      await tester.dragUntilVisible(
        find.text('Data: California Housing Dataset'),
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );

      expect(find.text('HomeValue'), findsOneWidget);
      expect(find.text('Version 1.0.0'), findsOneWidget);
      expect(find.text('Data: California Housing Dataset'), findsOneWidget);
    });

    testWidgets('shows an error with retry when loading settings fails',
        (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('API Server'), findsOneWidget);

      when(() => mockRepository.getSettings())
          .thenThrow(Exception('disk unavailable'));
      await tester.runAsync(() async {
        settingsBloc.add(const LoadSettings());
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();

      expect(find.text('Could not load settings'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('Could not read local settings. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Could not update settings'), findsNothing);

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );

      await tester.tap(find.text('Retry'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server URL'), findsOneWidget);
    });

    testWidgets('keeps the form and shows a snackbar when an update fails',
        (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateThemeMode(any()))
          .thenThrow(Exception('disk unavailable'));

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        settingsBloc.add(const ToggleTheme(ThemeMode.dark));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();

      expect(find.text('Could not update settings'), findsOneWidget);
      expect(find.text('Could not load settings'), findsNothing);
      expect(find.text('API Server'), findsOneWidget);
    });
  });
}
