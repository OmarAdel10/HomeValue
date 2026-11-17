import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:home_value/features/prediction/data/datasources/prediction_remote_datasource.dart';
import 'package:home_value/features/prediction/domain/entities/house_features.dart';
import 'package:home_value/features/prediction/domain/entities/model_info.dart';
import 'package:home_value/features/prediction/domain/entities/prediction_result.dart';
import 'package:home_value/features/prediction/domain/repositories/prediction_repository.dart';
import 'package:home_value/core/validation.dart' as validation;

void main() {
  const baseUrl = 'http://8.8.8.8:8000';
  const blockedUrl = 'http://127.0.0.1:8000';

  setUp(() {
    validation.dnsLookup =
        (host) async => <InternetAddress>[InternetAddress('8.8.8.8')];
  });

  tearDown(() {
    validation.dnsLookup = InternetAddress.lookup;
  });

  final features = const HouseFeatures(
    medInc: 8.3252,
    houseAge: 41.0,
    aveRooms: 6.984127,
    aveBedrms: 1.02381,
    population: 322.0,
    aveOccup: 2.555556,
    latitude: 37.88,
    longitude: -122.23,
    oceanProximity: OceanProximity.nearBay,
  );

  group('PredictionRemoteDataSource constructor + assertAllowedHost', () {
    test('accepts public IPv4 URL', () {
      expect(
        () => PredictionRemoteDataSource(
          baseUrl: baseUrl,
          timeout: const Duration(seconds: 30),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        returnsNormally,
      );
    });

    test('accepts public IPv6 documentation range', () {
      expect(
        () => PredictionRemoteDataSource(
          baseUrl: 'http://[2001:db8::1]:8000',
          timeout: const Duration(seconds: 30),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        returnsNormally,
      );
    });

    test('rejects loopback IPv4 URL', () {
      expect(
        () => PredictionRemoteDataSource(
          baseUrl: blockedUrl,
          timeout: const Duration(seconds: 30),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects RFC 1918 private URL', () {
      expect(
        () => PredictionRemoteDataSource(
          baseUrl: 'http://10.0.0.1:8000',
          timeout: const Duration(seconds: 30),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects link-local metadata URL', () {
      expect(
        () => PredictionRemoteDataSource(
          baseUrl: 'http://169.254.169.254:8000',
          timeout: const Duration(seconds: 30),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects localhost hostname', () {
      expect(
        () => PredictionRemoteDataSource(
          baseUrl: 'http://localhost:8000',
          timeout: const Duration(seconds: 30),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('creates IOClient when no client injected (_ownsClient=true)', () {
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
      );
      expect(datasource, isA<PredictionRemoteDataSource>());
      datasource.dispose();
    });

    test('uses injected client (_ownsClient=false)', () {
      final client = MockClient((_) async => http.Response('{}', 200));
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(datasource, isA<PredictionRemoteDataSource>());
      datasource.dispose(); // should NOT close injected client
    });
  });

  group('predict', () {
    test('returns PredictionResult on 200', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), contains('/predict'));
        expect(request.headers['content-type'], 'application/json');
        return http.Response(
          jsonEncode(
              {'prediction': 450000.0, 'model': 'xgb', 'model_version': '1.0'}),
          200,
        );
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      final result = await datasource.predict(features);
      expect(result, isA<PredictionResult>());
      expect(result.prediction, 450000.0);
      expect(result.model, 'xgb');
      expect(result.modelVersion, '1.0');
    });

    test('throws ModelNotLoadedException on 503', () async {
      final client = MockClient((_) async => http.Response('{}', 503));
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.predict(features),
        throwsA(isA<ModelNotLoadedException>()),
      );
    });

    test('throws PredictionException on 500', () async {
      final client = MockClient((_) async => http.Response('{}', 500));
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.predict(features),
        throwsA(isA<PredictionException>()),
      );
    });

    test('rejectRedirect throws on 302', () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse,
            reason: 'redirects must never be followed (SSRF)');
        return http.Response('', 302);
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.predict(features),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('predictBatch', () {
    test('returns List<double> on 200', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), contains('/predict/batch'));
        return http.Response(
          jsonEncode({
            'predictions': [450000.0, 320000.0]
          }),
          200,
        );
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      final result = await datasource.predictBatch([features, features]);
      expect(result, isA<List<double>>());
      expect(result.length, 2);
      expect(result.first, 450000.0);
    });

    test('throws ModelNotLoadedException on 503', () async {
      final client = MockClient((_) async => http.Response('{}', 503));
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.predictBatch([features]),
        throwsA(isA<ModelNotLoadedException>()),
      );
    });

    test('rejectRedirect throws on 302', () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse,
            reason: 'redirects must never be followed (SSRF)');
        return http.Response('', 302);
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.predictBatch([features]),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('getModelInfo', () {
    test('returns ModelInfo on 200', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), contains('/model/info'));
        return http.Response(
          jsonEncode({
            'model': 'xgb',
            'loaded': true,
            'steps': ['load', 'train']
          }),
          200,
        );
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      final result = await datasource.getModelInfo();
      expect(result, isA<ModelInfo>());
      expect(result.model, 'xgb');
      expect(result.loaded, isTrue);
      expect(result.steps, ['load', 'train']);
    });

    test('throws PredictionException on 500', () async {
      final client = MockClient((_) async => http.Response('{}', 500));
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.getModelInfo(),
        throwsA(isA<PredictionException>()),
      );
    });

    test('rejectRedirect throws on 302', () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse,
            reason: 'redirects must never be followed (SSRF)');
        return http.Response('', 302);
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.getModelInfo(),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('getModelComparison', () {
    test('returns List<ModelComparison> on 200', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), contains('/model/comparison'));
        return http.Response(
          jsonEncode({
            'models': [
              {
                'model': 'model_a',
                'rmse': 1.0,
                'mae': 0.5,
                'r2': 0.9,
                'cv_rmse': 0.1,
                'cv_rmse_std': 0.02,
              },
            ],
          }),
          200,
        );
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      final result = await datasource.getModelComparison();
      expect(result, isA<List<ModelComparison>>());
      expect(result.length, 1);
      expect(result.first.model, 'model_a');
    });

    test('throws PredictionException on 500', () async {
      final client = MockClient((_) async => http.Response('{}', 500));
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.getModelComparison(),
        throwsA(isA<PredictionException>()),
      );
    });

    test('rejectRedirect throws on 302', () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse,
            reason: 'redirects must never be followed (SSRF)');
        return http.Response('', 302);
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(
        () => datasource.getModelComparison(),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('dispose', () {
    test('dispose on an owned client is safe and idempotent', () {
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
      );
      expect(() => datasource.dispose(), returnsNormally);
      expect(() => datasource.dispose(), returnsNormally);
    });

    test('dispose never closes an injected client (owner manages it)', () {
      var closed = 0;
      final injectedClient = _CloseTrackingClient(() => closed++);
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: injectedClient,
      );
      datasource.dispose();
      expect(closed, 0);
    });
  });

  group('URL rebuild strips query/fragment and trailing slashes', () {
    test('a foreign query and fragment on the base never reach the request',
        () async {
      final captured = <http.Request>[];
      final datasource = PredictionRemoteDataSource(
        // String concatenation would push /predict into the query string
        // (POST lands on '/' and the retrain silently fails every window);
        // Uri.replace(query: null) keeps the existing query in Dart.
        // Rebuilding from components drops both.
        baseUrl: 'http://8.8.8.8:8000/api?x=1#frag',
        timeout: const Duration(seconds: 30),
        client: MockClient((request) async {
          captured.add(request);
          return http.Response('{}', 500);
        }),
      );
      await expectLater(
        datasource.predict(features),
        throwsA(isA<PredictionException>()),
      );
      expect(captured, hasLength(1));
      expect(
        captured.single.url.toString(),
        'http://8.8.8.8:8000/api/predict',
      );
      expect(captured.single.url.query, isEmpty);
      expect(captured.single.url.fragment, isEmpty);
    });

    test('trailing slashes in the base path never double-slash the endpoint',
        () async {
      final captured = <http.Request>[];
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://8.8.8.8:8000/api///',
        timeout: const Duration(seconds: 30),
        client: MockClient((request) async {
          captured.add(request);
          return http.Response('{}', 500);
        }),
      );
      await expectLater(
        datasource.predictBatch([features]),
        throwsA(isA<PredictionException>()),
      );
      await expectLater(
        datasource.getModelInfo(),
        throwsA(isA<PredictionException>()),
      );
      await expectLater(
        datasource.getModelComparison(),
        throwsA(isA<PredictionException>()),
      );
      expect(
        captured.map((r) => r.url.toString()),
        <String>[
          'http://8.8.8.8:8000/api/predict/batch',
          'http://8.8.8.8:8000/api/model/info',
          'http://8.8.8.8:8000/api/model/comparison',
        ],
      );
      for (final request in captured) {
        expect(request.url.path, isNot(contains('//')));
      }
    });
  });

  group('PredictionException', () {
    test('has message and optional statusCode', () {
      final e = const PredictionException('failed', statusCode: 500);
      expect(e.message, 'failed');
      expect(e.statusCode, 500);
      expect(e.toString(), 'PredictionException: failed');

      final e2 = const PredictionException('no status');
      expect(e2.statusCode, isNull);
    });
  });

  group('ModelNotLoadedException', () {
    test('is const with message', () {
      final e = const ModelNotLoadedException();
      expect(e.toString(), contains('Model not loaded'));
    });
  });

  group('domain-base DNS resolve + IP pinning', () {
    test('domain base resolves and pins POST to resolved IP', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(
              {'prediction': 450000.0, 'model': 'xgb', 'model_version': '1.0'}),
          200,
        );
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://api.example.com:8000',
        timeout: const Duration(seconds: 5),
        client: client,
      );
      await datasource.predict(features);
      expect(captured, isNotNull);
      expect(captured!.url.host, '8.8.8.8');
      expect(captured!.url.port, 8000);
      expect(captured!.followRedirects, isFalse);
    });

    test('empty DNS result fails closed without sending a request', () async {
      var sent = 0;
      final client = MockClient((request) async {
        sent++;
        return http.Response('{}', 200);
      });
      validation.dnsLookup = (host) async => <InternetAddress>[];
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://api.example.com:8000',
        timeout: const Duration(seconds: 5),
        client: client,
      );
      await expectLater(
        datasource.predict(features),
        throwsA(isA<ArgumentError>()),
      );
      expect(sent, 0);
    });

    test('prefers IPv4 when DNS returns IPv6 and IPv4 addresses', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(
              {'prediction': 450000.0, 'model': 'xgb', 'model_version': '1.0'}),
          200,
        );
      });
      validation.dnsLookup = (host) async => <InternetAddress>[
            InternetAddress('2001:db8::1'),
            InternetAddress('8.8.8.8'),
          ];
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://api.example.com:8000',
        timeout: const Duration(seconds: 5),
        client: client,
      );
      await datasource.predict(features);
      expect(captured, isNotNull);
      // http bases pin the connection to the (IPv4-first) resolved address.
      expect(captured!.url.host, '8.8.8.8');
    });

    test('DNS timeout fails closed with ArgumentError', () async {
      final never = Completer<List<InternetAddress>>();
      validation.dnsLookup = (host) => never.future;
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://api.example.com:8000',
        timeout: const Duration(milliseconds: 50),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => datasource.predict(features),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('blocked resolved IP fails closed', () async {
      validation.dnsLookup =
          (host) async => <InternetAddress>[InternetAddress('169.254.169.254')];
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://api.example.com:8000',
        timeout: const Duration(seconds: 5),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => datasource.predict(features),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('DNS transport failure maps to ArgumentError (fail closed)', () async {
      validation.dnsLookup =
          (host) async => Future.error(const SocketException('offline'));
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://api.example.com:8000',
        timeout: const Duration(seconds: 5),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => datasource.predict(features),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('https base keeps the hostname (no IP pinning)', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(
              {'prediction': 450000.0, 'model': 'xgb', 'model_version': '1.0'}),
          200,
        );
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'https://api.example.com:8000',
        timeout: const Duration(seconds: 5),
        client: client,
      );
      await datasource.predict(features);
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
          jsonEncode(
              {'prediction': 450000.0, 'model': 'xgb', 'model_version': '1.0'}),
          200,
        );
      });
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://8.8.8.8:8000',
        timeout: const Duration(seconds: 5),
        baseUrlProvider: () => 'http://api.example.com:8000',
        client: client,
      );
      await datasource.predict(features);
      expect(captured, isNotNull);
      expect(captured!.url.host, '8.8.8.8');
      expect(captured!.url.port, 8000);
    });

    test('a blocked host from baseUrlProvider fails closed', () async {
      final datasource = PredictionRemoteDataSource(
        baseUrl: 'http://8.8.8.8:8000',
        timeout: const Duration(seconds: 5),
        baseUrlProvider: () => 'http://127.0.0.1:8000',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        datasource.predict(features),
        throwsA(isArgumentError),
      );
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
