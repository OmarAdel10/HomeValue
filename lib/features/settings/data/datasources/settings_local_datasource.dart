import 'package:flutter/material.dart';
import '../../domain/entities/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  static const String _serverUrlKey = 'server_url';
  static const String _themeModeKey = 'theme_mode';
  static const String _autoRetrainKey = 'auto_retrain';

  static const String _defaultServerUrl = 'http://localhost:8000';
  static const int _defaultThemeMode = 0; // ThemeMode.system
  static const bool _defaultAutoRetrain = false;

  final SharedPreferences _prefs;

  SettingsLocalDataSource(this._prefs);

  Future<AppSettings> getSettings() async {
    final serverUrl = _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
    final themeModeIndex = _prefs.getInt(_themeModeKey) ?? _defaultThemeMode;
    final autoRetrain = _prefs.getBool(_autoRetrainKey) ?? _defaultAutoRetrain;

    final themeMode = ThemeMode.values[themeModeIndex];

    return AppSettings(
      serverUrl: serverUrl,
      themeMode: themeMode,
      autoRetrain: autoRetrain,
    );
  }

  Future<AppSettings> updateServerUrl(String serverUrl) async {
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
}
