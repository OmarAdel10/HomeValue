import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:home_value/features/comparison/data/datasources/comparison_remote_datasource.dart';
import 'package:home_value/features/comparison/data/models/model_comparison_model.dart';

void main() {
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
      final client = MockClient((_) async => http.Response('', 302));
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
}
