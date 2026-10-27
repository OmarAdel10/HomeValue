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
    serverUrl: 'http://localhost:8000',
    themeMode: ThemeMode.system,
    autoRetrain: false,
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
}
