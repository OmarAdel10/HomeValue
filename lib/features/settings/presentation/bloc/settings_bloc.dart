import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../../core/constants.dart';
import '../../../../core/validation.dart';
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
  skippedInFlight, // already in flight, no attempt
  skippedNotDue, // retrain window not yet elapsed, no attempt
  skippedBlocked, // server URL blocked by SSRF rules, retraining fail-closed
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

  /// Bumped when auto-retrain is disabled so an in-flight retrain that is
  /// still awaiting DNS can be invalidated before it POSTs.
  int _retrainGeneration = 0;

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
  /// fail-closed resolved-IP revalidation in _trainUri; every request is sent
  /// with followRedirects=false (see _triggerRetrain) so a 3xx can never send
  /// a second request to a redirect target before the status check rejects it.
  static http.Client _createClient() {
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
      // A blocked URL leaves the retrain timer unarmed (skippedBlocked never
      // reschedules). Correcting the URL must restore scheduling while
      // preserving the existing due-window calculation.
      _syncTimer(settings.autoRetrain);
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
        // Invalidate any in-flight retrain (e.g. pending DNS) so a disabled
        // switch never lets a stale operation POST after DNS completes.
        _retrainGeneration++;
        _autoRetrainTimer?.cancel();
        _autoRetrainTimer = null;
      } else if (!wasEnabled) {
        final outcome = await _triggerRetrain();
        if (outcome == _RetrainOutcome.failed) {
          emit(
              _failure(Exception('Auto-retrain failed'), isLoadFailure: false));
        } else if (outcome == _RetrainOutcome.skippedBlocked) {
          emit(_failure(Exception('Server URL blocked by SSRF rules'),
              isLoadFailure: false));
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
            .zero // No prior retrain: initial retrain via zero-delay timer.
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
    _triggerRetrain();
  }

  Future<Uri> _trainUri(String serverUrl) async {
    // Sync validation: scheme, host, credentials, hostname allowlist.
    // (Async DNS resolve + revalidation is done below via stubbable _dnsLookup.)
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null || !uri.hasAuthority) {
      throw ArgumentError('Invalid server URL');
    }
    if (uri.host.isEmpty) {
      throw ArgumentError('Invalid server URL');
    }
    if (uri.userInfo.isNotEmpty) {
      throw ArgumentError('Invalid server URL');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw ArgumentError(
          'Unsupported scheme: $scheme (expected http or https)');
    }
    if (!isAllowedHost(uri.host)) {
      throw ArgumentError('Blocked host');
    }
    // Build the retrain URI: strip trailing slashes from server URL, append
    // the train endpoint path, then pin to the resolved IP.
    final baseUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final trainUri = Uri.parse('$baseUrl${AppConstants.trainEndpoint}');
    // Resolve hostname at request time via stubbable _dnsLookup, re-validate
    // resolved IPs to prevent DNS rebinding TOCTOU, then connect directly to
    // the first validated IP so the retrain POST cannot be re-resolved to a
    // private address at connection time. Any DNS resolution failure or
    // timeout fails closed.
    try {
      final resolved = await _dnsLookup(trainUri.host).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw ArgumentError('DNS lookup timed out'),
      );
      if (resolved.isEmpty) {
        throw ArgumentError('DNS resolution returned no addresses');
      }
      for (final address in resolved) {
        if (!isAllowedHost(address.address)) {
          throw ArgumentError('Resolved host is blocked');
        }
      }
      // Prefer IPv4 so an unreachable IPv6 address does not strand requests.
      final validated = resolved.toList()
        ..sort((a, b) {
          final aV4 = a.type == InternetAddressType.IPv4;
          final bV4 = b.type == InternetAddressType.IPv4;
          if (aV4 != bV4) return aV4 ? -1 : 1;
          return 0;
        });
      if (trainUri.scheme == 'https') {
        // Keep the original hostname so TLS SNI and certificate-name
        // verification use the domain certificate (replacing the host with an
        // IP breaks https handshakes). Resolved IPs were validated above;
        // socket-level pinning for https is tracked as a follow-up.
        return trainUri;
      }
      // http: connect directly to the first validated IP so the HTTP client
      // does not re-resolve the hostname at connect time (DNS rebinding TOCTOU).
      return trainUri.replace(host: validated.first.address);
    } on SocketException {
      // DNS failure must fail closed as ArgumentError so callers classify it
      // as skipped (not a retrain failure) — see _triggerRetrain.
      throw ArgumentError('DNS lookup failed');
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
    bool isRealAttempt = false;
    final gen = _retrainGeneration;
    Uri? uri;
    _RetrainOutcome? outcome;
    try {
      final settings = await repository.getSettings();
      _lastKnownSettings = settings;
      if (!settings.autoRetrain || !_isRetrainDue(settings)) {
        outcome = _RetrainOutcome.skippedNotDue;
        return _RetrainOutcome.skippedNotDue;
      }
      if (repository.serverUrlBlocked) {
        // Fail-closed: blocked URL never triggers retrain, does not consume
        // the retrain window clock.
        outcome = _RetrainOutcome.skippedBlocked;
        return _RetrainOutcome.skippedBlocked;
      }
      uri = await _trainUri(settings.serverUrl);
      // _trainUri above already validates serverUrlBlocked/SSRF rules via
      // validateServerUrl + resolved-IP revalidation + IP pinning. Any blocked
      // hostname throws before we reach the POST, so no separate hostname-only
      // re-check is needed here (it cannot catch domain-name rebinding).
      // Invalidate work whose enabling condition disappeared while DNS was
      // pending (user disabled auto-retrain mid-flight); the generation also
      // prevents a later re-enable from reviving stale work.
      if (_retrainGeneration != gen || !_isEnabled) {
        outcome = _RetrainOutcome.skippedNotDue;
        return _RetrainOutcome.skippedNotDue;
      }
      // Explicit request with redirects disabled: package:http follows 3xx by
      // default, which would contact a redirect target before the status
      // check below could reject it (redirect-based SSRF).
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json';
      final response = await _httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(AppConstants.apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('retrain rejected');
      }
      _lastKnownSettings = await repository.updateLastAutoRetrain(_now());
      _lastKnownSettings ??= settings;
      _consecutiveRetrainFailures = 0;
      isRealAttempt = true;
      outcome = _RetrainOutcome.performed;
      return _RetrainOutcome.performed;
    } on ArgumentError catch (e) {
      // Blocked resolved IP or DNS failure — fail-closed without consuming
      // the consecutive failure cap (SSRF block is not a retrain failure).
      log('Auto-retrain blocked: ${e.runtimeType}');
      outcome = _RetrainOutcome.skippedBlocked;
      return _RetrainOutcome.skippedBlocked;
    } catch (e) {
      log('Auto-retrain failed');
      _consecutiveRetrainFailures++;
      isRealAttempt = true;
      outcome = _RetrainOutcome.failed;
      return _RetrainOutcome.failed;
    } finally {
      _retrainInFlight = false;
      if (isRealAttempt) {
        _lastAttemptAt = _now();
      }
      // Only reschedule for real attempts (performed/failed) and normal
      // window skips (skippedNotDue). Never reschedule for skippedBlocked —
      // blocked URLs must not keep retrying every window.
      if (outcome == _RetrainOutcome.performed ||
          outcome == _RetrainOutcome.failed ||
          outcome == _RetrainOutcome.skippedNotDue) {
        if (_isEnabled &&
            _consecutiveRetrainFailures < _maxConsecutiveRetrainFailures) {
          _scheduleNextRetrain();
        }
      }
    }
  }
}
