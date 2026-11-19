import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:home_value/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:home_value/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:home_value/features/settings/domain/entities/app_settings.dart';

class MockSettingsLocalDataSource extends Mock
    implements SettingsLocalDataSource {}

void main() {
  late MockSettingsLocalDataSource dataSource;
  late SettingsRepositoryImpl repository;

  const settings = AppSettings(
    serverUrl: 'http://example.com:8000',
    themeMode: ThemeMode.system,
    autoRetrain: false,
    initialRetrainDelay: Duration.zero,
  );

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    dataSource = MockSettingsLocalDataSource();
    repository = SettingsRepositoryImpl(localDataSource: dataSource);
  });

  test('delegates updateLastAutoRetrain to the datasource', () async {
    final at = DateTime(2026, 10, 27, 9);
    when(() => dataSource.updateLastAutoRetrain(at))
        .thenAnswer((_) async => settings);

    final result = await repository.updateLastAutoRetrain(at);

    expect(result, settings);
    verify(() => dataSource.updateLastAutoRetrain(at)).called(1);
  });

  test('propagates datasource failures', () async {
    when(() => dataSource.getSettings())
        .thenThrow(Exception('disk unavailable'));

    expect(repository.getSettings(), throwsException);
  });

  test('serverUrlBlocked delegates to datasource', () async {
    when(() => dataSource.serverUrlBlocked).thenReturn(true);
    expect(repository.serverUrlBlocked, isTrue);
    verify(() => dataSource.serverUrlBlocked).called(1);

    when(() => dataSource.serverUrlBlocked).thenReturn(false);
    expect(repository.serverUrlBlocked, isFalse);
    verify(() => dataSource.serverUrlBlocked).called(1);
  });

  test('delegates updateServerUrl to the datasource', () async {
    const updated = AppSettings(
      serverUrl: 'http://example.com:9000',
      themeMode: ThemeMode.system,
      autoRetrain: false,
      initialRetrainDelay: Duration.zero,
    );
    when(() => dataSource.updateServerUrl('http://example.com:9000'))
        .thenAnswer((_) async => updated);

    final result = await repository.updateServerUrl('http://example.com:9000');

    expect(result, updated);
    verify(() => dataSource.updateServerUrl('http://example.com:9000'))
        .called(1);
  });

  test('delegates updateThemeMode to the datasource', () async {
    const updated = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.dark,
      autoRetrain: false,
      initialRetrainDelay: Duration.zero,
    );
    when(() => dataSource.updateThemeMode(ThemeMode.dark))
        .thenAnswer((_) async => updated);

    final result = await repository.updateThemeMode(ThemeMode.dark);

    expect(result, updated);
    verify(() => dataSource.updateThemeMode(ThemeMode.dark)).called(1);
  });

  test('delegates updateAutoRetrain to the datasource', () async {
    const updated = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.system,
      autoRetrain: true,
      initialRetrainDelay: Duration.zero,
    );
    when(() => dataSource.updateAutoRetrain(true))
        .thenAnswer((_) async => updated);

    final result = await repository.updateAutoRetrain(true);

    expect(result, updated);
    verify(() => dataSource.updateAutoRetrain(true)).called(1);
  });
}
