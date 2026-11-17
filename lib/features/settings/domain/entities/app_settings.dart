import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class AppSettings extends Equatable {
  final String serverUrl;
  final ThemeMode themeMode;
  final bool autoRetrain;
  final DateTime? lastAutoRetrainAt;
  final Duration? initialRetrainDelay;

  const AppSettings({
    required this.serverUrl,
    required this.themeMode,
    required this.autoRetrain,
    this.lastAutoRetrainAt,
    this.initialRetrainDelay,
  });

  factory AppSettings.defaults() => AppSettings(
        serverUrl: 'http://example.com:8000',
        themeMode: ThemeMode.system,
        autoRetrain: false,
        initialRetrainDelay: const Duration(minutes: 5),
      );

  AppSettings copyWith({
    String? serverUrl,
    ThemeMode? themeMode,
    bool? autoRetrain,
    DateTime? lastAutoRetrainAt,
    Duration? initialRetrainDelay,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      themeMode: themeMode ?? this.themeMode,
      autoRetrain: autoRetrain ?? this.autoRetrain,
      lastAutoRetrainAt: lastAutoRetrainAt ?? this.lastAutoRetrainAt,
      initialRetrainDelay: initialRetrainDelay ?? this.initialRetrainDelay,
    );
  }

  @override
  List<Object?> get props => [
        serverUrl,
        themeMode,
        autoRetrain,
        lastAutoRetrainAt,
        initialRetrainDelay
      ];
}
