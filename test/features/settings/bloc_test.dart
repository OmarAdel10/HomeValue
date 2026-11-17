import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:home_value/core/validation.dart' as validation;
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
      initialRetrainDelay: Duration.zero,
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
      initialRetrainDelay: Duration.zero,
    );

    const updatedSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: true,
      initialRetrainDelay: Duration.zero,
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
      initialRetrainDelay: Duration.zero,
    );

    const enabledDarkSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: true,
      initialRetrainDelay: Duration.zero,
    );

    const enabledMovedSettings = AppSettings(
      serverUrl: 'http://example.com:9000',
      themeMode: ThemeMode.system,
      autoRetrain: true,
      initialRetrainDelay: Duration.zero,
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
      'strips query and fragment from the stored server URL',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        final taintedSettings = enabledSettings.copyWith(
          serverUrl: 'http://example.com:8000?x=1#frag',
        );
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => taintedSettings,
        );
        when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
          (_) async => taintedSettings,
        );
        when(() => mockRepository.updateLastAutoRetrain(any())).thenAnswer(
          (_) async => taintedSettings,
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
        final url = recorder.requests.single.url;
        expect(url.scheme, 'http');
        expect(url.host, '8.8.8.8');
        expect(url.path, '/train');
        expect(url.hasQuery, isFalse);
        expect(url.fragment, isEmpty);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'keeps the hostname for https targets (no IP pinning)',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        final secureSettings = enabledSettings.copyWith(
          serverUrl: 'https://example.com:8000',
        );
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => secureSettings,
        );
        when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
          (_) async => secureSettings,
        );
        when(() => mockRepository.updateLastAutoRetrain(any())).thenAnswer(
          (_) async => secureSettings,
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
        final url = recorder.requests.single.url;
        expect(url.scheme, 'https');
        expect(url.host, 'example.com');
        expect(url.path, '/train');
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

    test('surfaces a persist-time blocked URL as a policy message', () async {
      when(() => mockRepository.updateServerUrl(any()))
          .thenThrow(validation.ServerUrlBlockedError('Blocked host'));
      final bloc = SettingsBloc(
        repository: mockRepository,
        dnsLookup: (host) async =>
            <InternetAddress>[InternetAddress('8.8.8.8')],
      );
      addTearDown(bloc.close);

      final seen = <SettingsState>[];
      final subscription = bloc.stream.listen(seen.add);
      addTearDown(subscription.cancel);

      bloc.add(const UpdateServerUrl('http://127.0.0.1:8000'));
      await pumpEventQueue();

      expect(seen.last, isA<SettingsFailure>());
      // The policy reason is user-actionable, but the URL itself must never
      // leak into the failure message.
      final failure = seen.last as SettingsFailure;
      expect(failure.message, 'Server URL blocked by policy');
      expect(failure.message, isNot(contains('127.0.0.1')));
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
      initialRetrainDelay: Duration.zero,
    );

    const enabledDarkSettings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: true,
      initialRetrainDelay: Duration.zero,
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

    test('a URL change during DNS resolution cancels the pending retrain', () {
      fakeAsync((async) {
        final dnsCompleter = Completer<List<InternetAddress>>();
        final overdue = current.subtract(const Duration(hours: 25));
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings.copyWith(lastAutoRetrainAt: overdue),
        );
        when(() => mockRepository.updateServerUrl(any())).thenAnswer(
          (_) async => enabledSettings.copyWith(
            serverUrl: 'http://example.com:9000',
            lastAutoRetrainAt: current.subtract(const Duration(minutes: 30)),
          ),
        );
        final raceBloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          dnsLookup: (host) => dnsCompleter.future,
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );
        addTearDown(raceBloc.close);

        raceBloc.add(const LoadSettings());
        async.flushMicrotasks();
        // Overdue window arms a zero-delay timer; DNS lookup is pending.
        advance(async, const Duration(milliseconds: 1));
        expect(recorder.requests, isEmpty);

        // Changing the URL bumps the retrain generation.
        raceBloc.add(const UpdateServerUrl('http://example.com:9000'));
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        // Completing DNS after the URL change must not fire the POST.
        dnsCompleter.complete(<InternetAddress>[InternetAddress('8.8.8.8')]);
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);
      });
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

    test('cancels an in-flight retrain when auto retrain is disabled', () {
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
      final followFlags = <bool>[];
      fakeAsync((async) {
        final requests = <http.Request>[];
        final redirectingClient = MockClient((request) async {
          requests.add(request);
          followFlags.add(request.followRedirects);
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
      // Assert after the fakeAsync body: exceptions thrown inside a MockClient
      // handler are swallowed by the catch-all error path, so the inline
      // assertion would never fail the test.
      expect(followFlags, everyElement(isFalse),
          reason: 'redirects must never be followed (SSRF)');
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
        // The typed block error maps to the policy message, not the generic
        // 'Operation failed' fallback.
        expect((bloc.state as SettingsFailure).message,
            'Server URL blocked by policy');
        expect(recorder.requests, isEmpty);

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('non-socket resolver error fails closed as a policy block', () {
      fakeAsync((async) {
        final failingRequests = <http.Request>[];
        final failingClient = MockClient((request) async {
          failingRequests.add(request);
          throw http.ClientException('backend down');
        });
        // A non-SocketException resolver error is treated as a policy block
        // (skippedBlocked), not a transient outage: no POST, no window
        // consumption, timer keeps the normal schedule.
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

    test('a success between failures resets the consecutive counter', () {
      fakeAsync((async) {
        var failNext = true;
        final requests = <http.Request>[];
        final flakyClient = MockClient((request) async {
          requests.add(request);
          if (failNext) {
            throw http.ClientException('backend down');
          }
          return http.Response('{"status": "ok"}', 200);
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: flakyClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        // 2 consecutive failures.
        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(2));

        // A success must reset the consecutive counter (suspension counts
        // consecutive, not cumulative, failures).
        failNext = false;
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(3));

        // 4 more consecutive failures — cumulative 6, but only 4 since the
        // success, so the bloc must NOT suspend yet.
        failNext = true;
        for (var i = 0; i < 4; i++) {
          advance(async, const Duration(hours: 1));
          async.flushMicrotasks();
          async.flushMicrotasks();
        }
        expect(requests, hasLength(7));
        expect(bloc.state, isA<SettingsLoaded>());

        // 5th consecutive failure reaches the cap: suspension surfaces.
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(8));
        expect(bloc.state, isA<SettingsFailure>());
        expect((bloc.state as SettingsFailure).message, contains('suspended'));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('a DNS outage reschedules instead of disarming retraining', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final okClient = MockClient((request) async {
          requests.add(request);
          return http.Response('{"status": "ok"}', 200);
        });
        var dnsDown = true;
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: okClient,
          dnsLookup: (host) async {
            if (dnsDown) {
              throw const SocketException('DNS server unreachable');
            }
            return <InternetAddress>[InternetAddress('8.8.8.8')];
          },
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        // First window: DNS outage must not POST and must not silently
        // disarm the timer (the old behaviour never rescheduled).
        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        expect(requests, isEmpty);

        // DNS recovers: the next window must fire the retrain request.
        dnsDown = false;
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('suspends visibly after 5 consecutive DNS outages', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final okClient = MockClient((request) async {
          requests.add(request);
          return http.Response('{"status": "ok"}', 200);
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: okClient,
          dnsLookup: (host) async =>
              throw const SocketException('DNS server unreachable'),
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        expect(requests, isEmpty);

        // Four more outage windows reach the cap of 5 consecutive failures.
        for (var i = 0; i < 4; i++) {
          advance(async, const Duration(hours: 1));
          async.flushMicrotasks();
          async.flushMicrotasks();
        }

        // The suspension must be visible, not a silent permanent disarm.
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsFailure>());
        final failure = bloc.state as SettingsFailure;
        expect(failure.message, contains('suspended'));
        expect(failure.isLoadFailure, isFalse);

        // After suspension the timer is disarmed: a further window is quiet.
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, isEmpty);

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('an empty DNS result counts as a transient failure', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final okClient = MockClient((request) async {
          requests.add(request);
          return http.Response('{"status": "ok"}', 200);
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: okClient,
          dnsLookup: (host) async => <InternetAddress>[],
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        // Five consecutive empty-DNS windows exhaust the cap: no POST is
        // ever made, but every window is a real attempt that counts toward
        // the suspension (transient classification, not a policy block).
        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        expect(requests, isEmpty);

        for (var i = 0; i < 4; i++) {
          advance(async, const Duration(hours: 1));
          async.flushMicrotasks();
          async.flushMicrotasks();
        }

        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsFailure>());
        expect((bloc.state as SettingsFailure).message, contains('suspended'));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('a hung DNS lookup times out and reschedules', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final okClient = MockClient((request) async {
          requests.add(request);
          return http.Response('{"status": "ok"}', 200);
        });
        final hungDns = Completer<List<InternetAddress>>();
        var dnsRecovered = false;
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: okClient,
          dnsLookup: (host) {
            if (dnsRecovered) {
              return Future<List<InternetAddress>>.value(
                  <InternetAddress>[InternetAddress('8.8.8.8')]);
            }
            return hungDns.future;
          },
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        // Elapse past the 10s DNS timeout: _trainUri fails with the
        // dedicated DNS-unavailable error and reschedules on the normal
        // window instead of disarming.
        async.elapse(const Duration(seconds: 11));
        async.flushMicrotasks();
        expect(requests, isEmpty);

        dnsRecovered = true;
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('prefers IPv4 when DNS returns both IPv6 and IPv4 addresses', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final okClient = MockClient((request) async {
          requests.add(request);
          return http.Response('{"status": "ok"}', 200);
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: okClient,
          dnsLookup: (host) async => <InternetAddress>[
            InternetAddress('2001:db8::1'),
            InternetAddress('8.8.8.8'),
          ],
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        expect(requests, hasLength(1));
        // http connects to the first validated address: IPv4 is preferred so
        // an unreachable IPv6 address cannot strand the request.
        expect(requests.first.url.host, '8.8.8.8');

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('re-enabling auto retrain after suspension grants a fresh budget', () {
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
        when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
            (invocation) async => (invocation.positionalArguments.first as bool)
                ? enabledSettings
                : enabledSettings.copyWith(autoRetrain: false));

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        expect(failingRequests, hasLength(1));

        // Burn the cap to reach suspension.
        for (var i = 0; i < 4; i++) {
          advance(async, const Duration(hours: 1));
          async.flushMicrotasks();
          async.flushMicrotasks();
        }
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsFailure>());

        // Toggle off then on: the enable path resets the counter so a retry
        // is granted even though 5 consecutive failures already happened.
        bloc.add(const ToggleAutoRetrain(false));
        async.flushMicrotasks();
        async.flushMicrotasks();
        bloc.add(const ToggleAutoRetrain(true));
        async.flushMicrotasks();
        async.flushMicrotasks();

        // The re-enable rescheduled from the last attempt; advancing one
        // window must fire the retry (request 6).
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(failingRequests, hasLength(6));
        // The timer-path failure does not re-emit a suspension state.
        expect(bloc.state, isA<SettingsLoaded>());

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('a retrain completing after close() does not throw', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final gate = Completer<http.Response>();
        final gatedClient = MockClient((request) async {
          requests.add(request);
          return gate.future;
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: gatedClient,
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
        // The zero-delay initial retrain is in flight, parked on the gated
        // client.
        expect(requests, hasLength(1));

        // Close while the retrain response is still pending.
        bloc.close();
        async.flushMicrotasks();

        // The response completes after close(): the finally block must not
        // reschedule a timer on the closed bloc and the completion must not
        // throw (a StateError here would fail the test).
        gate.complete(http.Response('{"status": "ok"}', 200));
        async.flushMicrotasks();
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        expect(requests, hasLength(1));
      });
    });

    test('toggle on fires an overdue retrain and surfaces its failure', () {
      fakeAsync((async) {
        final failingRequests = <http.Request>[];
        final failingClient = MockClient((request) async {
          failingRequests.add(request);
          throw http.ClientException('backend down');
        });
        when(() => mockRepository.updateAutoRetrain(true)).thenAnswer(
          (_) async => enabledSettings.copyWith(autoRetrain: true),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: failingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        bloc.add(const ToggleAutoRetrain(true));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        // The toggle path awaits the retrain: a failed attempt must surface
        // as a (non-load) failure instead of failing silently.
        expect(bloc.state, isA<SettingsFailure>());
        final failure = bloc.state as SettingsFailure;
        expect(failure.isLoadFailure, isFalse);
        expect(failure.message, 'Operation failed');
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));
        expect(failingRequests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('retrain timeout defaults to ten minutes, not the API timeout', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final gate = Completer<http.Response>();
        final gatedClient = MockClient((request) async {
          requests.add(request);
          return gate.future;
        });
        when(() => mockRepository.updateAutoRetrain(true)).thenAnswer(
          (_) async => enabledSettings.copyWith(autoRetrain: true),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: gatedClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        bloc.add(const ToggleAutoRetrain(true));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        // The retrain POST is in flight, parked on the gated client.
        expect(requests, hasLength(1));
        expect(bloc.state, isA<SettingsLoaded>());

        // 31s must NOT time out: the retrain timeout is not the 30s API
        // timeout (that regression would suspend retraining on every slow
        // backend /train run).
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsLoaded>());

        // At the 10-minute default the attempt times out and the toggle path
        // surfaces the failure.
        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsFailure>());
        expect((bloc.state as SettingsFailure).isLoadFailure, isFalse);

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('LoadSettings grants a fresh failure budget after suspension', () {
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

        // Burn the cap to reach suspension.
        for (var i = 0; i < 4; i++) {
          advance(async, const Duration(hours: 1));
          async.flushMicrotasks();
          async.flushMicrotasks();
        }
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsFailure>());
        expect((bloc.state as SettingsFailure).message, contains('suspended'));

        // A reload resets the consecutive-failure counter: the next failure
        // is attempt 1 again, not an immediate re-suspension.
        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsLoaded>());

        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(failingRequests, hasLength(6));
        // Attempt 6 failed on the timer path, which emits no state: still
        // the SettingsLoaded from the reload. A stale counter would have
        // re-suspended here instead.
        expect(bloc.state, isA<SettingsLoaded>());

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('correcting a blocked URL re-arms retraining', () {
      fakeAsync((async) {
        when(() => mockRepository.serverUrlBlocked).thenReturn(true);
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
        for (var i = 0; i < 6; i++) {
          async.flushMicrotasks();
        }

        // Blocked URL: no POST, and skippedBlocked leaves no timer behind.
        expect(recorder.requests, isEmpty);
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));

        // Correcting the URL must restore scheduling.
        when(() => mockRepository.serverUrlBlocked).thenReturn(false);
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async =>
              enabledSettings.copyWith(serverUrl: 'http://example.com:9000'),
        );
        when(() => mockRepository.updateServerUrl(any())).thenAnswer(
          (invocation) async => enabledSettings.copyWith(
            serverUrl: invocation.positionalArguments.first as String,
          ),
        );
        bloc.add(const UpdateServerUrl('http://example.com:9000'));
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        // The re-armed schedule is overdue (no successful attempt yet), so
        // the next elapsed window fires the retrain against the new URL.
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 6; i++) {
          async.flushMicrotasks();
        }
        expect(recorder.requests, hasLength(1));
        // HTTP bases pin to the resolved IP (8.8.8.8 from DNS stub).
        expect(recorder.requests.first.url.host, '8.8.8.8');
        expect(recorder.requests.first.url.port, 9000);

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('bloc close never closes an injected client', () {
      fakeAsync((async) {
        final trackingClient = _CloseTrackingClient();
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: trackingClient,
          dnsLookup: (host) async =>
              <InternetAddress>[InternetAddress('8.8.8.8')],
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 6; i++) {
          async.flushMicrotasks();
        }
        // The injected client was used for the retrain and it succeeded.
        expect(trackingClient.sentRequests, hasLength(1));
        verify(() => mockRepository.updateLastAutoRetrain(any())).called(1);

        bloc.close();
        async.flushMicrotasks();

        // The bloc must not dispose a client it does not own.
        expect(trackingClient.closeCount, 0);
        trackingClient.close();
      });
    });

    test('a retrain pending on DNS cannot POST after close', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final okClient = MockClient((request) async {
          requests.add(request);
          return http.Response('{"status": "ok"}', 200);
        });
        final dnsCompleter = Completer<List<InternetAddress>>();
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: okClient,
          dnsLookup: (host) => dnsCompleter.future,
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        // DNS lookup is pending; no POST yet.
        expect(requests, isEmpty);

        // Close while DNS is in flight: the generation bump must invalidate
        // the pending attempt so it can never reach the POST or persist a
        // success timestamp for a closed bloc.
        bloc.close();
        async.flushMicrotasks();

        dnsCompleter.complete(<InternetAddress>[InternetAddress('8.8.8.8')]);
        for (var i = 0; i < 8; i++) {
          async.flushMicrotasks();
        }
        expect(requests, isEmpty);
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));
      });
    });

    test('re-enabling during a DNS outage emits only SettingsLoaded', () {
      fakeAsync((async) {
        final requests = <http.Request>[];
        final okClient = MockClient((request) async {
          requests.add(request);
          return http.Response('{"status": "ok"}', 200);
        });
        var dnsDown = true;
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: okClient,
          dnsLookup: (host) async {
            if (dnsDown) {
              throw const SocketException('DNS server unreachable');
            }
            return <InternetAddress>[InternetAddress('8.8.8.8')];
          },
          retrainInterval: const Duration(hours: 1),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }
        // Initial attempt hits the outage: counted, rescheduled, no POST.
        expect(requests, isEmpty);
        expect(bloc.state, isA<SettingsLoaded>());

        // Toggle off, let the window lapse, then re-enable while the outage
        // persists: the enable path must not surface a failure and must keep
        // the schedule armed.
        when(() => mockRepository.updateAutoRetrain(false)).thenAnswer(
          (_) async => enabledSettings.copyWith(autoRetrain: false),
        );
        when(() => mockRepository.updateAutoRetrain(true)).thenAnswer(
          (_) async => enabledSettings.copyWith(autoRetrain: true),
        );
        bloc.add(const ToggleAutoRetrain(false));
        async.flushMicrotasks();
        async.flushMicrotasks();
        advance(async, const Duration(hours: 1));
        bloc.add(const ToggleAutoRetrain(true));
        for (var i = 0; i < 5; i++) {
          async.flushMicrotasks();
        }

        // No failure surfaced by the enable path during the outage.
        expect(bloc.state, isA<SettingsLoaded>());
        expect(bloc.state, isNot(isA<SettingsFailure>()));

        // DNS recovers: the next window fires the retrain.
        dnsDown = false;
        advance(async, const Duration(hours: 1));
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });
  });
}

class _CloseTrackingClient extends http.BaseClient {
  final List<http.BaseRequest> sentRequests = <http.BaseRequest>[];
  int closeCount = 0;

  late final http.Client _inner = MockClient((request) async {
    return http.Response('{"status": "ok"}', 200);
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sentRequests.add(request);
    return _inner.send(request);
  }

  @override
  void close() {
    closeCount++;
  }
}
