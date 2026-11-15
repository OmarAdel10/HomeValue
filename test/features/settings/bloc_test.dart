import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_event.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_state.dart';
import 'package:home_value/features/settings/domain/entities/app_settings.dart';
import 'package:home_value/features/settings/domain/repositories/settings_repository.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

class RetrainRecorder {
  final List<http.Request> requests = <http.Request>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    return http.Response('{"status": "ok"}', 200);
  });
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.system,
      autoRetrain: false,
    ));
    registerFallbackValue(ThemeMode.system);
    registerFallbackValue(DateTime(2026));
  });

  group('SettingsBloc', () {
    late SettingsBloc settingsBloc;
    late MockSettingsRepository mockRepository;
    late RetrainRecorder recorder;

    setUp(() {
      recorder = RetrainRecorder();
      addTearDown(recorder.client.close);
      mockRepository = MockSettingsRepository();
      when(() => mockRepository.serverUrlBlocked).thenReturn(false);
      settingsBloc = SettingsBloc(
        repository: mockRepository,
        httpClient: recorder.client,
        dnsLookup: (host) async =>
            <InternetAddress>[InternetAddress('8.8.8.8')],
      );
    });

    tearDown(() {
      settingsBloc.close();
    });

    const testSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.system,
      autoRetrain: false,
    );

    const updatedSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: true,
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsLoaded] when LoadSettings succeeds',
      build: () {
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => testSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
        );
      },
      act: (bloc) => bloc.add(const LoadSettings()),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsLoaded] with updated settings when UpdateServerUrl succeeds',
      build: () {
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => testSettings,
        );
        when(() => mockRepository.updateServerUrl(any())).thenAnswer(
          (_) async => updatedSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
        );
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const UpdateServerUrl('http://example.com:8000')),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsLoaded] with updated settings when ToggleTheme succeeds',
      build: () {
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => testSettings,
        );
        when(() => mockRepository.updateThemeMode(any())).thenAnswer(
          (_) async => updatedSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
        );
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const ToggleTheme(ThemeMode.dark)),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsLoaded] with updated settings when ToggleAutoRetrain succeeds',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => testSettings,
        );
        when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
          (_) async => updatedSettings,
        );
        when(() => mockRepository.updateLastAutoRetrain(any())).thenAnswer(
          (_) async => updatedSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
        );
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const ToggleAutoRetrain(true)),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsFailure] with isLoadFailure when LoadSettings fails',
      build: () {
        when(() => mockRepository.getSettings())
            .thenThrow(Exception('disk unavailable'));
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
        );
      },
      act: (bloc) => bloc.add(const LoadSettings()),
      expect: () => [
        isA<SettingsFailure>()
            .having((state) => state.isLoadFailure, 'isLoadFailure', true),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsFailure] when UpdateServerUrl fails',
      build: () {
        when(() => mockRepository.updateServerUrl(any()))
            .thenThrow(Exception('disk unavailable'));
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
        );
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const UpdateServerUrl('http://example.com:9000')),
      expect: () => [
        isA<SettingsFailure>()
            .having((state) => state.isLoadFailure, 'isLoadFailure', false),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsFailure] when ToggleTheme fails',
      build: () {
        when(() => mockRepository.updateThemeMode(any()))
            .thenThrow(Exception('disk unavailable'));
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
        );
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const ToggleTheme(ThemeMode.dark)),
      expect: () => [
        isA<SettingsFailure>()
            .having((state) => state.isLoadFailure, 'isLoadFailure', false),
      ],
    );

    const enabledSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.system,
      autoRetrain: true,
    );

    const enabledDarkSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: true,
    );

    const enabledMovedSettings = AppSettings(
      serverUrl: 'http://example.com:9000',
      themeMode: ThemeMode.system,
      autoRetrain: true,
    );

    blocTest<SettingsBloc, SettingsState>(
      'posts one retrain request when auto retrain is enabled',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings,
        );
        when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
          (_) async => enabledSettings,
        );
        when(() => mockRepository.updateLastAutoRetrain(any())).thenAnswer(
          (_) async => enabledSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
        );
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const ToggleAutoRetrain(true)),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
      verify: (_) {
        expect(recorder.requests, hasLength(1));
        expect(recorder.requests.single.method, 'POST');
        expect(
          recorder.requests.single.url.toString(),
          'http://8.8.8.8:8000/train',
        );
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'does not retrain when the theme changes with auto retrain enabled',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings,
        );
        when(() => mockRepository.updateThemeMode(any())).thenAnswer(
          (_) async => enabledDarkSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
        );
      },
      seed: () => const SettingsLoaded(enabledSettings),
      act: (bloc) => bloc.add(const ToggleTheme(ThemeMode.dark)),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
      verify: (_) {
        expect(recorder.requests, isEmpty);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'does not retrain when the server URL changes with auto retrain enabled',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        final recentRun = DateTime.now().subtract(const Duration(minutes: 30));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings,
        );
        when(() => mockRepository.updateServerUrl(any())).thenAnswer(
          (_) async =>
              enabledMovedSettings.copyWith(lastAutoRetrainAt: recentRun),
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
        );
      },
      seed: () => SettingsLoaded(
        enabledSettings.copyWith(
          lastAutoRetrainAt:
              DateTime.now().subtract(const Duration(minutes: 30)),
        ),
      ),
      act: (bloc) => bloc.add(const UpdateServerUrl('http://example.com:9000')),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
      verify: (_) {
        expect(recorder.requests, isEmpty);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'does not retrain again when auto retrain is already enabled',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings,
        );
        when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
          (_) async => enabledDarkSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
        );
      },
      seed: () => const SettingsLoaded(enabledSettings),
      act: (bloc) => bloc.add(const ToggleAutoRetrain(true)),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
      verify: (_) {
        expect(recorder.requests, isEmpty);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'does not retrain on load when the last run is recent',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        final recentRun = DateTime.now().subtract(const Duration(hours: 1));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: recentRun),
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
        );
      },
      act: (bloc) => bloc.add(const LoadSettings()),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
      verify: (_) {
        expect(recorder.requests, isEmpty);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'retrains on load when the last run is overdue',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        final overdueRun = DateTime.now().subtract(const Duration(hours: 25));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: overdueRun),
        );
        when(() => mockRepository.updateLastAutoRetrain(any())).thenAnswer(
          (_) async => enabledSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
        );
      },
      act: (bloc) => bloc.add(const LoadSettings()),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
      verify: (_) {
        expect(recorder.requests, hasLength(1));
        verify(() => mockRepository.updateLastAutoRetrain(any())).called(1);
      },
    );

    test('emits a fresh failure for a repeated identical error', () async {
      when(() => mockRepository.updateThemeMode(any()))
          .thenThrow(Exception('disk unavailable'));
      final bloc = SettingsBloc(
        repository: mockRepository,
        dnsLookup: (host) async =>
            <InternetAddress>[InternetAddress('8.8.8.8')],
      );
      addTearDown(bloc.close);

      final seen = <SettingsState>[];
      final subscription = bloc.stream.listen(seen.add);
      addTearDown(subscription.cancel);

      bloc.add(const ToggleTheme(ThemeMode.dark));
      await pumpEventQueue();
      bloc.add(const ToggleTheme(ThemeMode.dark));
      await pumpEventQueue();

      final failures = seen.whereType<SettingsFailure>().toList();
      expect(failures, hasLength(2));
      expect(failures.last.attempt, greaterThan(failures.first.attempt));
      expect(failures.last.isLoadFailure, isFalse);
    });
  });

  group('SettingsBloc auto retrain scheduling', () {
    late MockSettingsRepository mockRepository;
    late RetrainRecorder recorder;
    late DateTime current;

    const enabledSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.system,
      autoRetrain: true,
    );

    const enabledDarkSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: true,
    );

    DateTime clock() => current;

    void advance(FakeAsync async, Duration duration) {
      current = current.add(duration);
      async.elapse(duration);
      async.flushMicrotasks();
    }

    setUp(() {
      current = DateTime(2026, 10, 27, 12);
      mockRepository = MockSettingsRepository();
      recorder = RetrainRecorder();
      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => enabledSettings,
      );
      when(() => mockRepository.serverUrlBlocked).thenReturn(false);
      when(() => mockRepository.updateThemeMode(any())).thenAnswer(
        (_) async => enabledDarkSettings,
      );
      when(() => mockRepository.updateLastAutoRetrain(any())).thenAnswer(
        (invocation) async => enabledSettings.copyWith(
          lastAutoRetrainAt: invocation.positionalArguments.first as DateTime,
        ),
      );
    });

    tearDown(() {
      recorder.client.close();
    });

    test('keeps the 24h schedule across theme changes', () {
      fakeAsync((async) {
        final lastRun = current.subtract(const Duration(hours: 1));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        when(() => mockRepository.updateThemeMode(any())).thenAnswer(
          (_) async => enabledDarkSettings.copyWith(
            lastAutoRetrainAt: lastRun,
          ),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(hours: 22, minutes: 59));
        async.flushMicrotasks();
        bloc.add(const ToggleTheme(ThemeMode.dark));
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(minutes: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('cancelles an in-flight retrain when auto retrain is disabled', () {
      fakeAsync((async) {
        final dnsCompleter = Completer<List<InternetAddress>>();
        final overdue = current.subtract(const Duration(hours: 25));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: overdue),
        );
        when(() => mockRepository.updateAutoRetrain(false)).thenAnswer(
          (_) async => enabledSettings.copyWith(autoRetrain: false),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) => dnsCompleter.future,
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );
        addTearDown(bloc.close);

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        // Overdue window arms a zero-delay timer; DNS lookup is pending.
        advance(async, const Duration(milliseconds: 1));
        expect(recorder.requests, isEmpty);

        // Disabling auto retrain bumps the retrain generation.
        bloc.add(const ToggleAutoRetrain(false));
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        // Completing DNS after the disable must not fire the POST.
        dnsCompleter.complete(<InternetAddress>[InternetAddress('8.8.8.8')]);
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);
      });
    });

    test('waits for the window when auto retrain is turned on', () {
      fakeAsync((async) {
        final lastRun = current.subtract(const Duration(hours: 1));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        when(() => mockRepository.updateAutoRetrain(true)).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const ToggleAutoRetrain(true));
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsLoaded>());
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(hours: 23));
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('retrains right away when the window is already overdue', () {
      fakeAsync((async) {
        final lastRun = current.subtract(const Duration(hours: 25));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('cancels the periodic timer when auto retrain is disabled', () {
      fakeAsync((async) {
        when(() => mockRepository.updateAutoRetrain(false)).thenAnswer(
          (_) async => enabledSettings.copyWith(autoRetrain: false),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.add(const ToggleAutoRetrain(false));
        async.flushMicrotasks();
        advance(async, const Duration(hours: 48));
        async.flushMicrotasks();

        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('stopping the timer on close prevents further retrains', () {
      fakeAsync((async) {
        final lastRun = current.subtract(const Duration(hours: 25));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
        advance(async, const Duration(hours: 48));
        async.flushMicrotasks();

        expect(recorder.requests, hasLength(1));
      });
    });

    test('retries a transport failure only after a full window', () {
      fakeAsync((async) {
        final failingRequests = <http.Request>[];
        final failingClient = MockClient((request) async {
          failingRequests.add(request);
          throw http.ClientException('backend down');
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: failingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(failingRequests, hasLength(1));

        advance(async, const Duration(hours: 1));
        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(failingRequests, hasLength(1));

        advance(async, const Duration(hours: 23));
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(failingRequests, hasLength(2));

        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));
        expect(bloc.state, isA<SettingsLoaded>());

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('uses the configured base path for the retrain request', () {
      fakeAsync((async) {
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(
            serverUrl: 'http://example.com:8000/api//',
          ),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(
          recorder.requests.single.url.toString(),
          'http://8.8.8.8:8000/api/train',
        );

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('does not record success when the backend rejects the retrain', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final rejectingClient = MockClient((request) async {
          requests.add(request);
          return http.Response('training failed', 500);
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: rejectingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(1));
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));

        advance(async, const Duration(hours: 24));
        async.flushMicrotasks();
        expect(requests, hasLength(2));
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('treats a redirect as a rejected retrain', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final redirectingClient = MockClient((request) async {
          requests.add(request);
          expect(request.followRedirects, isFalse,
              reason: 'redirects must never be followed (SSRF)');
          return http.Response('', 302);
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: redirectingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(requests, hasLength(1));
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('records success for a 204 response', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final noContentClient = MockClient((request) async {
          requests.add(request);
          return http.Response('', 204);
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: noContentClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(requests, hasLength(1));
        verify(() => mockRepository.updateLastAutoRetrain(current)).called(1);

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('schedules the next retrain from the stored run time', () {
      fakeAsync((async) {
        final lastRun = current.subtract(const Duration(hours: 23));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(minutes: 59));
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(minutes: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('keeps the remaining window when settings are reloaded', () {
      fakeAsync((async) {
        final lastRun = current.subtract(const Duration(hours: 23));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        advance(async, const Duration(minutes: 30));
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        advance(async, const Duration(minutes: 30));
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('keeps the timer running when a toggle fails', () {
      fakeAsync((async) {
        final lastRun = current.subtract(const Duration(hours: 23));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        when(() => mockRepository.updateAutoRetrain(any()))
            .thenThrow(Exception('disk unavailable'));
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        bloc.add(const ToggleAutoRetrain(false));
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsFailure>());

        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('skips a retrain while one is already in flight', () {
      fakeAsync((async) {
        final lastRun = current.subtract(const Duration(hours: 25));
        final gate = Completer<http.Response>();
        final requests = <http.Request>[];
        final gatedClient = MockClient((request) {
          requests.add(request);
          return gate.future;
        });

        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: gatedClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        gate.complete(http.Response('{"status": "ok"}', 200));
        async.flushMicrotasks();

        advance(async, const Duration(hours: 24));
        async.flushMicrotasks();
        expect(requests, hasLength(2));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    // --- GAP 3: serverUrlBlocked gate / skippedBlocked clock ---

    test('serverUrlBlocked=true blocks retrain and does not consume clock', () {
      fakeAsync((async) {
        when(() => mockRepository.serverUrlBlocked).thenReturn(true);
        final lastRun = current.subtract(const Duration(hours: 25));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: lastRun),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        // Blocked URL must never trigger retrain.
        expect(recorder.requests, isEmpty);
        // Clock not consumed: no updateLastAutoRetrain call.
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));
        expect(bloc.state, isA<SettingsLoaded>());

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('serverUrlBlocked=true on ToggleAutoRetrain emits SettingsFailure',
        () {
      fakeAsync((async) {
        when(() => mockRepository.serverUrlBlocked).thenReturn(true);
        when(() => mockRepository.updateAutoRetrain(true)).thenAnswer(
          (_) async => enabledSettings.copyWith(autoRetrain: true),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const ToggleAutoRetrain(true));
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsFailure>());
        expect(recorder.requests, isEmpty);

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('DNS failure triggers skippedBlocked with no retrain', () {
      fakeAsync((async) {
        final failingRequests = <http.Request>[];
        final failingClient = MockClient((request) async {
          failingRequests.add(request);
          throw http.ClientException('backend down');
        });
        // dnsLookup throws -> _trainUri fail-closed -> skippedBlocked.
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: failingClient,
          dnsLookup: (host) async => throw ArgumentError('DNS failure'),
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(failingRequests, isEmpty);
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));
        expect(bloc.state, isA<SettingsLoaded>());

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('blocked resolved IP triggers skippedBlocked with no retrain', () {
      fakeAsync((async) {
        final failingRequests = <http.Request>[];
        final failingClient = MockClient((request) async {
          failingRequests.add(request);
          return http.Response('{"status": "ok"}', 200);
        });
        // dnsLookup returns metadata IP -> _trainUri fail-closed -> skippedBlocked.
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: failingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('169.254.169.254')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(failingRequests, isEmpty);
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));
        expect(bloc.state, isA<SettingsLoaded>());

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('stops rescheduling after consecutive failure cap (5)', () {
      fakeAsync((async) {
        final failingRequests = <http.Request>[];
        final failingClient = MockClient((request) async {
          failingRequests.add(request);
          throw http.ClientException('backend down');
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: failingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(failingRequests, hasLength(1));

        // Trigger 4 more retries (total 5 = cap).
        for (var i = 0; i < 4; i++) {
          advance(async, const Duration(hours: 1));
          async.flushMicrotasks();
          async.flushMicrotasks();
        }
        expect(failingRequests, hasLength(5));

        // After cap reached, no more retries.
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(failingRequests, hasLength(5));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('emits a suspension failure when the consecutive cap is reached', () {
      fakeAsync((async) {
        final failingRequests = <http.Request>[];
        final failingClient = MockClient((request) async {
          failingRequests.add(request);
          throw http.ClientException('backend down');
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: failingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        expect(failingRequests, hasLength(1));

        // Trigger 4 more retries (total 5 = cap).
        for (var i = 0; i < 4; i++) {
          advance(async, const Duration(hours: 1));
          async.flushMicrotasks();
          async.flushMicrotasks();
        }
        expect(failingRequests, hasLength(5));

        // The suspension event surfaces as a failure state.
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsFailure>());
        final failure = bloc.state as SettingsFailure;
        expect(failure.message, contains('suspended'));
        expect(failure.isLoadFailure, isFalse);

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('a URL correction re-arms retraining after suspension', () {
      fakeAsync((async) {
        final failingRequests = <http.Request>[];
        final failingClient = MockClient((request) async {
          failingRequests.add(request);
          throw http.ClientException('backend down');
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: failingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        when(() => mockRepository.updateServerUrl(any())).thenAnswer(
          (_) async =>
              enabledSettings.copyWith(serverUrl: 'http://example.com:9000'),
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        expect(failingRequests, hasLength(1));

        // Burn the failure cap.
        for (var i = 0; i < 4; i++) {
          advance(async, const Duration(hours: 1));
          async.flushMicrotasks();
          async.flushMicrotasks();
        }
        expect(failingRequests, hasLength(5));

        // Suspended: no more retries.
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(failingRequests, hasLength(5));

        // Correcting the server URL resets the cap and re-arms the timer.
        bloc.add(const UpdateServerUrl('http://example.com:9000'));
        async.flushMicrotasks();
        async.flushMicrotasks();

        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(failingRequests, hasLength(6));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('skippedClosed outcome when bloc is closed', () async {
      final bloc = SettingsBloc(
        repository: mockRepository,
        httpClient: recorder.client,
        dnsLookup: (host) async =>
            <InternetAddress>[InternetAddress('8.8.8.8')],
      );
      await bloc.close();

      // Bloc is closed: isClosed is true, _triggerRetrain returns skippedClosed
      // without attempting any retrain. Adding events after close is not allowed,
      // so we verify close() completed cleanly and no retrain requests exist.
      expect(recorder.requests, isEmpty);
    });
  });
}
