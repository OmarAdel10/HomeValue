import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../../core/constants.dart';
import '../../data/datasources/settings_local_datasource.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

/// Outcome of a retrain attempt: distinguishes actual attempts from skips
/// so in-flight/closed skips are not reported as failures.
enum _RetrainOutcome {
  performed, // retrain attempt succeeded
  failed, // retrain attempt was made but failed
  skippedClosed, // bloc is closed, no attempt
  skippedInFlight, // already in flight or not due, no attempt
}

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
  int _consecutiveRetrainFailures = 0;

  final Future<List<InternetAddress>> Function(String) _dnsLookup;

  static const int _maxConsecutiveRetrainFailures = 5;

  SettingsBloc({
    required this.repository,
    http.Client? httpClient,
    this.retrainInterval = const Duration(hours: 24),
    DateTime Function()? now,
    Future<List<InternetAddress>> Function(String)? dnsLookup,
  })  : _httpClient = httpClient ?? _createClient(),
        _ownsHttpClient = httpClient == null,
        _now = now ?? DateTime.now,
        _dnsLookup = dnsLookup ?? InternetAddress.lookup,
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

  /// Creates an HTTP client for retrain requests.
  /// SSRF protection relies on validateServerUrl host allowlisting plus
  /// fail-closed resolved-IP revalidation in _trainUri; redirect responses
  /// are rejected by _triggerRetrain (3xx status codes are not followed).
  static http.Client _createClient() {
    // IOClient does not follow HTTP redirects by default; each request is a
    // single hop. 3xx responses reaching _triggerRetrain are rejected there
    // (status >= 300 throws), providing defense-in-depth against redirect-based
    // SSRF to private/metadata targets.
    return IOClient(HttpClient());
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
        final outcome = await _triggerRetrain();
        if (outcome == _RetrainOutcome.failed) {
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
    // into UI state or observability. Log the error type for diagnostics only.
    log('Settings operation failed: ${error.runtimeType}');
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
    final delay = nextRun == null
        ? Duration
            .zero // No prior retrain: retrain immediately via zero-delay timer.
        : (!nextRun.isAfter(now) ? Duration.zero : nextRun.difference(now));
    _armTimer(delay);
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
    unawaited(_handleTimerFired());
  }

  Future<void> _handleTimerFired() async {
    final outcome = await _triggerRetrain();
    if (outcome == _RetrainOutcome.failed && !isClosed) {
      // ignore: invalid_use_of_visible_for_testing_member
      emit(_failure(Exception('Scheduled auto-retrain failed')));
    }
  }

  Future<Uri> _trainUri(String serverUrl) async {
    SettingsLocalDataSource.validateServerUrl(serverUrl);
    final baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl${AppConstants.trainEndpoint}');
    // Resolve hostname at request time, re-validate resolved IPs to prevent
    // DNS rebinding TOCTOU, then connect directly to the first validated IP so
    // the retrain POST cannot be re-resolved to a private address at connection
    // time. Any DNS resolution failure or timeout fails closed.
    try {
      final resolved = await _dnsLookup(uri.host).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw ArgumentError('DNS lookup timed out'),
      );
      if (resolved.isEmpty) {
        throw ArgumentError('DNS resolution returned no addresses');
      }
      for (final address in resolved) {
        if (!SettingsLocalDataSource.isAllowedHost(address.address)) {
          throw ArgumentError('Resolved host is blocked');
        }
      }
      // Connect directly to the first validated IP so the HTTP client does not
      // re-resolve the hostname at connect time (DNS rebinding TOCTOU).
      return uri.replace(host: resolved.first.address);
    } on ArgumentError {
      // A resolved IP is blocked or DNS failed — fail closed, do not proceed.
      rethrow;
    }
  }

  Future<_RetrainOutcome> _triggerRetrain() async {
    if (isClosed) {
      return _RetrainOutcome.skippedClosed;
    }
    if (_retrainInFlight) {
      return _RetrainOutcome.skippedInFlight;
    }
    _retrainInFlight = true;
    var attemptStarted = false;
    Uri? uri;
    try {
      final settings = await repository.getSettings();
      _lastKnownSettings = settings;
      if (!settings.autoRetrain || !_isRetrainDue(settings)) {
        return _RetrainOutcome.skippedInFlight;
      }
      attemptStarted = true;
      uri = await _trainUri(settings.serverUrl);
      final response = await _httpClient.post(uri, headers: {
        'Content-Type': 'application/json'
      }).timeout(AppConstants.apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('retrain rejected', uri);
      }
      _lastKnownSettings = await repository.updateLastAutoRetrain(_now());
      _lastKnownSettings ??= settings;
      _consecutiveRetrainFailures = 0;
      return _RetrainOutcome.performed;
    } catch (e) {
      // Log outcome only; never log the URL or raw exception text.
      log('Auto-retrain failed');
      _consecutiveRetrainFailures++;
      return _RetrainOutcome.failed;
    } finally {
      _retrainInFlight = false;
      if (attemptStarted) {
        _lastAttemptAt = _now();
      }
      if (_isEnabled &&
          _consecutiveRetrainFailures < _maxConsecutiveRetrainFailures) {
        _scheduleNextRetrain();
      }
    }
  }
}
