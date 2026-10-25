import 'package:flutter/material.dart';
import 'package:home_value/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:home_value/features/settings/domain/entities/app_settings.dart';
import 'package:home_value/features/settings/domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDataSource localDataSource;

  SettingsRepositoryImpl({required this.localDataSource});

  @override
  Future<AppSettings> getSettings() async {
    return localDataSource.getSettings();
  }

  @override
  Future<AppSettings> updateServerUrl(String serverUrl) async {
    return localDataSource.updateServerUrl(serverUrl);
  }

  @override
  Future<AppSettings> updateThemeMode(ThemeMode themeMode) async {
    return localDataSource.updateThemeMode(themeMode);
  }

  @override
  Future<AppSettings> updateAutoRetrain(bool autoRetrain) async {
    return localDataSource.updateAutoRetrain(autoRetrain);
  }
}
