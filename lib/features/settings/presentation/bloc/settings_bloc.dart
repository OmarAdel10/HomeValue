import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository repository;
  final Duration retrainInterval;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _now;

  Timer? _autoRetrainTimer;
  AppSettings? _lastKnownSettings;
  bool _retrainInFlight = false;

  SettingsBloc({
    required this.repository,
    http.Client? httpClient,
    this.retrainInterval = const Duration(hours: 24),
    DateTime Function()? now,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _now = now ?? DateTime.now,
        super(SettingsLoaded(AppSettings.defaults())) {
    on<LoadSettings>(_onLoadSettings);
    on<UpdateServerUrl>(_onUpdateServerUrl);
    on<ToggleTheme>(_onToggleTheme);
    on<ToggleAutoRetrain>(_onToggleAutoRetrain);
  }

  @override
  Future<void> close() {
    _autoRetrainTimer?.cancel();
    _autoRetrainTimer = null;
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
      _lastKnownSettings = settings;
      emit(SettingsLoaded(settings));
      _syncTimer(settings.autoRetrain);
    } catch (e) {
      emit(SettingsFailure(e.toString(), isLoadFailure: true));
    }
  }

  Future<void> _onUpdateServerUrl(
    UpdateServerUrl event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.updateServerUrl(event.serverUrl);
      _lastKnownSettings = settings;
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
      _lastKnownSettings = settings;
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }

  Future<void> _onToggleAutoRetrain(
    ToggleAutoRetrain event,
    Emitter<SettingsState> emit,
  ) async {
    final wasEnabled = _isEnabled;
    try {
      final settings = await repository.updateAutoRetrain(event.autoRetrain);
      _lastKnownSettings = settings;
      emit(SettingsLoaded(settings));
      if (!settings.autoRetrain) {
        _autoRetrainTimer?.cancel();
        _autoRetrainTimer = null;
      } else if (!wasEnabled) {
        unawaited(_triggerRetrain());
      }
    } catch (e) {
      emit(SettingsFailure(e.toString()));
    }
  }

  bool get _isEnabled {
    final known = _lastKnownSettings?.autoRetrain;
    if (known != null) {
      return known;
    }
    final current = state;
    return current is SettingsLoaded && current.settings.autoRetrain;
  }

  void _syncTimer(bool enabled) {
    _autoRetrainTimer?.cancel();
    _autoRetrainTimer = null;
    if (!enabled) {
      return;
    }
    _scheduleNextRetrain();
  }

  /// Arms a one-shot timer for the remaining part of the retrain window so
  /// reloading settings never restarts the 24h clock.
  void _scheduleNextRetrain() {
    final settings = _lastKnownSettings;
    if (settings == null || !settings.autoRetrain) {
      return;
    }
    final now = _now();
    final lastRun = settings.lastAutoRetrainAt;
    final nextRun = lastRun == null ? now : lastRun.add(retrainInterval);
    _armTimer(nextRun.isAfter(now) ? nextRun.difference(now) : Duration.zero);
  }

  void _armTimer(Duration delay) {
    if (isClosed) {
      return;
    }
    _autoRetrainTimer?.cancel();
    _autoRetrainTimer = Timer(delay, _onTimerFired);
  }

  void _onTimerFired() {
    if (!_isEnabled) {
      return;
    }
    unawaited(_triggerRetrain());
  }

  Uri _trainUri(String serverUrl) {
    final baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$baseUrl${AppConstants.trainEndpoint}');
  }

  Future<void> _triggerRetrain() async {
    if (_retrainInFlight) {
      return;
    }
    _retrainInFlight = true;
    var failed = false;
    Uri? uri;
    try {
      final settings = await repository.getSettings();
      _lastKnownSettings = settings;
      if (!settings.autoRetrain) {
        return;
      }
      uri = _trainUri(settings.serverUrl);
      final response =
          await _httpClient.post(uri).timeout(const Duration(minutes: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('retrain rejected', uri);
      }
      _lastKnownSettings = await repository.updateLastAutoRetrain(_now());
    } catch (e) {
      failed = true;
      // Log outcome only; never log the URL or raw exception text.
      log('Auto-retrain failed: ${e.runtimeType} ${uri?.path ?? ''}');
    } finally {
      _retrainInFlight = false;
      if (_isEnabled) {
        final recorded = _lastKnownSettings?.lastAutoRetrainAt != null;
        if (failed || !recorded) {
          _armTimer(retrainInterval);
        } else {
          _scheduleNextRetrain();
        }
      }
    }
  }
}
