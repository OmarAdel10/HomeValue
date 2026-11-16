import 'dart:developer';
import 'package:flutter/material.dart';
import '../../../../core/validation.dart' as validation;
import '../../domain/entities/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  static const String _serverUrlKey = 'server_url';

  /// Delegates to the shared URL validator in `lib/core/validation.dart`.
  static Future<void> validateServerUrl(String serverUrl) async =>
      validation.validateServerUrl(serverUrl);

  static const String _themeModeKey = 'theme_mode';
  static const String _autoRetrainKey = 'auto_retrain';
  static const String _lastAutoRetrainKey = 'last_auto_retrain_at';

  static const String _defaultServerUrl = 'http://example.com:8000';
  static const int _defaultThemeMode = 0; // ThemeMode.system
  static const bool _defaultAutoRetrain = false;

  final SharedPreferences _prefs;

  /// URL whose validation (including DNS resolution) already succeeded, so
  /// repeated getSettings() reads do not re-run live DNS on every call.
  /// Invalidated whenever a different URL is persisted.
  String? _lastValidatedUrl;

  SettingsLocalDataSource(this._prefs);

  /// Validates [serverUrl] unless an identical URL already passed validation.
  Future<void> _validateCached(String serverUrl) async {
    if (_lastValidatedUrl == serverUrl) {
      return;
    }
    await validateServerUrl(serverUrl);
    _lastValidatedUrl = serverUrl;
  }

  /// Synchronous read used by the HTTP layer before each request.
  String get serverUrl => _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;

  /// Whether the currently configured server URL is blocked by SSRF rules.
  /// When true, retraining must not proceed even if auto-retrain is enabled.
  /// Uses synchronous host allowlisting (no DNS resolution); domain-based
  // SSRF is caught at request time in `_trainUri` via async DNS resolve +
  // revalidation.
  bool get serverUrlBlocked {
    final serverUrl = _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
    final uri = Uri.tryParse(serverUrl);
    if (uri == null || uri.host.isEmpty) {
      return true; // malformed or empty host: fail closed
    }
    return !validation.isAllowedHost(uri.host);
  }

  Future<AppSettings> getSettings() async {
    final serverUrl = _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
    // Validate the effective URL (including defaults) at startup so a blocked
    // default cannot silently enable self-SSRF. A blocked default is tolerated
    // at load; retraining fails closed on each attempt (checked via
    // serverUrlBlocked).
    try {
      await _validateCached(serverUrl);
    } on ArgumentError {
      log('Blocked server URL at load; retraining will fail closed');
    } on Exception catch (e) {
      // DNS offline/timeout during a local read must not prevent returning
      // persisted preferences (theme/auto-retrain updates read via
      // getSettings after persisting). Request-time validation stays
      // fail-closed in the retrain/prediction flows.
      log('Server URL check unavailable at load: ${e.runtimeType}');
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
    await validateServerUrl(trimmed);
    // Validation just succeeded for this exact URL — seed the cache so the
    // follow-up getSettings() read (and future loads) skip redundant DNS.
    _lastValidatedUrl = trimmed;
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
