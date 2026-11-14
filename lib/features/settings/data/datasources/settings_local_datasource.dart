import 'dart:developer';
import 'package:flutter/material.dart';
import '../../../../core/validation.dart' as validation;
import '../../domain/entities/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  static const String _serverUrlKey = 'server_url';

  /// Delegates to the shared SSRF allowlist in `lib/core/validation.dart`.
  static bool isAllowedHost(String host) => validation.isAllowedHost(host);

  /// Delegates to the shared URL validator in `lib/core/validation.dart`.
  static void validateServerUrl(String serverUrl) =>
      validation.validateServerUrl(serverUrl);

  static const String _themeModeKey = 'theme_mode';
  static const String _autoRetrainKey = 'auto_retrain';
  static const String _lastAutoRetrainKey = 'last_auto_retrain_at';

  static const String _defaultServerUrl = 'http://example.com:8000';
  static const int _defaultThemeMode = 0; // ThemeMode.system
  static const bool _defaultAutoRetrain = false;

  final SharedPreferences _prefs;

  SettingsLocalDataSource(this._prefs);

  /// Synchronous read used by the HTTP layer before each request.
  String get serverUrl => _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;

  /// Whether the currently configured server URL is blocked by SSRF rules.
  /// When true, retraining must not proceed even if auto-retrain is enabled.
  bool get serverUrlBlocked {
    final serverUrl = _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
    try {
      validateServerUrl(serverUrl);
      return false;
    } on ArgumentError {
      return true;
    }
  }

  Future<AppSettings> getSettings() async {
    final serverUrl = _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
    // Validate the effective URL (including defaults) at startup so a blocked
    // default cannot silently enable self-SSRF. A blocked default is tolerated
    // at load; retraining fails closed on each attempt (checked via
    // serverUrlBlocked).
    try {
      validateServerUrl(serverUrl);
    } on ArgumentError {
      log('Blocked server URL at load; retraining will fail closed');
    }
    final themeModeIndex = _prefs.getInt(_themeModeKey) ?? _defaultThemeMode;
    final autoRetrain = _prefs.getBool(_autoRetrainKey) ?? _defaultAutoRetrain;
    DateTime? lastAutoRetrainAt;
    final lastAutoRetrainMillis = _prefs.getInt(_lastAutoRetrainKey);
    if (lastAutoRetrainMillis != null) {
      try {
        lastAutoRetrainAt =
            DateTime.fromMillisecondsSinceEpoch(lastAutoRetrainMillis);
      } on Object {
        lastAutoRetrainAt = null;
      }
    }

    final themeMode =
        themeModeIndex >= 0 && themeModeIndex < ThemeMode.values.length
            ? ThemeMode.values[themeModeIndex]
            : ThemeMode.system;

    return AppSettings(
      serverUrl: serverUrl,
      themeMode: themeMode,
      autoRetrain: autoRetrain,
      lastAutoRetrainAt: lastAutoRetrainAt,
    );
  }

  Future<AppSettings> updateServerUrl(String serverUrl) async {
    final trimmed = serverUrl.trim();
    validateServerUrl(trimmed);
    await _prefs.setString(_serverUrlKey, trimmed);
    return getSettings();
  }

  Future<AppSettings> updateThemeMode(ThemeMode themeMode) async {
    await _prefs.setInt(_themeModeKey, themeMode.index);
    return getSettings();
  }

  Future<AppSettings> updateAutoRetrain(bool autoRetrain) async {
    await _prefs.setBool(_autoRetrainKey, autoRetrain);
    return getSettings();
  }

  Future<AppSettings> updateLastAutoRetrain(DateTime at) async {
    await _prefs.setInt(_lastAutoRetrainKey, at.millisecondsSinceEpoch);
    return getSettings();
  }
}
