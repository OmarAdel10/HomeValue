import 'package:flutter/material.dart';
import '../entities/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> getSettings();
  Future<AppSettings> updateServerUrl(String serverUrl);
  Future<AppSettings> updateThemeMode(ThemeMode themeMode);
  Future<AppSettings> updateAutoRetrain(bool autoRetrain);
  Future<AppSettings> updateLastAutoRetrain(DateTime at);
}
