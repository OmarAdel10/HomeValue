import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_value/features/settings/data/datasources/settings_local_datasource.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsLocalDataSource dataSource;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);
  });

  test('returns defaults when nothing is stored', () async {
    final settings = await dataSource.getSettings();

    expect(settings.serverUrl, 'http://localhost:8000');
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.autoRetrain, isFalse);
    expect(settings.lastAutoRetrainAt, isNull);
  });

  test('reads a stored retrain timestamp', () async {
    final stored = DateTime(2026, 10, 27, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'last_auto_retrain_at': stored.millisecondsSinceEpoch,
    });
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);

    final settings = await dataSource.getSettings();

    expect(settings.lastAutoRetrainAt, stored);
  });

  test('persists the retrain timestamp so it survives a restart', () async {
    final stored = DateTime(2026, 10, 27, 18, 30);

    final updated = await dataSource.updateLastAutoRetrain(stored);

    expect(updated.lastAutoRetrainAt, stored);
    expect(
      prefs.getInt('last_auto_retrain_at'),
      stored.millisecondsSinceEpoch,
    );

    final reopened = SettingsLocalDataSource(prefs);
    final reloaded = await reopened.getSettings();
    expect(reloaded.lastAutoRetrainAt, stored);
  });

  test('ignores an out of range retrain timestamp', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'last_auto_retrain_at': 9223372036854775807,
    });
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);

    final settings = await dataSource.getSettings();

    expect(settings.lastAutoRetrainAt, isNull);
  });

  test('falls back to system theme for an unknown index', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'theme_mode': 99});
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);

    final settings = await dataSource.getSettings();

    expect(settings.themeMode, ThemeMode.system);
  });
}
