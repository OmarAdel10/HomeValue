import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:home_value/core/validation.dart';

void main() {
  setUp(() {
    dnsLookup = (host) async => <InternetAddress>[InternetAddress('8.8.8.8')];
  });

  tearDown(() {
    dnsLookup = InternetAddress.lookup;
  });
  group('isAllowedHost', () {
    test('allows public domain', () {
      expect(isAllowedHost('example.com'), isTrue);
      expect(isAllowedHost('api.example.com'), isTrue);
      // Regression: 4-label DNS names are not malformed IPv4.
      expect(isAllowedHost('api.prod.example.com'), isTrue);
    });

    test('blocks malformed numeric IPv4 with 4 parts', () {
      expect(isAllowedHost('999.1.1.1'), isFalse);
      expect(isAllowedHost('300.1.1.1'), isFalse);
    });

    test('allows public IPv4', () {
      expect(isAllowedHost('8.8.8.8'), isTrue);
      expect(isAllowedHost('1.1.1.1'), isTrue);
    });

    test('allows public IPv6 documentation range', () {
      expect(isAllowedHost('2001:db8::1'), isTrue);
    });

    test('blocks loopback IPv4', () {
      expect(isAllowedHost('127.0.0.1'), isFalse);
      expect(isAllowedHost('localhost'), isFalse);
      expect(isAllowedHost('localhost.'), isFalse);
    });

    test('blocks RFC 1918 private ranges', () {
      expect(isAllowedHost('10.0.0.1'), isFalse);
      expect(isAllowedHost('10.255.255.255'), isFalse);
      expect(isAllowedHost('172.16.0.1'), isFalse);
      expect(isAllowedHost('172.31.255.255'), isFalse);
      expect(isAllowedHost('192.168.1.1'), isFalse);
      expect(isAllowedHost('192.168.255.255'), isFalse);
    });

    test('blocks link-local and metadata', () {
      expect(isAllowedHost('169.254.169.254'), isFalse);
      expect(isAllowedHost('169.254.0.1'), isFalse);
    });

    test('blocks 0.0.0.0/8', () {
      expect(isAllowedHost('0.0.0.0'), isFalse);
      expect(isAllowedHost('0.0.0.1'), isFalse);
    });

    test('blocks IPv6 loopback and link-local', () {
      expect(isAllowedHost('::1'), isFalse);
      expect(isAllowedHost('fe80::1'), isFalse);
    });

    test('blocks IPv4-mapped IPv6 ::ffff:127.0.0.1', () {
      expect(isAllowedHost('::ffff:127.0.0.1'), isFalse);
    });

    test('blocks SIIT ::ffff:0:127.0.0.1', () {
      // SIIT pool 0:ffff:0:0/96 embedding loopback
      expect(isAllowedHost('::ffff:0:127.0.0.1'), isFalse);
      // SIIT embedding RFC 1918
      expect(isAllowedHost('::ffff:0:10.0.0.1'), isFalse);
    });

    test('blocks ISATAP embedding private IPv4', () {
      // ISATAP ::0200:5e10:ac10:01 embeds 172.16.0.1? No —
      // ::0200:5efe:ac10:0001 embeds 172.16.0.0:1; use canonical form
      // ::0200:5efe:ac10:0001 = marker 0200:5efe + 172.16.0.1
      expect(isAllowedHost('::0200:5efe:ac10:1'), isFalse);
    });

    test('blocks deprecated site-local fec0::/10', () {
      // /10 = bytes[0]==0xfe && bytes[1] high 2 bits == 11 (0xc0-0xff).
      expect(isAllowedHost('fec0::1'), isFalse);
      expect(isAllowedHost('fedf::1'), isFalse);
      expect(isAllowedHost('feff::1'), isFalse);
    });

    test('blocks full link-local fe80::/10 range', () {
      // RFC 4291 link-local spans fe80-febf (high 2 bits = 10). The SDK
      // isLinkLocal getter only covers fe8x, so the allowlist must check
      // the range explicitly.
      expect(isAllowedHost('fe80::1'), isFalse);
      expect(isAllowedHost('fe90::1'), isFalse);
      expect(isAllowedHost('fea0::1'), isFalse);
      expect(isAllowedHost('febf::1'), isFalse);
    });

    test('blocks subdomains of localhost', () {
      expect(isAllowedHost('sub.localhost'), isFalse);
      expect(isAllowedHost('api.prod.localhost'), isFalse);
    });

    test('strips ALL trailing dots before the localhost check', () {
      // A single trailing dot was already handled; multiple dots must not
      // let 'localhost..' fall through as a domain.
      expect(isAllowedHost('localhost..'), isFalse);
      expect(isAllowedHost('localhost...'), isFalse);
      expect(isAllowedHost('sub.localhost.'), isFalse);
      expect(isAllowedHost('...'), isFalse);
      // A fully-qualified public domain keeps working.
      expect(isAllowedHost('api.prod.example.com.'), isTrue);
      expect(isAllowedHost('api.prod.example.com'), isTrue);
    });

    test('blocks non-dotted-quad all-numeric hosts (octal shorthand)', () {
      // '0177.0.0.1' parses as 127.0.0.1 in C-style octal interpretation;
      // overlong octets ('1234') are not dotted-quad IPv4. Both must be
      // blocked rather than allowed through as domain names.
      expect(isAllowedHost('0177.0.0.1'), isFalse);
      expect(isAllowedHost('1234.1.1.1'), isFalse);
      // A real dotted-quad public IP is unaffected.
      expect(isAllowedHost('8.8.8.8'), isTrue);
    });

    test('blocks remaining special-use IPv4 ranges', () {
      // CGNAT 100.64/10
      expect(isAllowedHost('100.64.0.1'), isFalse);
      expect(isAllowedHost('100.127.255.255'), isFalse);
      // TEST-NET-1/2/3
      expect(isAllowedHost('192.0.2.1'), isFalse);
      expect(isAllowedHost('198.51.100.1'), isFalse);
      expect(isAllowedHost('203.0.113.1'), isFalse);
      // 6to4 relay 192.88.99/24
      expect(isAllowedHost('192.88.99.1'), isFalse);
      // Benchmarking 198.18/15
      expect(isAllowedHost('198.18.0.1'), isFalse);
      expect(isAllowedHost('198.19.255.255'), isFalse);
      // Multicast 224/4 and reserved 240/4
      expect(isAllowedHost('224.0.0.1'), isFalse);
      expect(isAllowedHost('240.0.0.1'), isFalse);
      expect(isAllowedHost('255.255.255.255'), isFalse);
      // IETF protocol assignments 192.0.0/24
      expect(isAllowedHost('192.0.0.1'), isFalse);
    });

    test('validateServerUrl fails closed on DNS lookup timeout', () async {
      final hung = Completer<List<InternetAddress>>();
      dnsLookup = (host) => hung.future;
      await expectLater(
        validateServerUrl('http://hanging-dns.example.com:8000'),
        throwsA(isArgumentError),
      );
    });

    test('blocks empty host after trim', () {
      expect(isAllowedHost(''), isFalse);
      expect(isAllowedHost('   '), isFalse);
    });

    test('blocks IPv4-compatible IPv6 ::127.0.0.1', () {
      expect(isAllowedHost('::127.0.0.1'), isFalse);
    });

    test('blocks 6to4 embedding private IPv4', () {
      // 2002:ac10::1 embeds 172.16.0.1 (RFC 1918)
      expect(isAllowedHost('2002:ac10::1'), isFalse);
    });

    test('blocks RFC 6052 embedding private IPv4', () {
      // 64:ff9b::7f00:1 embeds 127.0.0.1 (loopback)
      expect(isAllowedHost('64:ff9b::7f00:1'), isFalse);
    });

    test('allows 6to4 embedding public IPv4', () {
      // 2002:808::8 embeds 8.8.8.8 (public)
      expect(isAllowedHost('2002:808::8'), isTrue);
    });

    test('strips IPv6 zone ID before checking', () {
      expect(isAllowedHost('fe80::1%eth0'), isFalse);
      expect(isAllowedHost('::1%eth0'), isFalse);
    });

    test('allows non-numeric 4-label names (DNS domains)', () {
      expect(isAllowedHost('127.0.0.o1'), isTrue);
    });

    test('blocks alternative IPv4 notation integer', () {
      expect(isAllowedHost('2130706433'), isFalse);
    });

    test('blocks alternative IPv4 notation hex', () {
      expect(isAllowedHost('0x7f000001'), isFalse);
    });

    test('blocks leading-zero octet', () {
      expect(isAllowedHost('010.000.000.001'), isFalse);
    });

    test('blocks empty host', () {
      expect(isAllowedHost(''), isFalse);
    });

    test('blocks host with whitespace', () {
      expect(isAllowedHost('127 .0.0.1'), isFalse);
    });

    test('blocks host with control characters', () {
      expect(isAllowedHost('127.0.0.1\x00'), isFalse);
    });

    test('allows domain names even if they resolve privately', () {
      // Domain names bypass IP allowlist; request-time revalidation covers them.
      expect(isAllowedHost('evil.example.com'), isTrue);
    });
  });

  group('_ipv4InBlockedRange (via isAllowedHost)', () {
    test('/0 CIDR entry does not fail-open', () {
      // '0.0.0.0/8' is blocked explicitly, but a hypothetical /0 would match
      // everything. The /0 guard ensures prefix 0 matches nothing.
      expect(isAllowedHost('8.8.8.8'), isTrue);
    });

    test('blocks CIDR boundary octets', () {
      expect(isAllowedHost('10.255.255.255'), isFalse);
      expect(isAllowedHost('172.31.255.255'), isFalse);
      expect(isAllowedHost('192.168.255.255'), isFalse);
    });

    test('allows just-outside CIDR ranges', () {
      expect(isAllowedHost('11.0.0.1'), isTrue);
      expect(isAllowedHost('172.32.0.1'), isTrue);
      expect(isAllowedHost('192.169.0.1'), isTrue);
    });

    test('non-numeric octet is allowed (treated as DNS name)', () {
      expect(isAllowedHost('127.0.0.o1'), isTrue);
    });
  });

  group('validateServerUrl', () {
    test('accepts public http URL', () async {
      await expectLater(
        validateServerUrl('http://example.com/train'),
        completes,
      );
    });

    test('accepts public https URL', () async {
      await expectLater(
        validateServerUrl('https://example.com/train'),
        completes,
      );
    });

    test('accepts multi-label public domain (regression)', () async {
      await expectLater(
        validateServerUrl('https://api.prod.example.com/train'),
        completes,
      );
    });

    test('rejects non-http/https scheme', () {
      expect(
        () async => validateServerUrl('ftp://example.com/train'),
        throwsA(isArgumentError),
      );
      expect(
        () async => validateServerUrl('file:///etc/passwd'),
        throwsA(isArgumentError),
      );
    });

    test('rejects malformed input', () {
      expect(
          () async => validateServerUrl('not-a-url'), throwsA(isArgumentError));
      expect(() async => validateServerUrl(''), throwsA(isArgumentError));
    });

    test('rejects empty host', () {
      expect(
        () async => validateServerUrl('http://:8000/'),
        throwsA(isArgumentError),
      );
    });

    test('rejects host with whitespace', () {
      expect(
        () async => validateServerUrl('http://127 .0.0.1:8000/'),
        throwsA(isArgumentError),
      );
    });

    test('rejects embedded credentials (userInfo)', () {
      expect(
        () async => validateServerUrl('http://user:pass@evil.com/'),
        throwsA(isArgumentError),
      );
    });

    test('blocks loopback IPv4', () {
      expect(
        () async => validateServerUrl('http://127.0.0.1:8000/train'),
        throwsA(isArgumentError),
      );
      expect(
        () async => validateServerUrl('http://localhost:8000/train'),
        throwsA(isArgumentError),
      );
    });

    test('blocks RFC 1918 private ranges', () {
      expect(
        () async => validateServerUrl('http://10.0.0.1:8000/train'),
        throwsA(isArgumentError),
      );
      expect(
        () async => validateServerUrl('http://172.16.0.1:8000/train'),
        throwsA(isArgumentError),
      );
      expect(
        () async => validateServerUrl('http://192.168.1.1:8000/train'),
        throwsA(isArgumentError),
      );
    });

    test('blocks link-local and metadata', () {
      expect(
        () async => validateServerUrl('http://169.254.169.254/train'),
        throwsA(isArgumentError),
      );
    });

    test('blocks IPv6 loopback and link-local', () {
      expect(
        () async => validateServerUrl('http://[::1]:8000/train'),
        throwsA(isArgumentError),
      );
      expect(
        () async => validateServerUrl('http://[fe80::1]:8000/train'),
        throwsA(isArgumentError),
      );
    });

    test('allows public IPv6 documentation range', () async {
      await expectLater(
        validateServerUrl('http://[2001:db8::1]:8000/train'),
        completes,
      );
    });

    test('blocks alternative IPv4 notation', () {
      expect(
        () async => validateServerUrl('http://2130706433:8000/train'),
        throwsA(isArgumentError),
      );
    });

    test('blocks 6to4 embedding private IPv4', () {
      expect(
        () async => validateServerUrl('http://[2002:ac10::1]:8000/train'),
        throwsA(isArgumentError),
      );
    });
  });

  group('validateServerUrl DNS resolve+revalidate', () {
    test('allows domain resolving to public IP', () async {
      dnsLookup = (host) async => <InternetAddress>[InternetAddress('8.8.8.8')];
      await expectLater(
        validateServerUrl('http://example.com/train'),
        completes,
      );
    });

    test('blocks domain resolving to blocked IP', () {
      dnsLookup =
          (host) async => <InternetAddress>[InternetAddress('127.0.0.1')];
      expect(
        () async => validateServerUrl('http://evil.example.com/train'),
        throwsA(isArgumentError),
      );
    });

    test('blocks domain resolving to link-local metadata IP', () {
      dnsLookup =
          (host) async => <InternetAddress>[InternetAddress('169.254.169.254')];
      expect(
        () async => validateServerUrl('http://metadata.google.internal/train'),
        throwsA(isArgumentError),
      );
    });

    test('fail-closed when DNS lookup throws', () {
      dnsLookup = (host) async => throw ArgumentError('DNS failure');
      expect(
        () async => validateServerUrl('http://example.com/train'),
        throwsA(isArgumentError),
      );
    });

    test('maps a DNS transport failure to an ArgumentError', () {
      // A SocketException from the resolver must surface as the dedicated
      // ArgumentError, never escape as a raw SocketException (the bloc
      // relies on this mapping for transient-outage classification).
      dnsLookup = (host) async => throw const SocketException('DNS down');
      expect(
        () async => validateServerUrl('http://example.com/train'),
        throwsA(
          isArgumentError.having(
            (e) => e.message,
            'message',
            'DNS lookup failed',
          ),
        ),
      );
    });

    test('fail-closed when DNS returns no addresses', () {
      dnsLookup = (host) async => <InternetAddress>[];
      expect(
        () async => validateServerUrl('http://example.com/train'),
        throwsA(isArgumentError),
      );
    });
  });

  group('assertAllowedHost', () {
    test('passes public URL', () {
      expect(
        () => assertAllowedHost('http://example.com/path'),
        returnsNormally,
      );
    });

    test('passes public IPv4 URL', () {
      expect(() => assertAllowedHost('http://8.8.8.8/'), returnsNormally);
    });

    test('rejects blocked host', () {
      expect(
        () => assertAllowedHost('http://127.0.0.1/'),
        throwsA(isArgumentError),
      );
      expect(
        () => assertAllowedHost('http://localhost:8000/'),
        throwsA(isArgumentError),
      );
    });

    test('rejects embedded credentials (userInfo)', () {
      expect(
        () => assertAllowedHost('http://user:pass@evil.com/'),
        throwsA(isArgumentError),
      );
    });

    test('rejects invalid URL', () {
      expect(() => assertAllowedHost('not-a-url'), throwsA(isArgumentError));
      expect(() => assertAllowedHost(''), throwsA(isArgumentError));
    });

    test('rejects empty host', () {
      expect(
        () => assertAllowedHost('http://:8000/'),
        throwsA(isArgumentError),
      );
    });

    test('rejects non-http(s) scheme', () {
      expect(
        () => assertAllowedHost('ftp://example.com/'),
        throwsA(isArgumentError),
      );
      expect(
        () => assertAllowedHost('file:///etc/passwd'),
        throwsA(isArgumentError),
      );
    });
  });

  group('validateServerUrlSync', () {
    test('returns the parsed URI for a public URL', () {
      final uri = validateServerUrlSync('http://example.com:8000');
      expect(uri.host, 'example.com');
      expect(uri.port, 8000);
      expect(uri.scheme, 'http');
    });

    test('rejects raw control characters before parsing', () {
      expect(
        () => validateServerUrlSync('http://example.com/\x00'),
        throwsA(isArgumentError),
      );
      expect(
        () => validateServerUrlSync('http://example.com\x7F'),
        throwsA(isArgumentError),
      );
    });

    test('rejects blocked host', () {
      expect(
        () => validateServerUrlSync('http://127.0.0.1:8000'),
        throwsA(isArgumentError),
      );
    });

    test('rejects trailing-dot loopback and octal shorthand hosts', () {
      // localhost.. used to survive the single-dot strip; 0177.0.0.1 is
      // octal shorthand for 127.0.0.1.
      expect(
        () => validateServerUrlSync('http://localhost../:8000'),
        throwsA(isArgumentError),
      );
      expect(
        () => validateServerUrlSync('http://0177.0.0.1:8000'),
        throwsA(isArgumentError),
      );
    });

    test('rejects embedded credentials', () {
      expect(
        () => validateServerUrlSync('http://user:pass@example.com'),
        throwsA(isArgumentError),
      );
    });

    test('rejects malformed and empty-host input', () {
      expect(
          () => validateServerUrlSync('not-a-url'), throwsA(isArgumentError));
      expect(
        () => validateServerUrlSync('http://:8000/'),
        throwsA(isArgumentError),
      );
    });

    test('rejects non-http(s) scheme', () {
      expect(
        () => validateServerUrlSync('ftp://example.com/'),
        throwsA(isArgumentError),
      );
    });
  });

  group('rejectRedirect', () {
    test('passes 200 response', () {
      expect(
        () => rejectRedirect(http.Response('body', 200)),
        returnsNormally,
      );
    });

    test('passes 404 response', () {
      expect(
        () => rejectRedirect(http.Response('body', 404)),
        returnsNormally,
      );
    });

    test('passes 500 response', () {
      expect(
        () => rejectRedirect(http.Response('body', 500)),
        returnsNormally,
      );
    });

    test('rejects 301 response', () {
      expect(
        () => rejectRedirect(http.Response('body', 301)),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('rejects 302 response', () {
      expect(
        () => rejectRedirect(http.Response('body', 302)),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('rejects 307 response', () {
      expect(
        () => rejectRedirect(http.Response('body', 307)),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('rejects 308 response', () {
      expect(
        () => rejectRedirect(http.Response('body', 308)),
        throwsA(isA<http.ClientException>()),
      );
    });
  });
}
