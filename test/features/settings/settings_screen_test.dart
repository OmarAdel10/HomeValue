import 'dart:io';

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
import 'package:home_value/core/validation.dart' as validation;

class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.system,
      autoRetrain: false,
      initialRetrainDelay: Duration.zero,
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
      when(() => mockRepository.serverUrlBlocked).thenReturn(false);
      // Stub DNS so auto-retrain scheduling never performs real lookups
      // inside widget tests (offline determinism).
      validation.dnsLookup =
          (host) async => <InternetAddress>[InternetAddress('8.8.8.8')];
      settingsBloc = SettingsBloc(
        repository: mockRepository,
        httpClient: mockClient,
        dnsLookup: (host) async =>
            <InternetAddress>[InternetAddress('8.8.8.8')],
      );
    });

    tearDown(() {
      settingsBloc.close();
      mockClient.close();
      validation.dnsLookup = InternetAddress.lookup;
    });

    testWidgets('shows settings form when loaded', (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://example.com:8000',
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
        serverUrl: 'http://example.com:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      const updatedSettings = AppSettings(
        serverUrl: 'http://example.com:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => testSettings,
      );
      when(() => mockRepository.updateServerUrl('http://example.com:8000/'))
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
          find.byType(TextFormField), 'http://example.com:8000/');
      await tester.pumpAndSettle();

      // Tap save button
      await tester.tap(find.text('Save Server URL'));
      await tester.pumpAndSettle();

      verify(() => mockRepository.updateServerUrl('http://example.com:8000/'))
          .called(1);
    });

    testWidgets('rejects a blocked server URL without updating',
        (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://example.com:8000',
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

      // Enter a blocked (private) server URL.
      await tester.enterText(
          find.byType(TextFormField), 'http://127.0.0.1:8000/');
      await tester.pumpAndSettle();

      // Tap save button: form validation must reject the host.
      await tester.tap(find.text('Save Server URL'));
      await tester.pumpAndSettle();

      verifyNever(() => mockRepository.updateServerUrl(any()));
    });

    testWidgets('toggles theme mode', (WidgetTester tester) async {
      const testSettings = AppSettings(
        serverUrl: 'http://example.com:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      const darkSettings = AppSettings(
        serverUrl: 'http://example.com:8000',
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
        serverUrl: 'http://example.com:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

      const updatedSettings = AppSettings(
        serverUrl: 'http://example.com:8000',
        themeMode: ThemeMode.system,
        autoRetrain: true,
        initialRetrainDelay: Duration.zero,
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
        serverUrl: 'http://example.com:8000',
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
        serverUrl: 'http://example.com:8000',
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
        serverUrl: 'http://example.com:8000',
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

      // The snackbar surfaces the bloc's (leak-safe) failure message so
      // suspension notices are visible, not a hardcoded generic string.
      expect(find.text('Operation failed'), findsOneWidget);
      expect(find.text('Could not update settings'), findsNothing);
      expect(find.text('Could not load settings'), findsNothing);
      expect(find.text('API Server'), findsOneWidget);
    });

    testWidgets('shows the auto-retrain suspension notice verbatim',
        (WidgetTester tester) async {
      // The retrain window is judged against the bloc's injectable clock;
      // widget pumps advance the test's fake clock 1s per pump, so `now`
      // must follow it or every attempt beyond the first is judged not-due.
      var fakeNow = DateTime(2026, 1, 1);
      final overdueSettings = AppSettings(
        serverUrl: 'http://8.8.8.8:8000',
        themeMode: ThemeMode.system,
        autoRetrain: true,
        lastAutoRetrainAt: fakeNow.subtract(const Duration(days: 2)),
        initialRetrainDelay: Duration.zero,
      );
      final failingClient = MockClient(
        (request) async => throw http.ClientException('backend down'),
      );
      addTearDown(failingClient.close);
      final suspensionBloc = SettingsBloc(
        repository: mockRepository,
        httpClient: failingClient,
        dnsLookup: (host) async =>
            <InternetAddress>[InternetAddress('8.8.8.8')],
        retrainInterval: const Duration(seconds: 1),
        now: () => fakeNow,
      );
      addTearDown(suspensionBloc.close);

      when(() => mockRepository.getSettings())
          .thenAnswer((_) async => overdueSettings);
      when(() => mockRepository.updateLastAutoRetrain(any()))
          .thenAnswer((_) async => overdueSettings);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsBloc>.value(
            value: suspensionBloc,
            child: const SettingsScreen(),
          ),
        ),
      );
      // One plain pump: processes the LoadSettings microtasks and schedules
      // the zero-delay first retrain without advancing the clock.
      await tester.pump();

      // Drive the 5 consecutive failures that reach the suspension cap:
      // each iteration advances both the test clock (pump) and the bloc's
      // injected clock so the next window is judged due exactly on fire.
      for (var i = 0; i < 8; i++) {
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }

      // The suspension must be visible verbatim in the UI, not a hardcoded
      // generic string: the user cannot see that retraining stopped otherwise.
      expect(
        find.text('Auto-retrain suspended after 5 consecutive failures'),
        findsOneWidget,
      );
    });
  });
}
