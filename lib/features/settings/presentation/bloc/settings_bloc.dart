import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository repository;
  final Duration retrainInterval;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Timer? _autoRetrainTimer;

  SettingsBloc({
    required this.repository,
    http.Client? httpClient,
    this.retrainInterval = const Duration(hours: 24),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        super(SettingsLoaded(AppSettings.defaults())) {
    on<LoadSettings>(_onLoadSettings);
    on<UpdateServerUrl>(_onUpdateServerUrl);
    on<ToggleTheme>(_onToggleTheme);
    on<ToggleAutoRetrain>(_onToggleAutoRetrain);
  }

  @override
  Future<void> close() {
    _autoRetrainTimer?.cancel();
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    return super.close();
  }

  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.getSettings();
      emit(SettingsLoaded(settings));
      _syncTimer(settings.autoRetrain);
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
    final currentState = state;
    final wasEnabled =
        currentState is SettingsLoaded && currentState.settings.autoRetrain;
    try {
      final settings = await repository.updateAutoRetrain(event.autoRetrain);
      emit(SettingsLoaded(settings));
      if (!settings.autoRetrain) {
        _syncTimer(false);
      } else if (!wasEnabled) {
        _syncTimer(true);
        unawaited(_triggerRetrain());
      }
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }

  void _syncTimer(bool enabled) {
    if (!enabled) {
      _autoRetrainTimer?.cancel();
      _autoRetrainTimer = null;
      return;
    }
    if (_autoRetrainTimer?.isActive ?? false) {
      return;
    }
    _autoRetrainTimer =
        Timer.periodic(retrainInterval, (_) => unawaited(_triggerRetrain()));
  }

  Future<void> _triggerRetrain() async {
    try {
      final settings = await repository.getSettings();
      final baseUrl = settings.serverUrl;
      final uri = Uri.parse('$baseUrl/train');
      await _httpClient.post(uri).timeout(const Duration(minutes: 10));
    } catch (e) {
      // Log error but don't crash the app
      log('Auto-retrain failed: $e');
    }
  }
}
