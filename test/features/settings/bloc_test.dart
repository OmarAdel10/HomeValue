import 'dart:async';

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
      serverUrl: 'http://localhost:8000',
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
      mockRepository = MockSettingsRepository();
      settingsBloc = SettingsBloc(repository: mockRepository);
    });

    tearDown(() {
      settingsBloc.close();
    });

    const testSettings = AppSettings(
      serverUrl: 'http://localhost:8000',
      themeMode: ThemeMode.system,
      autoRetrain: false,
    );

    const updatedSettings = AppSettings(
      serverUrl: 'http://192.168.1.100:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: true,
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsLoaded] when LoadSettings succeeds',
      build: () {
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => testSettings,
        );
        return SettingsBloc(repository: mockRepository);
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
        return SettingsBloc(repository: mockRepository);
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) =>
          bloc.add(const UpdateServerUrl('http://192.168.1.100:8000')),
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
        return SettingsBloc(repository: mockRepository);
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
        return SettingsBloc(repository: mockRepository);
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
        return SettingsBloc(repository: mockRepository);
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const UpdateServerUrl('http://localhost:9000')),
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
        return SettingsBloc(repository: mockRepository);
      },
      seed: () => const SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const ToggleTheme(ThemeMode.dark)),
      expect: () => [
        isA<SettingsFailure>()
            .having((state) => state.isLoadFailure, 'isLoadFailure', false),
      ],
    );

    const enabledSettings = AppSettings(
      serverUrl: 'http://localhost:8000',
      themeMode: ThemeMode.system,
      autoRetrain: true,
    );

    const enabledDarkSettings = AppSettings(
      serverUrl: 'http://localhost:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: true,
    );

    const enabledMovedSettings = AppSettings(
      serverUrl: 'http://192.168.1.100:8000',
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
          'http://localhost:8000/train',
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
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings,
        );
        when(() => mockRepository.updateServerUrl(any())).thenAnswer(
          (_) async => enabledMovedSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          retrainInterval: const Duration(hours: 1),
        );
      },
      seed: () => const SettingsLoaded(enabledSettings),
      act: (bloc) =>
          bloc.add(const UpdateServerUrl('http://192.168.1.100:8000')),
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
      final bloc = SettingsBloc(repository: mockRepository);
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
      serverUrl: 'http://localhost:8000',
      themeMode: ThemeMode.system,
      autoRetrain: true,
    );

    const enabledDarkSettings = AppSettings(
      serverUrl: 'http://localhost:8000',
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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(hours: 22, minutes: 59));
        bloc.add(const ToggleTheme(ThemeMode.dark));
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(minutes: 1));
        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const ToggleAutoRetrain(true));
        async.flushMicrotasks();
        expect(bloc.state, isA<SettingsLoaded>());
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(hours: 23));
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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.add(const ToggleAutoRetrain(false));
        async.flushMicrotasks();
        advance(async, const Duration(hours: 48));

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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
        advance(async, const Duration(hours: 48));

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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(failingRequests, hasLength(1));

        advance(async, const Duration(hours: 1));
        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(failingRequests, hasLength(1));

        advance(async, const Duration(hours: 23));
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
            serverUrl: 'http://localhost:8000/api//',
          ),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        expect(
          recorder.requests.single.url.toString(),
          'http://localhost:8000/api/train',
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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(requests, hasLength(1));
        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));

        advance(async, const Duration(hours: 24));
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
          return http.Response('', 302);
        });
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: redirectingClient,
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(minutes: 59));
        expect(recorder.requests, isEmpty);

        advance(async, const Duration(minutes: 1));
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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        advance(async, const Duration(minutes: 30));
        expect(recorder.requests, isEmpty);

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        advance(async, const Duration(minutes: 30));

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
          retrainInterval: const Duration(hours: 24),
          now: clock,
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        gate.complete(http.Response('{"status": "ok"}', 200));
        async.flushMicrotasks();

        advance(async, const Duration(hours: 24));
        expect(requests, hasLength(2));

        bloc.close();
        async.flushMicrotasks();
      });
    });
  });
}
