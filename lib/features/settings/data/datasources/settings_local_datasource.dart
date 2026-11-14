import 'dart:io';
import 'package:flutter/material.dart';
import '../../domain/entities/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  static const String _serverUrlKey = 'server_url';

  // IPv4 private/reserved ranges blocked from being used as `serverUrl`
  // (SSRF mitigation): loopback, link-local, RFC 1918, CGN, TEST-NET,
  // documentation, multicast, and reserved ranges.
  static final List<(String, int)> _blockedIpv4Cidrs = <(String, int)>[
    ('0.0.0.0', 8),
    ('10.0.0.0', 8),
    ('100.64.0.0', 10),
    ('127.0.0.0', 8),
    ('169.254.0.0', 16),
    ('172.16.0.0', 12),
    ('192.0.0.0', 24),
    ('192.0.2.0', 24),
    ('192.168.0.0', 16),
    ('198.18.0.0', 15),
    ('198.51.100.0', 24),
    ('203.0.113.0', 24),
    ('224.0.0.0', 4),
    ('240.0.0.0', 4),
  ];

  /// Returns `true` when [host] is a public, non-private IP/host.
  /// Domain names (non-IP hosts) are allowed — IP-based SSRF mitigations
  /// apply only to literal IP addresses. DNS-rebinding protection is handled
  /// separately in `_trainUri` via resolved-IP revalidation.
  static bool isAllowedHost(String host) {
    final lower = host.toLowerCase();
    // Strip IPv6 zone ID (e.g., fe80::1%eth0 -> fe80::1) to prevent bypass.
    final noZone = lower.split('%').first;

    // Block loopback hostname explicitly (not caught by IP parsing).
    if (noZone == 'localhost') {
      return false;
    }

    // Try to parse as an IP address.
    final address = InternetAddress.tryParse(noZone);
    if (address == null) {
      // Not a valid IP. If it looks like a malformed IPv4 (4 dot-separated
      // parts), block it. Otherwise treat as a domain name and allow it.
      if (noZone.split('.').length == 4) {
        return false; // Malformed IPv4: blocked
      }
      return true; // Domain name: allowed
    }

    // IPv6: normalize via InternetAddress to catch expanded notation.
    if (address.type == InternetAddressType.IPv6) {
      if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
        return false;
      }
      final bytes = address.rawAddress;
      if (bytes.length == 16 && (bytes[0] & 0xfe) == 0xfc) {
        return false; // fc00::/7 unique-local
      }
      // Defense-in-depth: block IPv4-mapped IPv6 (::ffff:a.b.c.d).
      if (noZone.startsWith('::ffff:')) {
        return false;
      }
      return true;
    }

    // IPv4: reject leading-zero octets, then check blocked CIDR ranges.
    final parts = noZone.split('.');
    if (parts.any((p) => p.length > 1 && p.startsWith('0'))) {
      return false; // leading-zero octet (octal ambiguity): blocked
    }
    if (!_ipv4InBlockedRange(noZone)) {
      return true;
    }
    return false;
  }

  /// Checks whether [ip] (IPv4 dotted-quad) falls within any blocked CIDR.
  static bool _ipv4InBlockedRange(String ip) {
    final parts = ip.split('.');
    int ipInt;
    try {
      ipInt = parts.map(int.parse).fold(0, (a, b) => (a << 8) | b);
    } on FormatException {
      return true; // Non-numeric octet: treat as blocked host
    }
    for (final cidr in _blockedIpv4Cidrs) {
      final netParts = cidr.$1.split('.').map(int.parse);
      final netInt = netParts.fold(0, (a, b) => (a << 8) | b);
      final prefix = cidr.$2;
      final mask = prefix == 0 ? 0 : (~(0xFFFFFFFF >> prefix)) & 0xFFFFFFFF;
      if ((ipInt & mask) == (netInt & mask)) {
        return true;
      }
    }
    return false;
  }

  /// Validates [serverUrl] before it is persisted: scheme must be http/https
  /// and host must not be private/link-local/metadata. Throws on invalid input.
  static void validateServerUrl(String serverUrl) {
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null || !uri.hasAuthority) {
      throw ArgumentError('Invalid server URL');
    }
    // Reject embedded credentials (userInfo) to prevent SSRF via user@host.
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
  }

  static const String _themeModeKey = 'theme_mode';
  static const String _autoRetrainKey = 'auto_retrain';
  static const String _lastAutoRetrainKey = 'last_auto_retrain_at';

  static const String _defaultServerUrl = 'http://example.com:8000';
  static const int _defaultThemeMode = 0; // ThemeMode.system
  static const bool _defaultAutoRetrain = false;

  final SharedPreferences _prefs;

  SettingsLocalDataSource(this._prefs);

  /// Synchronous read used by the HTTP layer before each request.
  String get serverUrl => _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;

  Future<AppSettings> getSettings() async {
    final serverUrl = _prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
    // Validate the effective URL (including defaults) at startup so a blocked
    // default cannot silently enable self-SSRF. A blocked default will prevent
    // retraining (rejected by _trainUri) but won't block settings load.
    try {
      validateServerUrl(serverUrl);
    } on Object {
      // Default or stored URL is blocked; retraining will be rejected by _trainUri.
    }
    final themeModeIndex = _prefs.getInt(_themeModeKey) ?? _defaultThemeMode;
    final autoRetrain = _prefs.getBool(_autoRetrainKey) ?? _defaultAutoRetrain;
    DateTime? lastAutoRetrainAt;
    final lastAutoRetrainMillis = _prefs.getInt(_lastAutoRetrainKey);
    if (lastAutoRetrainMillis != null) {
      try {
        lastAutoRetrainAt =
            DateTime.fromMillisecondsSinceEpoch(lastAutoRetrainMillis);
      } on Object {
        lastAutoRetrainAt = null;
      }
    }

    final themeMode =
        themeModeIndex >= 0 && themeModeIndex < ThemeMode.values.length
            ? ThemeMode.values[themeModeIndex]
            : ThemeMode.system;

    return AppSettings(
      serverUrl: serverUrl,
      themeMode: themeMode,
      autoRetrain: autoRetrain,
      lastAutoRetrainAt: lastAutoRetrainAt,
    );
  }

  Future<AppSettings> updateServerUrl(String serverUrl) async {
    final trimmed = serverUrl.trim();
    validateServerUrl(trimmed);
    await _prefs.setString(_serverUrlKey, trimmed);
    return getSettings();
  }

  Future<AppSettings> updateThemeMode(ThemeMode themeMode) async {
    await _prefs.setInt(_themeModeKey, themeMode.index);
    return getSettings();
  }

  Future<AppSettings> updateAutoRetrain(bool autoRetrain) async {
    await _prefs.setBool(_autoRetrainKey, autoRetrain);
    return getSettings();
  }

  Future<AppSettings> updateLastAutoRetrain(DateTime at) async {
    await _prefs.setInt(_lastAutoRetrainKey, at.millisecondsSinceEpoch);
    return getSettings();
  }
}
