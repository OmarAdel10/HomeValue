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
    _assertAllowedHost(baseUrl);
  }

  String get _base => baseUrlProvider?.call() ?? baseUrl;

  void _assertAllowedHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) {
      throw ArgumentError('Invalid base URL');
    }
    if (!isAllowedHost(uri.host)) {
      throw ArgumentError('Blocked host: SSRF protection');
    }
    _resolveAndValidateHost(uri.host);
  }

  void _resolveAndValidateHost(String host) {
    final resolved = InternetAddress.tryParse(host);
    if (resolved == null) {
      return; // Domain name: allowlisted by validateServerUrl; DNS rebinding
      // protection is at the HTTP client / network layer outside this
      // datasource's scope for non-literal hosts.
    }
    if (!isAllowedHost(resolved.address)) {
      throw ArgumentError('Resolved host is blocked: SSRF protection');
    }
  }

  @override
  Future<PredictionResult> predict(HouseFeatures features) async {
    _assertAllowedHost(_base);
    final uri = Uri.parse('$_base${AppConstants.predictEndpoint}');
    final body = jsonEncode(features.toJson());

    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(timeout);

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
    _assertAllowedHost(_base);
    final uri = Uri.parse('$_base${AppConstants.predictBatchEndpoint}');
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
    _assertAllowedHost(_base);
    final uri = Uri.parse('$_base${AppConstants.modelInfoEndpoint}');

    final response = await _client.get(uri).timeout(timeout);

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
    _assertAllowedHost(_base);
    final uri = Uri.parse('$_base${AppConstants.modelComparisonEndpoint}');

    final response = await _client.get(uri).timeout(timeout);

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
