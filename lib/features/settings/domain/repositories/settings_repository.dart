import 'package:flutter/material.dart';
import 'package:home_value/features/settings/domain/entities/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> getSettings();
  Future<AppSettings> updateServerUrl(String serverUrl);
  Future<AppSettings> updateThemeMode(ThemeMode themeMode);
  Future<AppSettings> updateAutoRetrain(bool autoRetrain);
}
