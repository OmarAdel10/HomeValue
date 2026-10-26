import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository repository;

  Timer? _autoRetrainTimer;
  static const _retrainInterval = Duration(hours: 24);

  SettingsBloc({required this.repository})
      : super(SettingsLoaded(AppSettings.defaults())) {
    on<LoadSettings>(_onLoadSettings);
    on<UpdateServerUrl>(_onUpdateServerUrl);
    on<ToggleTheme>(_onToggleTheme);
    on<ToggleAutoRetrain>(_onToggleAutoRetrain);
  }

  @override
  Future<void> close() {
    _autoRetrainTimer?.cancel();
    return super.close();
  }

  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.getSettings();
      emit(SettingsLoaded(settings));
      _maybeStartAutoRetrain(settings);
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
      _maybeStartAutoRetrain(settings);
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
      _maybeStartAutoRetrain(settings);
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
      _maybeStartAutoRetrain(settings);
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }

  void _maybeStartAutoRetrain(AppSettings settings) {
    _autoRetrainTimer?.cancel();
    if (settings.autoRetrain) {
      _autoRetrainTimer =
          Timer.periodic(_retrainInterval, (_) => _triggerRetrain());
      // Also trigger immediately on enable
      _triggerRetrain();
    }
  }

  Future<void> _triggerRetrain() async {
    try {
      final settings = await repository.getSettings();
      final baseUrl = settings.serverUrl;
      final uri = Uri.parse('$baseUrl/train');
      await http.post(uri).timeout(const Duration(minutes: 10));
    } catch (e) {
      // Log error but don't crash the app
      print('Auto-retrain failed: $e');
    }
  }
}
