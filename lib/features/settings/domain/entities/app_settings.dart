import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class AppSettings extends Equatable {
  final String serverUrl;
  final ThemeMode themeMode;
  final bool autoRetrain;
  final DateTime? lastAutoRetrainAt;

  const AppSettings({
    required this.serverUrl,
    required this.themeMode,
    required this.autoRetrain,
    this.lastAutoRetrainAt,
  });

  factory AppSettings.defaults() => const AppSettings(
        serverUrl: 'http://localhost:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
      );

  AppSettings copyWith({
    String? serverUrl,
    ThemeMode? themeMode,
    bool? autoRetrain,
    DateTime? lastAutoRetrainAt,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      themeMode: themeMode ?? this.themeMode,
      autoRetrain: autoRetrain ?? this.autoRetrain,
      lastAutoRetrainAt: lastAutoRetrainAt ?? this.lastAutoRetrainAt,
    );
  }

  @override
  List<Object?> get props =>
      [serverUrl, themeMode, autoRetrain, lastAutoRetrainAt];
}
