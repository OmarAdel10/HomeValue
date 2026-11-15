/// Shared host-allowlist and URL validation for SSRF mitigation.
///
/// Used by the settings datasource, prediction/comparison remote
/// datasources, and the settings BLoC. Keeping this in `core` avoids pulling
/// `flutter/material.dart` + `dart:io` into prediction/comparison data layers.
library;

import 'dart:io';

import 'package:http/http.dart' as http;

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
  ('192.88.99.0', 24), // 6to4 relay anycast
  ('198.18.0.0', 15),
  ('198.51.100.0', 24),
  ('203.0.113.0', 24),
  ('224.0.0.0', 4),
  ('240.0.0.0', 4),
];

/// Injectable DNS resolver for [validateServerUrl]. Defaults to
/// [InternetAddress.lookup] in production; tests can stub this to avoid
/// live network/DNS calls.
Future<List<InternetAddress>> Function(String host) dnsLookup =
    InternetAddress.lookup;

/// Returns `true` when [host] is a public, non-private IP/host.
/// Domain names (non-IP hosts) are allowed — IP-based SSRF mitigations
/// apply only to literal IP addresses. DNS-rebinding protection is handled
/// separately via resolved-IP revalidation.
bool isAllowedHost(String host) {
  // Reject empty host.
  if (host.isEmpty) return false;
  // Reject hosts containing whitespace or control characters.
  if (host.contains(RegExp(r'[\s\x00-\x1F\x7F]'))) return false;

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
    // parts), block it. Block alternative IPv4 notations (bare integer like
    // 2130706433, or hex like 0x7f000001) that bypass strict dotted-decimal
    // parsing. Otherwise treat as a domain name and allow it.
    // Only classify 4-part input as malformed IPv4 when it is numeric
    // address-shaped (e.g. 999.1.1.1). Valid multi-label DNS names such as
    // api.prod.example.com must proceed to DNS validation.
    final parts = stripped.split('.');
    if (parts.length == 4 &&
        parts.every((p) => RegExp(r'^\d{1,3}$').hasMatch(p))) {
      return false; // Malformed numeric IPv4: blocked
    }
    if (RegExp(r'^\d+$').hasMatch(stripped) ||
        RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(stripped)) {
      return false; // Alternative IPv4 notation: blocked
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
      return false; // IPv4-compatible IPv6 ::a.b.c.d (incl ::127.0.0.1)
    }
    // Defense-in-depth: explicit IPv4-mapped IPv6 ::ffff:a.b.c.d check
    // (already covered by ::a.b.c.d rule above, but made explicit for clarity).
    if (bytes.length == 16 &&
        bytes[0] == 0 &&
        bytes[1] == 0 &&
        bytes[2] == 0 &&
        bytes[3] == 0 &&
        bytes[4] == 0 &&
        bytes[5] == 0 &&
        bytes[6] == 0xff &&
        bytes[7] == 0xff) {
      return false;
    }
    // Block IPv6 transition forms embedding a blocked IPv4: 6to4
    // (2002::/16, embedded IPv4 in bytes 8-11) and RFC 6052
    // (64:ff9b::/96, embedded IPv4 in bytes 12-15). Documentation range
    // 2001:db8::/32 is not a transition form and is allowed.
    if (bytes.length == 16) {
      final is6to4 = bytes[0] == 0x20 && bytes[1] == 0x02;
      final isRfc6052 =
          bytes[1] == 0x64 && bytes[2] == 0xff && bytes[3] == 0x9b;
      if (is6to4 || isRfc6052) {
        String embedded;
        if (is6to4) {
          // 6to4: 2002:IPv4::/48, embedded IPv4 in bytes 2-5.
          embedded = '${bytes[2]}.${bytes[3]}.${bytes[4]}.${bytes[5]}';
        } else {
          // RFC 6052: 64:ff9b::/96, embedded IPv4 in bytes 12-15.
          embedded = '${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}';
        }
        if (_ipv4InBlockedRange(embedded)) {
          return false;
        }
      }
    }
    return true;
  }

  // IPv4: enforce strict dotted-decimal notation (4 octets, 0-255 each,
  // no leading zeros, no hex/integer notation) to block alternative IPv4
  // notations that bypass CIDR matching (e.g. 2130706433, 0x7f000001).
  final parts = stripped.split('.');
  if (parts.length != 4) {
    return false; // Not strict dotted-decimal IPv4
  }
  for (final p in parts) {
    if (p.isEmpty ||
        p.length > 1 && p.startsWith('0') ||
        !RegExp(r'^\d+$').hasMatch(p) ||
        int.tryParse(p)! > 255) {
      return false; // Non-strict octet: blocked
    }
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
    // /0 would match every IPv4 address — treat as match-nothing so no
    // future /0 entry can open a fail-open SSRF path.
    if (prefix == 0) {
      continue;
    }
    final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    if ((ipInt & mask) == (netInt & mask)) {
      return true;
    }
  }
  return false;
}

