import 'package:equatable/equatable.dart';
import '../../domain/entities/app_settings.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();

  @override
  List<Object?> get props => [];
}

class SettingsLoaded extends SettingsState {
  final AppSettings settings;

  const SettingsLoaded(this.settings);

  @override
  List<Object?> get props => [settings];
}

class SettingsFailure extends SettingsState {
  final String message;

  const SettingsFailure(this.message);

  @override
  List<Object?> get props => [message];
}
