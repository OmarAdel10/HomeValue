import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_value/features/settings/domain/entities/app_settings.dart';

void main() {
  group('AppSettings', () {
    const settings = AppSettings(
      serverUrl: 'http://example.com:8000',
      themeMode: ThemeMode.system,
      autoRetrain: false,
    );

    test('defaults uses example.com public URL', () {
      expect(AppSettings.defaults().serverUrl, 'http://example.com:8000');
      expect(AppSettings.defaults().themeMode, ThemeMode.system);
      expect(AppSettings.defaults().autoRetrain, isFalse);
      expect(AppSettings.defaults().lastAutoRetrainAt, isNull);
    });

    test('copyWith with no changes returns equal settings', () {
      expect(settings.copyWith(), settings);
    });

    test('copyWith serverUrl', () {
      final updated = settings.copyWith(serverUrl: 'http://8.8.8.8:8000');
      expect(updated.serverUrl, 'http://8.8.8.8:8000');
      expect(updated.themeMode, settings.themeMode);
      expect(updated.autoRetrain, settings.autoRetrain);
      expect(updated.lastAutoRetrainAt, settings.lastAutoRetrainAt);
    });

    test('copyWith themeMode', () {
      final updated = settings.copyWith(themeMode: ThemeMode.dark);
      expect(updated.themeMode, ThemeMode.dark);
      expect(updated.serverUrl, settings.serverUrl);
      expect(updated.autoRetrain, settings.autoRetrain);
    });

    test('copyWith autoRetrain', () {
      final updated = settings.copyWith(autoRetrain: true);
      expect(updated.autoRetrain, isTrue);
      expect(updated.serverUrl, settings.serverUrl);
      expect(updated.themeMode, settings.themeMode);
    });

    test('copyWith lastAutoRetrainAt', () {
      final at = DateTime(2026, 10, 27, 12);
      final updated = settings.copyWith(lastAutoRetrainAt: at);
      expect(updated.lastAutoRetrainAt, at);
      expect(updated.serverUrl, settings.serverUrl);
    });

    test('copyWith null lastAutoRetrainAt keeps current value (?? fallback)',
        () {
      final withTime = settings.copyWith(lastAutoRetrainAt: DateTime(2026));
      final cleared = withTime.copyWith(lastAutoRetrainAt: null);
      // copyWith uses `?? this.lastAutoRetrainAt`, so null keeps current value.
      expect(cleared.lastAutoRetrainAt, withTime.lastAutoRetrainAt);
    });

    test('props equality reflects all fields', () {
      final same = const AppSettings(
        serverUrl: 'http://example.com:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );
      expect(same.props, settings.props);
      expect(same, settings);

      final different = settings.copyWith(autoRetrain: true);
      expect(different.props, isNot(settings.props));
      expect(different, isNot(settings));
    });

    test('props includes lastAutoRetrainAt when set', () {
      final withTime = settings.copyWith(lastAutoRetrainAt: DateTime(2026));
      expect(withTime.props.length, 4);
      expect(withTime.props.last, DateTime(2026));
    });
  });
}
