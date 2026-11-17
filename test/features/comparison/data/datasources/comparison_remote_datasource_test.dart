import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:home_value/features/comparison/data/datasources/comparison_remote_datasource.dart';
import 'package:home_value/features/comparison/data/models/model_comparison_model.dart';
import 'package:home_value/core/validation.dart' as validation;

void main() {
  setUp(() {
    validation.dnsLookup =
        (host) async => <InternetAddress>[InternetAddress('8.8.8.8')];
  });

  tearDown(() {
    validation.dnsLookup = InternetAddress.lookup;
  });

  group('ComparisonRemoteDataSource constructor + assertAllowedHost', () {
    test('accepts public IPv4 URL', () {
      expect(
        () => ComparisonRemoteDataSource(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://8.8.8.8:8000',
        ),
        returnsNormally,
      );
    });

    test('accepts public IPv6 documentation range', () {
      expect(
        () => ComparisonRemoteDataSource(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://[2001:db8::1]:8000',
        ),
        returnsNormally,
      );
    });

    test('rejects loopback IPv4 URL', () {
      expect(
        () => ComparisonRemoteDataSource(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://127.0.0.1:8000',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects RFC 1918 private URL', () {
      expect(
        () => ComparisonRemoteDataSource(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://10.0.0.1:8000',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects link-local metadata URL', () {
      expect(
        () => ComparisonRemoteDataSource(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://169.254.169.254:8000',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects localhost hostname', () {
      expect(
        () => ComparisonRemoteDataSource(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://localhost:8000',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('_resolveAndValidateHost', () {
    test('literal public IP passes through unchanged', () async {
      final datasource = ComparisonRemoteDataSource(
        client: MockClient((_) async => http.Response('[]', 200)),
        baseUrl: 'http://8.8.8.8:8000',
      );
      // Access via fetchModelComparison which calls _resolveAndValidateHost.
      final result = await datasource.fetchModelComparison();
      expect(result, isA<ModelComparisonModel>());
    });

    test('literal private IP rejected via constructor', () {
      expect(
        () => ComparisonRemoteDataSource(
          client: MockClient((_) async => http.Response('[]', 200)),
          baseUrl: 'http://10.0.0.1:8000',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('fetchModelComparison', () {
    test('returns ModelComparisonModel on 200', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), contains('/model/comparison'));
        return http.Response(
          '[{"model_name":"model_a","rmse":1.0,"mae":0.5,"r2":0.9,"cv_std":0.1,"is_best":true}]',
          200,
        );
      });
      final datasource = ComparisonRemoteDataSource(
        client: client,
        baseUrl: 'http://8.8.8.8:8000',
      );
      final result = await datasource.fetchModelComparison();
      expect(result, isA<ModelComparisonModel>());
      expect(result.metrics.length, 1);
      expect(result.metrics.first.name, 'model_a');
    });

    test('rejectRedirect throws on 302', () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse,
            reason: 'redirects must never be followed (SSRF)');
        return http.Response('', 302);
      });
      final datasource = ComparisonRemoteDataSource(
        client: client,
        baseUrl: 'http://8.8.8.8:8000',
      );
      expect(
        () => datasource.fetchModelComparison(),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('throws Exception on non-200 non-3xx status', () async {
      final client = MockClient((_) async => http.Response('error', 500));
      final datasource = ComparisonRemoteDataSource(
        client: client,
        baseUrl: 'http://8.8.8.8:8000',
      );
      expect(
        () => datasource.fetchModelComparison(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ModelComparisonModel.fromJson', () {
    test('parses JSON array of metrics', () {
      final model = ModelComparisonModel.fromJson(
        '[{"model_name":"model_a","rmse":2.5,"mae":1.2,"r2":0.8,"cv_std":0.3,"is_best":false}]',
      );
      expect(model.metrics.length, 1);
      expect(model.metrics.first.name, 'model_a');
      expect(model.metrics.first.rmse, 2.5);
      expect(model.metrics.first.isBest, isFalse);
    });

    test('parses JSON object with models key', () {
      final model = ModelComparisonModel.fromJson(
        '{"models":[{"model_name":"model_b","rmse":1.5,"mae":0.8,"r2":0.85,"cv_std":0.2,"is_best":true}]}',
      );
      expect(model.metrics.length, 1);
      expect(model.metrics.first.isBest, isTrue);
    });

    test('isBest default false when missing', () {
      final model = ModelComparisonModel.fromJson(
        '[{"model_name":"model_a","rmse":1.0,"mae":0.5,"r2":0.9}]',
      );
      expect(model.metrics.first.isBest, isFalse);
    });
  });
  group('domain-base DNS resolve + IP pinning', () {
    test('domain base resolves and pins request to resolved IP', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          '[{"model_name":"m","rmse":1.0,"mae":0.5,"r2":0.9,"cv_std":0.1}]',
          200,
        );
      });
      final datasource = ComparisonRemoteDataSource(
        client: client,
        baseUrl: 'http://api.example.com:8000',
      );
      await datasource.fetchModelComparison();
      // http: request host is the resolved (validated) IP, port preserved.
      expect(captured, isNotNull);
      expect(captured!.url.host, '8.8.8.8');
      expect(captured!.url.port, 8000);
      expect(captured!.followRedirects, isFalse);
    });

    test('DNS timeout fails closed with ArgumentError', () async {
      final never = Completer<List<InternetAddress>>();
      validation.dnsLookup = (host) => never.future;
      final datasource = ComparisonRemoteDataSource(
        client: MockClient((_) async => http.Response('[]', 200)),
        baseUrl: 'http://api.example.com:8000',
        timeout: const Duration(milliseconds: 50),
      );
      expect(
        () => datasource.fetchModelComparison(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('blocked resolved IP fails closed', () async {
      validation.dnsLookup =
          (host) async => <InternetAddress>[InternetAddress('169.254.169.254')];
      final datasource = ComparisonRemoteDataSource(
        client: MockClient((_) async => http.Response('[]', 200)),
        baseUrl: 'http://api.example.com:8000',
      );
      expect(
        () => datasource.fetchModelComparison(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('DNS failure fails closed', () async {
      validation.dnsLookup =
          (host) async => Future.error(const SocketException('offline'));
      final datasource = ComparisonRemoteDataSource(
        client: MockClient((_) async => http.Response('[]', 200)),
        baseUrl: 'http://api.example.com:8000',
      );
      expect(
        () => datasource.fetchModelComparison(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('dispose never closes an injected client (owner manages it)', () {
      var closed = 0;
      final injectedClient = _CloseTrackingClient(() => closed++);
      final datasource = ComparisonRemoteDataSource(
        client: injectedClient,
        baseUrl: 'http://8.8.8.8:8000',
      );
      datasource.dispose();
      expect(closed, 0);
    });

    test('dispose on an owned client is safe and idempotent', () {
      final datasource = ComparisonRemoteDataSource(
        baseUrl: 'http://8.8.8.8:8000',
      );
      datasource.dispose();
      datasource.dispose();
    });
  });

  group('https keeps the hostname and baseUrlProvider is honoured', () {
    test('https base keeps the hostname (no IP pinning)', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          '[{"model_name":"m","rmse":1.0,"mae":0.5,"r2":0.9,"cv_std":0.1}]',
          200,
        );
      });
      final datasource = ComparisonRemoteDataSource(
        client: client,
        baseUrl: 'https://api.example.com:8000',
      );
      await datasource.fetchModelComparison();
      // https: the original hostname is preserved so TLS SNI and
      // certificate-name verification use the domain certificate.
      expect(captured, isNotNull);
      expect(captured!.url.host, 'api.example.com');
      expect(captured!.url.port, 8000);
      expect(captured!.followRedirects, isFalse);
    });

    test('baseUrlProvider supplies the request base URL', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          '[{"model_name":"m","rmse":1.0,"mae":0.5,"r2":0.9,"cv_std":0.1}]',
          200,
        );
      });
      final datasource = ComparisonRemoteDataSource(
        client: client,
        baseUrl: 'http://8.8.8.8:8000',
        baseUrlProvider: () => 'http://api.example.com:8000',
      );
      await datasource.fetchModelComparison();
      expect(captured, isNotNull);
      expect(captured!.url.host, '8.8.8.8');
      expect(captured!.url.port, 8000);
    });

    test('a blocked host from baseUrlProvider fails closed', () async {
      final client = MockClient((request) async {
        fail('request must not be sent to a blocked host');
      });
      final datasource = ComparisonRemoteDataSource(
        client: client,
        baseUrl: 'http://8.8.8.8:8000',
        baseUrlProvider: () => 'http://127.0.0.1:8000',
      );
      await expectLater(
        datasource.fetchModelComparison(),
        throwsA(isArgumentError),
      );
    });
  });

  group('URL rebuild strips query/fragment and trailing slashes', () {
    test('a foreign query and fragment on the base never reach the request',
        () async {
      final captured = <http.Request>[];
      final datasource = ComparisonRemoteDataSource(
        client: MockClient((request) async {
          captured.add(request);
          return http.Response('[]', 500);
        }),
        // String concatenation would push /model/comparison into the query
        // string and GET '/' instead; Uri.replace(query: null) keeps the
        // existing query in Dart. Rebuilding from components drops both.
        baseUrl: 'http://8.8.8.8:8000/api?x=1#frag',
      );
      await expectLater(
        datasource.fetchModelComparison(),
        throwsA(isException),
      );
      expect(captured, hasLength(1));
      expect(
        captured.single.url.toString(),
        'http://8.8.8.8:8000/api/model/comparison',
      );
      expect(captured.single.url.query, isEmpty);
      expect(captured.single.url.fragment, isEmpty);
    });

    test('trailing slashes in the base path never double-slash the endpoint',
        () async {
      final captured = <http.Request>[];
      final datasource = ComparisonRemoteDataSource(
        client: MockClient((request) async {
          captured.add(request);
          return http.Response('[]', 500);
        }),
        baseUrl: 'http://8.8.8.8:8000/api///',
      );
      await expectLater(
        datasource.fetchModelComparison(),
        throwsA(isException),
      );
      expect(captured, hasLength(1));
      expect(
        captured.single.url.toString(),
        'http://8.8.8.8:8000/api/model/comparison',
      );
      expect(captured.single.url.path, isNot(contains('//')));
    });
  });
}

/// Minimal [http.BaseClient] subclass that counts close() calls so the
/// datasource dispose contract is observable.
class _CloseTrackingClient extends http.BaseClient {
  final void Function() onClose;

  _CloseTrackingClient(this.onClose);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnimplementedError();
  }

  @override
  void close() => onClose();
}
