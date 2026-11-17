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
  skippedUnavailable, // transient DNS outage — rescheduled on the normal window
}

/// DNS could not be resolved (transport failure or timeout). Distinct from a
/// policy block so a transient network outage is retried later instead of
/// silently disarming auto-retrain permanently.
class _DnsUnavailableError extends ArgumentError {
  _DnsUnavailableError(super.message);
}

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository repository;
  final Duration retrainInterval;

  /// Deadline for a single retrain POST. Defaults to 10 minutes — the
  /// pre-fix behaviour — because the backend /train endpoint runs the full
  /// training pipeline synchronously; a short prediction-class timeout here
  /// would classify every slow-but-successful retrain as a failure and
  /// suspend auto-retrain after 5 windows.
  final Duration retrainTimeout;
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
    this.retrainTimeout = const Duration(minutes: 10),
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
    on<RetrainSuspended>(_onRetrainSuspended);
  }

  @override
  Future<void> close() {
    // Invalidate any in-flight retrain (e.g. one still awaiting DNS) so it
    // can neither POST on a closed bloc nor persist afterwards.
    _retrainGeneration++;
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
      // Reload grants a fresh scheduling window: reset the consecutive
      // failure counter so a post-suspension retry starts clean instead of
      // growing the counter past the cap ('suspended after 6').
      _consecutiveRetrainFailures = 0;
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
      // A URL change invalidates any in-flight retrain that resolved DNS
      // against the old host and clears the consecutive-failure suspension
      // accumulated against the old target.
      _retrainGeneration++;
      _consecutiveRetrainFailures = 0;
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
        // Re-enabling grants a fresh failure budget: without this reset a
        // post-suspension toggle off→on resumes the counter ('suspended
        // after 6', 7, ...) instead of giving the user a clean retry.
        _consecutiveRetrainFailures = 0;
        final outcome = await _triggerRetrain();
        if (outcome == _RetrainOutcome.failed) {
          emit(
              _failure(Exception('Auto-retrain failed'), isLoadFailure: false));
        } else if (outcome == _RetrainOutcome.skippedBlocked) {
          // Pass the typed blocked error so _failure maps it to the policy
          // message (a generic Exception would downgrade it to the generic
          // failure text).
          emit(_failure(ServerUrlBlockedError('Blocked host'),
              isLoadFailure: false));
        } else if (outcome == _RetrainOutcome.skippedInFlight) {
          // A stale attempt already owns the retrain slot; if it ends
          // classified as skippedBlocked its finally-block never reschedules,
          // which would leave auto-retrain enabled with no timer. Re-arm the
          // (idempotent) schedule so the feature stays alive.
          _scheduleNextRetrain();
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
    // A persist-time SSRF rejection is user-actionable (they entered a
    // private/internal URL), so surface the policy reason without leaking
    // the URL itself. Match on the typed marker error — string-matching
    // error text drifts as validator messages evolve.
    final blocked = error is ServerUrlBlockedError;
    return SettingsFailure(
      blocked ? 'Server URL blocked by policy' : 'Operation failed',
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
        ? (settings.initialRetrainDelay ?? const Duration(minutes: 5))
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
    // Sync validation (control chars, scheme, host, credentials, hostname
    // allowlist) is shared with persist-time validateServerUrl so the
    // request-time checks cannot drift from the save-time checks. Async DNS
    // resolve + revalidation is done below via stubbable _dnsLookup.
    final baseUri = validateServerUrlSync(serverUrl);
    // Build the retrain URI: parse once, strip query/fragment and trailing
    // path slashes, then append the train endpoint path. String concatenation
    // would push the endpoint into the query string for URLs like
    // 'http://host:8000?x=1' (POST lands on '/' and the retrain silently
    // fails every window).
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    // Rebuild from components: Uri.replace(query: null) KEEPS the existing
    // query in Dart, so a saved URL like 'http://host:8000?x=1' would push
    // the request through with the foreign query attached. A fresh Uri()
    // omits query and fragment entirely.
    final trainUri = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.port == 0 ? null : baseUri.port,
      path: '$basePath${AppConstants.trainEndpoint}',
    );
    // Resolve hostname at request time via stubbable _dnsLookup, re-validate
    // resolved IPs to prevent DNS rebinding TOCTOU, then connect directly to
    // the first validated IP so the retrain POST cannot be re-resolved to a
    // private address at connection time. Any DNS resolution failure or
    // timeout fails closed.
    try {
      final resolved = await _dnsLookup(trainUri.host).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw _DnsUnavailableError('DNS lookup timed out'),
      );
      if (resolved.isEmpty) {
        throw _DnsUnavailableError('DNS resolution returned no addresses');
      }
      for (final address in resolved) {
        if (!isAllowedHost(address.address)) {
          throw ServerUrlBlockedError('Resolved host is blocked');
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
      // Zone IDs (%eth0) are stripped — Uri rejects them in the host component.
      return trainUri.replace(
        host: validated.first.address.split('%').first,
      );
    } on SocketException {
      // DNS transport failure is transient: throw the dedicated error so
      // _triggerRetrain reschedules on the normal window instead of silently
      // disarming auto-retrain (policy blocks stay ArgumentError).
      throw _DnsUnavailableError('DNS lookup failed');
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
      // _trainUri already enforced the SSRF rules via validateServerUrlSync
      // (sync allowlist) plus resolved-IP revalidation and IP pinning; the
      // earlier serverUrlBlocked gate above catches hostname-only blocks
      // before DNS. Any blocked hostname throws before we reach the POST, so
      // no separate hostname-only re-check is needed here (it cannot catch
      // domain-name rebinding).
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
          .timeout(retrainTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('retrain rejected');
      }
      _lastKnownSettings = await repository.updateLastAutoRetrain(_now());
      _consecutiveRetrainFailures = 0;
      isRealAttempt = true;
      outcome = _RetrainOutcome.performed;
      return _RetrainOutcome.performed;
    } on ArgumentError catch (e) {
      if (e is _DnsUnavailableError) {
        // Transient DNS outage: count as a real attempt and reschedule on
        // the normal retrain window. One network blip must never silently
        // and permanently disarm auto-retrain (the cap eventually surfaces
        // a visible suspension through RetrainSuspended).
        log('Auto-retrain skipped: DNS unavailable');
        _consecutiveRetrainFailures++;
        isRealAttempt = true;
        outcome = _RetrainOutcome.skippedUnavailable;
        return _RetrainOutcome.skippedUnavailable;
      }
      // Policy block (sync validation or a resolved IP allowlisted out) —
      // fail-closed without consuming the consecutive failure cap (SSRF
      // block is not a retrain failure).
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
      // Only reschedule for real attempts (performed/failed/unavailable) and
      // normal window skips (skippedNotDue). Never reschedule for
      // skippedBlocked — blocked URLs must not keep retrying every window.
      if (outcome == _RetrainOutcome.performed ||
          outcome == _RetrainOutcome.failed ||
          outcome == _RetrainOutcome.skippedUnavailable ||
          outcome == _RetrainOutcome.skippedNotDue) {
        if (_isEnabled &&
            _consecutiveRetrainFailures < _maxConsecutiveRetrainFailures) {
          _scheduleNextRetrain();
        } else if (_isEnabled &&
            (outcome == _RetrainOutcome.failed ||
                outcome == _RetrainOutcome.skippedUnavailable) &&
            _consecutiveRetrainFailures >= _maxConsecutiveRetrainFailures) {
          // Suspension must be visible: surface it through the normal event
          // pipeline instead of failing silently (fire-and-forget caller
          // cannot emit directly outside a handler). The bloc may have been
          // closed while the retrain was in flight — adding to a closed bloc
          // throws, so guard first.
          if (!isClosed) {
            add(RetrainSuspended(_consecutiveRetrainFailures));
          }
        }
      }
    }
  }

  void _onRetrainSuspended(
    RetrainSuspended event,
    Emitter<SettingsState> emit,
  ) {
    emit(
      SettingsFailure(
        'Auto-retrain suspended after ${event.consecutiveFailures} '
        'consecutive failures',
      ),
    );
  }
}
