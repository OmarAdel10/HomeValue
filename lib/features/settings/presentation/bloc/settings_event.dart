import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class LoadSettings extends SettingsEvent {
  const LoadSettings();
}

class UpdateServerUrl extends SettingsEvent {
  final String serverUrl;

  const UpdateServerUrl(this.serverUrl);

  @override
  List<Object?> get props => [serverUrl];
}

class ToggleTheme extends SettingsEvent {
  final ThemeMode themeMode;

  const ToggleTheme(this.themeMode);

  @override
  List<Object?> get props => [themeMode];
}

class ToggleAutoRetrain extends SettingsEvent {
  final bool autoRetrain;

  const ToggleAutoRetrain(this.autoRetrain);

  @override
  List<Object?> get props => [autoRetrain];
}
