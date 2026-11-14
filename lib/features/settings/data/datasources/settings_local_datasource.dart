import 'package:flutter/material.dart';
import '../../domain/entities/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  static const String _serverUrlKey = 'server_url';

  // Hosts/IP ranges blocked from being used as `serverUrl` (SSRF mitigation):
  // loopback, link-local, RFC 1918 private ranges, and cloud metadata.
  static final Set<String> _blockedHostPrefixes = <String>{
    '127.',
    '0.0.0.0',
    '10.',
    '172.16.',
    '172.17.',
    '172.18.',
    '172.19.',
    '172.20.',
    '172.21.',
    '172.22.',
    '172.23.',
    '172.24.',
    '172.25.',
    '172.26.',
    '172.27.',
    '172.28.',
    '172.29.',
    '172.30.',
    '172.31.',
    '192.168.',
    '169.254.',
  };

  /// Returns `true` when [host] is a public, non-private IP/host.
  static bool _isAllowedHost(String host) {
    final lower = host.toLowerCase();
    if (lower.contains(':')) {
      // IPv6: block loopback (::1) and link-local (fe80::).
      if (lower == '::1' || lower.startsWith('fe80:')) {
        return false;
      }
      return true;
    }
    return !_blockedHostPrefixes.any((prefix) => lower.startsWith(prefix));
  }

  /// Validates [serverUrl] before it is persisted: scheme must be http/https
  /// and host must not be private/link-local/metadata. Throws on invalid input.
  static void validateServerUrl(String serverUrl) {
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null || !uri.hasAuthority) {
      throw ArgumentError('Invalid server URL: $serverUrl');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw ArgumentError(
          'Unsupported scheme: $scheme (expected http or https)');
    }
    if (!_isAllowedHost(uri.host)) {
      throw ArgumentError(
          'Blocked host: ${uri.host} (private/link-local/metadata not allowed)');
    }
  }

  static const String _themeModeKey = 'theme_mode';
  static const String _autoRetrainKey = 'auto_retrain';
  static const String _lastAutoRetrainKey = 'last_auto_retrain_at';

  static const String _defaultServerUrl = 'http://localhost:8000';
  static const int _defaultThemeMode = 0; // ThemeMode.system
  static const bool _defaultAutoRetrain = false;

  final SharedPreferences _prefs;

  SettingsLocalDataSource(this._prefs);

  /// Synchronous read used by the HTTP layer before each request.
  String get serverUrl => _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;

  Future<AppSettings> getSettings() async {
    final serverUrl = _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
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
    validateServerUrl(serverUrl);
    await _prefs.setString(_serverUrlKey, serverUrl);
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
