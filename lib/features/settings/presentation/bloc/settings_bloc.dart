import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants.dart';
import '../../data/datasources/settings_local_datasource.dart';
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
  DateTime? _lastAttemptAt;
  bool _retrainInFlight = false;
  int _failureCount = 0;

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
      _failureCount = 0;
      emit(SettingsLoaded(settings));
      _syncTimer(settings.autoRetrain);
    } catch (e) {
      emit(_failure(e, isLoadFailure: true));
    }
  }

  Future<void> _onUpdateServerUrl(
    UpdateServerUrl event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.updateServerUrl(event.serverUrl);
      _lastKnownSettings = settings;
      _failureCount = 0;
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(_failure(e));
    }
  }

  Future<void> _onToggleTheme(
    ToggleTheme event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final settings = await repository.updateThemeMode(event.themeMode);
      _lastKnownSettings = settings;
      _failureCount = 0;
      emit(SettingsLoaded(settings));
    } catch (e) {
      emit(_failure(e));
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
      _failureCount = 0;
      emit(SettingsLoaded(settings));
      if (!settings.autoRetrain) {
        _autoRetrainTimer?.cancel();
        _autoRetrainTimer = null;
      } else if (!wasEnabled) {
        final retrained = await _triggerRetrain();
        if (!retrained) {
          emit(
              _failure(Exception('Auto-retrain failed'), isLoadFailure: false));
        }
      }
    } catch (e) {
      emit(_failure(e));
    }
  }

  SettingsFailure _failure(Object error, {bool isLoadFailure = false}) {
    _failureCount++;
    // Emit a generic, user-safe message; never leak raw URLs or exception text
    // into UI state or observability.
    return SettingsFailure(
      'Operation failed',
      isLoadFailure: isLoadFailure,
      attempt: _failureCount,
    );
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
    DateTime? nextRun;
    for (final stamp in <DateTime?>[
      settings.lastAutoRetrainAt,
      _lastAttemptAt,
    ]) {
      if (stamp == null) {
        continue;
      }
      final candidate = stamp.add(retrainInterval);
      if (nextRun == null || candidate.isAfter(nextRun)) {
        nextRun = candidate;
      }
    }
    _armTimer(
      nextRun == null || !nextRun.isAfter(now)
          ? Duration.zero
          : nextRun.difference(now),
    );
  }

  bool _isRetrainDue(AppSettings settings) {
    final now = _now();
    final lastSuccess = settings.lastAutoRetrainAt;
    final lastAttempt = _lastAttemptAt;
    final candidates =
        <DateTime?>[lastSuccess, lastAttempt].whereType<DateTime>();
    if (candidates.isEmpty) {
      return true;
    }
    final effectiveLast = candidates.reduce((a, b) => a.isAfter(b) ? a : b);
    if (now.difference(effectiveLast) < retrainInterval) {
      return false;
    }
    return true;
  }

  void _armTimer(Duration delay) {
    if (isClosed) {
      return;
    }
    _autoRetrainTimer?.cancel();
    _autoRetrainTimer = Timer(delay, _onTimerFired);
  }

  void _onTimerFired() {
    if (isClosed) {
      return;
    }
    if (!_isEnabled) {
      return;
    }
    _triggerRetrain().then((retrained) {
      if (!retrained && !isClosed) {
        log('Scheduled auto-retrain failed');
      }
    });
  }

  Uri _trainUri(String serverUrl) {
    SettingsLocalDataSource.validateServerUrl(serverUrl);
    final baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$baseUrl${AppConstants.trainEndpoint}');
  }

  Future<bool> _triggerRetrain() async {
    if (isClosed) {
      return true;
    }
    if (_retrainInFlight) {
      return true;
    }
    _retrainInFlight = true;
    var attemptStarted = false;
    Uri? uri;
    try {
      final settings = await repository.getSettings();
      _lastKnownSettings = settings;
      if (!settings.autoRetrain || !_isRetrainDue(settings)) {
        return true;
      }
      attemptStarted = true;
      uri = _trainUri(settings.serverUrl);
      final response =
          await _httpClient.post(uri).timeout(AppConstants.apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('retrain rejected', uri);
      }
      _lastKnownSettings = await repository.updateLastAutoRetrain(_now());
      return true;
    } catch (e) {
      // Log outcome only; never log the URL or raw exception text.
      log('Auto-retrain failed');
      _failureCount++;
      return false;
    } finally {
      _retrainInFlight = false;
      if (attemptStarted) {
        _lastAttemptAt = _now();
      }
      if (_isEnabled) {
        _scheduleNextRetrain();
      }
    }
  }
}
