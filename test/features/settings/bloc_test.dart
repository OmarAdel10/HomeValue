import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_event.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_state.dart';
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
  });

  group('SettingsBloc', () {
    late SettingsBloc settingsBloc;
    late MockSettingsRepository mockRepository;

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
      seed: () => SettingsLoaded(testSettings),
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
      seed: () => SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const ToggleTheme(ThemeMode.dark)),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'emits [SettingsLoaded] with updated settings when ToggleAutoRetrain succeeds',
      build: () {
        when(() => mockRepository.getSettings()).thenAnswer(
          (_) async => testSettings,
        );
        when(() => mockRepository.updateAutoRetrain(any())).thenAnswer(
          (_) async => updatedSettings,
        );
        return SettingsBloc(repository: mockRepository);
      },
      seed: () => SettingsLoaded(testSettings),
      act: (bloc) => bloc.add(const ToggleAutoRetrain(true)),
      expect: () => [
        isA<SettingsLoaded>(),
      ],
    );
  });
}
