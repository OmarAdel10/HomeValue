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
  });

  group('SettingsBloc auto retrain scheduling', () {
    late MockSettingsRepository mockRepository;
    late RetrainRecorder recorder;

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

    setUp(() {
      mockRepository = MockSettingsRepository();
      recorder = RetrainRecorder();
      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => enabledSettings,
      );
      when(() => mockRepository.updateThemeMode(any())).thenAnswer(
        (_) async => enabledDarkSettings,
      );
      when(() => mockRepository.updateLastAutoRetrain(any())).thenAnswer(
        (_) async => enabledSettings,
      );
    });

    tearDown(() {
      recorder.client.close();
    });

    test('keeps the 24h schedule across theme changes', () {
      fakeAsync((async) {
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          retrainInterval: const Duration(hours: 24),
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        async.elapse(const Duration(hours: 23, minutes: 59));
        bloc.add(const ToggleTheme(ThemeMode.dark));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();

        expect(recorder.requests, hasLength(2));

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
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.add(const ToggleAutoRetrain(false));
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 48));
        async.flushMicrotasks();

        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('stopping the timer on close prevents further retrains', () {
      fakeAsync((async) {
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          retrainInterval: const Duration(hours: 24),
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(recorder.requests, hasLength(1));

        bloc.close();
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 48));
        async.flushMicrotasks();

        expect(recorder.requests, hasLength(1));
      });
    });

    test('ignores a transport failure and keeps the timer alive', () {
      fakeAsync((async) {
        final failingClient = MockClient(
          (_) async => throw http.ClientException('backend down'),
        );
        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: failingClient,
          retrainInterval: const Duration(hours: 24),
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 48));
        async.flushMicrotasks();

        verifyNever(() => mockRepository.updateLastAutoRetrain(any()));
        expect(bloc.state, isA<SettingsLoaded>());

        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('skips a retrain while one is already in flight', () {
      fakeAsync((async) {
        final gate = Completer<http.Response>();
        final requests = <http.Request>[];
        final gatedClient = MockClient((request) {
          requests.add(request);
          return gate.future;
        });

        when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
          (_) async => enabledSettings,
        );

        final bloc = SettingsBloc(
          repository: mockRepository,
          httpClient: gatedClient,
          retrainInterval: const Duration(hours: 24),
        );

        bloc.add(const LoadSettings());
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        bloc.add(const ToggleAutoRetrain(false));
        async.flushMicrotasks();
        bloc.add(const ToggleAutoRetrain(true));
        async.flushMicrotasks();

        expect(requests, hasLength(1));

        gate.complete(http.Response('{"status": "ok"}', 200));
        async.flushMicrotasks();

        bloc.close();
        async.flushMicrotasks();
      });
    });
  });
}
