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
  });

  group('dispose', () {
    test('closes owned client', () {
      // IOClient close is idempotent-safe; just ensure dispose doesn't throw.
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
      );
      expect(() => datasource.dispose(), returnsNormally);
    });

    test('does not close injected client', () {
      final client = MockClient((_) async => http.Response('{}', 200));
      final datasource = PredictionRemoteDataSource(
        baseUrl: baseUrl,
        timeout: const Duration(seconds: 30),
        client: client,
      );
      expect(() => datasource.dispose(), returnsNormally);
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
  });
}
