import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository repository;

  SettingsBloc({required this.repository})
      : super(SettingsLoaded(AppSettings.defaults())) {
    on<LoadSettings>(_onLoadSettings);
    on<UpdateServerUrl>(_onUpdateServerUrl);
    on<ToggleTheme>(_onToggleTheme);
    on<ToggleAutoRetrain>(_onToggleAutoRetrain);
  }

  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.getSettings();
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }

  Future<void> _onUpdateServerUrl(
    UpdateServerUrl event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.updateServerUrl(event.serverUrl);
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }

  Future<void> _onToggleTheme(
    ToggleTheme event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.updateThemeMode(event.themeMode);
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }

  Future<void> _onToggleAutoRetrain(
    ToggleAutoRetrain event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.updateAutoRetrain(event.autoRetrain);
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }
}
