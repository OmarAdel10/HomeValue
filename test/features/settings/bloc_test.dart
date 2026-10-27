import 'package:bloc_test/bloc_test.dart';
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
      'emits [SettingsFailure] when LoadSettings fails',
      build: () {
        when(() => mockRepository.getSettings())
            .thenThrow(Exception('disk unavailable'));
        return SettingsBloc(repository: mockRepository);
      },
      act: (bloc) => bloc.add(const LoadSettings()),
      expect: () => [
        isA<SettingsFailure>(),
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
        expect(recorder.requests.single.url.path, '/train');
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
      'does not retrain immediately when settings load with auto retrain enabled',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          retrainInterval: const Duration(hours: 1),
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
      'retrains on the periodic timer while auto retrain is enabled',
      build: () {
        recorder = RetrainRecorder();
        addTearDown(recorder.client.close);
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => enabledSettings,
        );
        return SettingsBloc(
          repository: mockRepository,
          httpClient: recorder.client,
          retrainInterval: const Duration(milliseconds: 40),
        );
      },
      act: (bloc) => bloc.add(const LoadSettings()),
      wait: const Duration(milliseconds: 120),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
      verify: (_) {
        expect(recorder.requests, isNotEmpty);
      },
    );

    test('cancels the periodic timer when auto retrain is disabled', () async {
      final recorder = RetrainRecorder();
      addTearDown(recorder.client.close);
      when(() => mockRepository.getSettings()).thenAnswer(
        (_) async => enabledSettings,
      );
      when(() => mockRepository.updateAutoRetrain(false)).thenAnswer(
        (_) async => testSettings,
      );

      final bloc = SettingsBloc(
        repository: mockRepository,
        httpClient: recorder.client,
        retrainInterval: const Duration(milliseconds: 30),
      );
      addTearDown(bloc.close);

      bloc.add(const LoadSettings());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(recorder.requests, isNotEmpty);

      bloc.add(const ToggleAutoRetrain(false));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      recorder.requests.clear();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(recorder.requests, isEmpty);
    });
  });
}
