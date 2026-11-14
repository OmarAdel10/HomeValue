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

    test('blocks malformed IPv4 with 4 dot parts', () {
      expect(isAllowedHost('127.0.0.o1'), isFalse);
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

    test('non-numeric octet is treated as blocked', () {
      expect(isAllowedHost('127.0.0.o1'), isFalse);
    });
  });

  group('validateServerUrl', () {
    test('accepts public http URL', () {
      expect(
        () async => validateServerUrl('http://example.com/train'),
        returnsNormally,
      );
    });

    test('accepts public https URL', () {
      expect(
        () async => validateServerUrl('https://example.com/train'),
        returnsNormally,
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

    test('allows public IPv6 documentation range', () {
      expect(
        () async => validateServerUrl('http://[2001:db8::1]:8000/train'),
        returnsNormally,
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
    test('allows domain resolving to public IP', () {
      dnsLookup = (host) async => <InternetAddress>[InternetAddress('8.8.8.8')];
      expect(
        () async => validateServerUrl('http://example.com/train'),
        returnsNormally,
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