/// Validates [serverUrl] before it is persisted: scheme must be http/https
/// and host must not be private/link-local/metadata. Domain names are
/// resolved and every resolved IP is re-validated to prevent domain-based
/// SSRF (e.g. metadata.google.internal resolving to 169.254.169.254).
/// Throws on invalid input. Fail-closed: any DNS failure throws.
Future<void> validateServerUrl(String serverUrl) async {
  // Reject raw input containing whitespace or control characters before
  // parsing, since Uri.tryParse may normalize or drop them.
  if (serverUrl.contains(RegExp(r'[\s\x00-\x1F\x7F]'))) {
    throw ArgumentError('Invalid server URL');
  }
  final uri = Uri.tryParse(serverUrl.trim());
  if (uri == null || !uri.hasAuthority) {
    throw ArgumentError('Invalid server URL');
  }
  // Reject empty host (e.g. http://:8000/).
  if (uri.host.isEmpty) {
    throw ArgumentError('Invalid server URL');
  }
  // Reject hosts containing whitespace or control characters.
  if (uri.host.contains(RegExp(r'[\s\x00-\x1F\x7F]'))) {
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
  // Resolve+revalidate domain names at persist time to prevent domain-based
  // SSRF (e.g. metadata.google.internal resolving to 169.254.169.254).
  // Literal IPs are already validated by isAllowedHost above.
  final address = InternetAddress.tryParse(uri.host);
  if (address == null) {
    // Domain name — resolve and validate all resolved IPs.
    try {
      final resolved = await dnsLookup(uri.host).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw ArgumentError('DNS lookup timed out'),
      );
      if (resolved.isEmpty) {
        throw ArgumentError('DNS resolution returned no addresses');
      }
      for (final ip in resolved) {
        if (!isAllowedHost(ip.address)) {
          throw ArgumentError('Resolved host is blocked');
        }
      }
    } on ArgumentError {
      rethrow;
    }
  }
}

/// Asserts that [url]'s host is allowed (not private/link-local/metadata).
/// Throws ArgumentError if blocked — fail-closed for SSRF mitigation.
void assertAllowedHost(String url) {
  // Trim before parsing to avoid whitespace/control-char edge cases.
  url = url.trim();
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority) {
    throw ArgumentError('Invalid URL');
  }
  // Reject empty host (e.g. http://:8000/path).
  if (uri.host.isEmpty) {
    throw ArgumentError('Invalid URL');
  }
  // Reject hosts containing whitespace or control characters.
  if (uri.host.contains(RegExp(r'[\s\x00-\x1F\x7F]'))) {
    throw ArgumentError('Invalid URL');
  }
  // Reject embedded credentials (userInfo) to prevent SSRF via user@host.
  if (uri.userInfo.isNotEmpty) {
    throw ArgumentError('Invalid URL');
  }
  if (!isAllowedHost(uri.host)) {
    throw ArgumentError('Blocked host: SSRF protection');
  }
}

/// Rejects a redirect response to prevent redirect-based SSRF.
/// Throws [http.ClientException] for 3xx status codes.
/// The exception message never embeds the URL (no SSRF target leakage).
void rejectRedirect(http.Response response) {
  if (response.statusCode >= 300 && response.statusCode < 400) {
    throw http.ClientException('Redirect not followed: SSRF protection');
  }
}
