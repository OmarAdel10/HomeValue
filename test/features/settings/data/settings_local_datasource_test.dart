import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_value/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:home_value/core/validation.dart' as validation;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late SettingsLocalDataSource dataSource;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);
    // Stub DNS so validateServerUrl domain tests pass offline.
    validation.dnsLookup =
        (host) async => <InternetAddress>[InternetAddress('8.8.8.8')];
  });

  tearDown(() {
    validation.dnsLookup = InternetAddress.lookup;
  });

  test('returns defaults when nothing is stored', () async {
    final settings = await dataSource.getSettings();

    expect(settings.serverUrl, 'http://example.com:8000');
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.autoRetrain, isFalse);
    expect(settings.lastAutoRetrainAt, isNull);
  });

  test('getSettings validates each distinct URL once', () async {
    await prefs.setString('server_url', 'http://example.com:8000');
    var lookups = 0;
    validation.dnsLookup = (host) async {
      lookups++;
      return <InternetAddress>[InternetAddress('8.8.8.8')];
    };

    await dataSource.getSettings();
    await dataSource.getSettings();

    expect(lookups, 1);
  });

  test('updateServerUrl refreshes the validation cache', () async {
    await prefs.setString('server_url', 'http://example.com:8000');
    var lookups = 0;
    validation.dnsLookup = (host) async {
      lookups++;
      return <InternetAddress>[InternetAddress('8.8.8.8')];
    };

    await dataSource.getSettings();
    await dataSource.updateServerUrl('http://example.org:9000');
    await dataSource.getSettings();

    expect(lookups, 2);
  });

  test('a blocked updateServerUrl does not poison the cache', () async {
    await prefs.setString('server_url', 'http://example.com:8000');
    var lookups = 0;
    validation.dnsLookup = (host) async {
      lookups++;
      return <InternetAddress>[InternetAddress('8.8.8.8')];
    };

    await dataSource.getSettings();
    await expectLater(
      dataSource.updateServerUrl('http://127.0.0.1:8000/'),
      throwsArgumentError,
    );
    final settings = await dataSource.getSettings();

    expect(lookups, 1);
    expect(settings.serverUrl, 'http://example.com:8000');
  });

  test('getSettings survives a generic DNS exception while offline', () async {
    await prefs.setString('server_url', 'http://example.com:8000');
    validation.dnsLookup = (host) async => throw Exception('offline');

    final settings = await dataSource.getSettings();

    expect(settings.serverUrl, 'http://example.com:8000');
  });

  test('a failed validation is negatively cached for the same URL', () async {
    // Every mutation handler awaits getSettings(); without a negative cache
    // a DNS outage would re-run the full 10s lookup on every persist.
    await prefs.setString('server_url', 'http://example.com:8000');
    var dnsCalls = 0;
    validation.dnsLookup = (host) async {
      dnsCalls++;
      throw const SocketException('DNS offline');
    };

    // First read: the validation attempt runs and fails, but the load still
    // returns persisted settings (fail-open at load, fail-closed at request).
    final first = await dataSource.getSettings();
    expect(first.serverUrl, 'http://example.com:8000');
    expect(dnsCalls, 1);

    // Second read must not re-run the lookup for the same URL.
    final second = await dataSource.getSettings();
    expect(second.serverUrl, 'http://example.com:8000');
    expect(dnsCalls, 1);

    // updateServerUrl validates live (outside the read cache), so the
    // outage fails the persist and the URL stays unchanged; the failed
    // attempt does not corrupt the read path.
    await expectLater(
      dataSource.updateServerUrl('http://example.org:9000'),
      throwsA(isArgumentError),
    );
    expect(dnsCalls, 2);
    final third = await dataSource.getSettings();
    expect(third.serverUrl, 'http://example.com:8000');
    expect(dnsCalls, 2);
  });

  test('reads a stored retrain timestamp', () async {
    final stored = DateTime(2026, 10, 27, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'last_auto_retrain_at': stored.millisecondsSinceEpoch,
    });
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);

    final settings = await dataSource.getSettings();

    expect(settings.lastAutoRetrainAt, stored);
  });

  test('persists the retrain timestamp so it survives a restart', () async {
    final stored = DateTime(2026, 10, 27, 18, 30);

    final updated = await dataSource.updateLastAutoRetrain(stored);

    expect(updated.lastAutoRetrainAt, stored);
    expect(
      prefs.getInt('last_auto_retrain_at'),
      stored.millisecondsSinceEpoch,
    );

    final reopened = SettingsLocalDataSource(prefs);
    final reloaded = await reopened.getSettings();
    expect(reloaded.lastAutoRetrainAt, stored);
  });

  test('ignores an out of range retrain timestamp', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'last_auto_retrain_at': 9223372036854775807,
    });
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);

    final settings = await dataSource.getSettings();

    expect(settings.lastAutoRetrainAt, isNull);
  });

  test('falls back to system theme for an unknown index', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'theme_mode': 99});
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);

    final settings = await dataSource.getSettings();

    expect(settings.themeMode, ThemeMode.system);
  });

  // --- validateServerUrl tests (SSRF mitigation) ---

  test('validateServerUrl accepts public http URL', () async {
    await expectLater(
      SettingsLocalDataSource.validateServerUrl('http://example.com/train'),
      completes,
    );
  });

  test('validateServerUrl accepts public https URL', () async {
    await expectLater(
      SettingsLocalDataSource.validateServerUrl('https://example.com/train'),
      completes,
    );
  });

  test('validateServerUrl rejects non-http/https scheme', () {
    expect(
      () =>
          SettingsLocalDataSource.validateServerUrl('ftp://example.com/train'),
      throwsA(isArgumentError),
    );
    expect(
      () async =>
          SettingsLocalDataSource.validateServerUrl('file:///etc/passwd'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl rejects malformed input', () {
    expect(
      () async => SettingsLocalDataSource.validateServerUrl('not-a-url'),
      throwsA(isArgumentError),
    );
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(''),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl blocks loopback IPv4', () {
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://127.0.0.1:8000/train'),
      throwsA(isArgumentError),
    );
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://localhost:8000/train'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl blocks RFC 1918 private ranges', () {
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://10.0.0.1:8000/train'),
      throwsA(isArgumentError),
    );
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://172.16.0.1:8000/train'),
      throwsA(isArgumentError),
    );
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://192.168.1.1:8000/train'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl blocks link-local and metadata', () {
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://169.254.169.254/train'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl blocks IPv6 loopback and link-local', () {
    expect(
      () =>
          SettingsLocalDataSource.validateServerUrl('http://[::1]:8000/train'),
      throwsA(isArgumentError),
    );
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://[fe80::1]:8000/train'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl allows public IPv6 documentation range', () async {
    await expectLater(
      SettingsLocalDataSource.validateServerUrl(
          'http://[2001:db8::1]:8000/train'),
      completes,
    );
  });

  // --- updateServerUrl validation side-effect tests ---

  test('updateServerUrl rejects blocked host and does not persist', () async {
    expect(
      () async => dataSource.updateServerUrl('http://127.0.0.1:8000/train'),
      throwsA(isArgumentError),
    );
    expect(prefs.getString('server_url'), isNull);
  });

  test('updateServerUrl persists allowed host', () async {
    final updated =
        await dataSource.updateServerUrl('http://example.com:8000/train');

    expect(updated.serverUrl, 'http://example.com:8000/train');
    expect(prefs.getString('server_url'), 'http://example.com:8000/train');
  });

  // --- getSettings validates default URL ---

  test('getSettings with blocked default serverUrl does not throw', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_url': 'http://127.0.0.1:8000/',
    });
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);

    // Should not throw; blocked URL is tolerated at load but retraining is rejected.
    final settings = await dataSource.getSettings();
    expect(settings.serverUrl, 'http://127.0.0.1:8000/');
  });

  // --- SSRF edge-case tests ---

  test('validateServerUrl blocks 0.0.0.0 (CIDR 0/8)', () {
    expect(
      () async =>
          SettingsLocalDataSource.validateServerUrl('http://0.0.0.0:8000/'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl blocks IPv4-mapped IPv6 loopback ::ffff:127.0.0.1',
      () {
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://[::ffff:127.0.0.1]:8000/train'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl blocks CIDR boundary 10.255.255.255', () {
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://10.255.255.255:8000/train'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl blocks CIDR boundary 172.31.255.255', () {
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://172.31.255.255:8000/train'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl blocks CIDR boundary 192.168.255.255', () {
    expect(
      () async => SettingsLocalDataSource.validateServerUrl(
          'http://192.168.255.255:8000/train'),
      throwsA(isArgumentError),
    );
  });

  test('validateServerUrl allows non-numeric 4-label DNS names', () async {
    await expectLater(
      SettingsLocalDataSource.validateServerUrl('http://127.0.0.o1:8000/train'),
      completes,
    );
  });

  test('validateServerUrl allows public IP outside blocked ranges', () async {
    await expectLater(
      SettingsLocalDataSource.validateServerUrl('http://8.8.8.8:8000/train'),
      completes,
    );
  });

  // --- serverUrlBlocked tests ---

  test('serverUrlBlocked returns false for allowed URL', () async {
    await dataSource.updateServerUrl('http://example.com:8000/train');
    expect(dataSource.serverUrlBlocked, isFalse);
  });

  test('serverUrlBlocked returns true for blocked URL', () async {
    await expectLater(
      dataSource.updateServerUrl('http://127.0.0.1:8000/train'),
      throwsA(isArgumentError),
    );
    // updateServerUrl rejects before persisting, so stored URL is still default.
    // Directly persist a blocked URL via setMockInitialValues for a fresh instance.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_url': 'http://127.0.0.1:8000/',
    });
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);
    expect(dataSource.serverUrlBlocked, isTrue);
  });

  test('serverUrlBlocked returns true for default blocked URL', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_url': 'http://169.254.169.254/',
    });
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);
    expect(dataSource.serverUrlBlocked, isTrue);
  });

  test('serverUrlBlocked fails closed for unparseable stored URLs', () async {
    // A malformed stored URL parses to no authority: empty host fails closed.
    await prefs.setString('server_url', 'not a url');
    expect(dataSource.serverUrlBlocked, isTrue);
    // An empty host ('http://') must also fail closed.
    await prefs.setString('server_url', 'http://');
    expect(dataSource.serverUrlBlocked, isTrue);
  });

  test('updateThemeMode persists and returns updated settings', () async {
    await prefs.setString('server_url', 'http://example.com:8000');
    // Don't mock updateThemeMode - test the real implementation.

    final result = await dataSource.updateThemeMode(ThemeMode.dark);

    expect(result.themeMode, ThemeMode.dark);
    expect(result.serverUrl, 'http://example.com:8000');
    expect(result.autoRetrain, isFalse);
    expect(prefs.getInt('theme_mode'), ThemeMode.dark.index);
  });

  test('updateAutoRetrain persists and returns updated settings', () async {
    await prefs.setString('server_url', 'http://example.com:8000');
    // Don't mock updateAutoRetrain - test the real implementation.

    final result = await dataSource.updateAutoRetrain(true);

    expect(result.autoRetrain, isTrue);
    expect(result.serverUrl, 'http://example.com:8000');
    expect(result.themeMode, ThemeMode.system);
    expect(prefs.getBool('auto_retrain'), isTrue);
  });

  test('getSettings uses default initialRetrainDelay when not stored', () async {
    // No initial_retrain_delay_millis stored: fallback to 5 minutes.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_url': 'http://example.com:8000',
    });
    prefs = await SharedPreferences.getInstance();
    dataSource = SettingsLocalDataSource(prefs);

    final settings = await dataSource.getSettings();

    expect(settings.initialRetrainDelay, Duration(minutes: 5));
  });
}
