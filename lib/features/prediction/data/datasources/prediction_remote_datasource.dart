import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/constants.dart';
import '../../../../core/validation.dart';
import '../../domain/entities/house_features.dart';
import '../../domain/entities/prediction_result.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/repositories/prediction_repository.dart';

class PredictionRemoteDataSource implements PredictionRepository {
  final String baseUrl;
  final Duration timeout;
  final String Function()? baseUrlProvider;
  final http.Client _client;

  PredictionRemoteDataSource({
    required this.baseUrl,
    required this.timeout,
    this.baseUrlProvider,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    assertAllowedHost(baseUrl);
  }

  String get _base => baseUrlProvider?.call() ?? baseUrl;

  // Resolve DNS at request time, re-validate every resolved IP, and return
  // the first validated IP to pin the connection (prevents DNS rebinding TOCTOU
  // where validation passes on one IP but the client connects to another).
  Future<String> _resolveAndValidateHost(String host) async {
    final resolved = InternetAddress.tryParse(host);
    if (resolved != null) {
      if (!isAllowedHost(resolved.address)) {
        throw ArgumentError('Resolved host is blocked: SSRF protection');
      }
      return resolved.address;
    }
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      throw ArgumentError('DNS resolution returned no addresses');
    }
    String? firstValidated;
    for (final address in addresses) {
      if (!isAllowedHost(address.address)) {
        throw ArgumentError('Resolved host is blocked: SSRF protection');
      }
      firstValidated ??= address.address;
    }
    return firstValidated!;
  }

  @override
  Future<PredictionResult> predict(HouseFeatures features) async {
    assertAllowedHost(_base);
    final baseUri = Uri.parse(_base);
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = baseUri.replace(
        host: resolvedHost,
        path: '${baseUri.path}${AppConstants.predictEndpoint}');
    final body = jsonEncode(features.toJson());

    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(timeout);

    rejectRedirect(response);
    if (response.statusCode == 200) {
      return PredictionResult.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 503) {
      throw const ModelNotLoadedException();
    } else {
      throw PredictionException(
        'Prediction failed: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<List<double>> predictBatch(List<HouseFeatures> features) async {
    assertAllowedHost(_base);
    final baseUri = Uri.parse(_base);
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = baseUri.replace(
        host: resolvedHost,
        path: '${baseUri.path}${AppConstants.predictBatchEndpoint}');
    final body = jsonEncode({
      'features': features.map((f) => f.toJson()).toList(),
    });

    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(timeout);

    rejectRedirect(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['predictions'] as List)
          .map((p) => (p as num).toDouble())
          .toList();
    } else if (response.statusCode == 503) {
      throw const ModelNotLoadedException();
    } else {
      throw PredictionException(
        'Batch prediction failed: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<ModelInfo> getModelInfo() async {
    assertAllowedHost(_base);
    final baseUri = Uri.parse(_base);
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = baseUri.replace(
        host: resolvedHost,
        path: '${baseUri.path}${AppConstants.modelInfoEndpoint}');

    final response = await _client.get(uri).timeout(timeout);

    rejectRedirect(response);
    if (response.statusCode == 200) {
      return ModelInfo.fromJson(jsonDecode(response.body));
    } else {
      throw PredictionException(
        'Failed to get model info: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<List<ModelComparison>> getModelComparison() async {
    assertAllowedHost(_base);
    final baseUri = Uri.parse(_base);
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = baseUri.replace(
        host: resolvedHost,
        path: '${baseUri.path}${AppConstants.modelComparisonEndpoint}');

    final response = await _client.get(uri).timeout(timeout);

    rejectRedirect(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final models = (data['models'] as List)
          .map((m) => ModelComparison.fromJson(m))
          .toList();
      return models;
    } else {
      throw PredictionException(
        'Failed to get model comparison: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

class PredictionException implements Exception {
  final String message;
  final int? statusCode;

  const PredictionException(this.message, {this.statusCode});

  @override
  String toString() => 'PredictionException: $message';
}

class ModelNotLoadedException implements Exception {
  const ModelNotLoadedException();

  @override
  String toString() =>
      'ModelNotLoadedException: Model not loaded. Train a model first.';
}
