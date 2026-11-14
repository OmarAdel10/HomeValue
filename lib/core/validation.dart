/// Shared host-allowlist and URL validation for SSRF mitigation.
///
/// Used by the settings datasource, prediction/comparison remote
/// datasources, and the settings BLoC. Keeping this in `core` avoids pulling
/// `flutter/material.dart` + `dart:io` into prediction/comparison data layers.
library;

import 'dart:io';

/// IPv4 private/reserved ranges blocked from being used as a server URL
/// (SSRF mitigation): loopback, link-local, RFC 1918, CGN, TEST-NET,
/// documentation, multicast, and reserved ranges.
final List<(String, int)> blockedIpv4Cidrs = <(String, int)>[
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
/// separately via resolved-IP revalidation.
bool isAllowedHost(String host) {
  final lower = host.toLowerCase();
  // Strip IPv6 zone ID (e.g., fe80::1%eth0 -> fe80::1) to prevent bypass.
  final noZone = lower.split('%').first;
  // Strip trailing dot (e.g., localhost. -> localhost) to prevent bypass.
  final stripped =
      noZone.endsWith('.') ? noZone.substring(0, noZone.length - 1) : noZone;

  // Block loopback hostname explicitly (not caught by IP parsing).
  if (stripped == 'localhost' || stripped.endsWith('.localhost')) {
    return false;
  }

  // Try to parse as an IP address.
  final address = InternetAddress.tryParse(stripped);
  if (address == null) {
    // Not a valid IP. If it looks like a malformed IPv4 (4 dot-separated
    // parts), block it. Otherwise treat as a domain name and allow it.
    if (stripped.split('.').length == 4) {
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
    // Block ALL IPv4-compatible IPv6 (::a.b.c.d, including ::127.0.0.1)
    // regardless of the embedded IPv4 address (RFC 4291 deprecated format).
    if (bytes.length == 16 &&
        bytes[0] == 0 &&
        bytes[1] == 0 &&
        bytes[2] == 0 &&
        bytes[3] == 0 &&
        bytes[4] == 0 &&
        bytes[5] == 0 &&
        bytes[6] == 0 &&
        bytes[7] == 0 &&
        bytes[8] == 0 &&
        bytes[9] == 0) {
      return false;
    }
    return true;
  }

  // IPv4: reject leading-zero octets, then check blocked CIDR ranges.
  final parts = stripped.split('.');
  if (parts.any((p) => p.length > 1 && p.startsWith('0'))) {
    return false; // leading-zero octet (octal ambiguity): blocked
  }
  if (!_ipv4InBlockedRange(stripped)) {
    return true;
  }
  return false;
}

/// Checks whether [ip] (IPv4 dotted-quad) falls within any blocked CIDR.
bool _ipv4InBlockedRange(String ip) {
  final parts = ip.split('.');
  int ipInt;
  try {
    ipInt = parts.map(int.parse).fold(0, (a, b) => (a << 8) | b);
  } on FormatException {
    return true; // Non-numeric octet: treat as blocked host
  }
  for (final cidr in blockedIpv4Cidrs) {
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
void validateServerUrl(String serverUrl) {
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
    throw ArgumentError('Unsupported scheme: $scheme (expected http or https)');
  }
  if (!isAllowedHost(uri.host)) {
    throw ArgumentError('Blocked host');
  }
}
