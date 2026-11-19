import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../../core/constants.dart';
import '../../../../core/validation.dart' as validation;
import '../../domain/entities/house_features.dart';
import '../../domain/entities/prediction_result.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/repositories/prediction_repository.dart';

class PredictionRemoteDataSource implements PredictionRepository {
  final String baseUrl;
  final Duration timeout;
  final String Function()? baseUrlProvider;
  final http.Client _client;
  final bool _ownsClient;

  PredictionRemoteDataSource({
    required this.baseUrl,
    required this.timeout,
    this.baseUrlProvider,
    http.Client? client,
  })  : _client = client ?? IOClient(HttpClient()),
        _ownsClient = client == null {
    validation.assertAllowedHost(baseUrl);
  }

  String get _base => baseUrlProvider?.call() ?? baseUrl;

  // Resolve DNS at request time, re-validate every resolved IP, and return
  // the first validated IP to pin the connection (prevents DNS rebinding TOCTOU
  // where validation passes on one IP but the client connects to another).
  Future<String> _resolveAndValidateHost(String host) async {
    final resolved = InternetAddress.tryParse(host);
    if (resolved != null) {
      if (!validation.isAllowedHost(resolved.address)) {
        throw ArgumentError('Resolved host is blocked: SSRF protection');
      }
      return resolved.address.split('%').first;
    }
    final List<InternetAddress> addresses;
    try {
      addresses = await validation.dnsLookup(host).timeout(
            timeout,
            onTimeout: () => throw ArgumentError('DNS lookup timed out'),
          );
    } on SocketException {
      // DNS transport failure must fail closed as ArgumentError so callers
      // classify it as a blocked request (not a transport failure).
      throw ArgumentError('DNS lookup failed');
    }
    if (addresses.isEmpty) {
      throw ArgumentError('DNS resolution returned no addresses');
    }
    final validated = <InternetAddress>[];
    for (final address in addresses) {
      if (!validation.isAllowedHost(address.address)) {
        throw ArgumentError('Resolved host is blocked: SSRF protection');
      }
      validated.add(address);
    }
    // Prefer IPv4 so an unreachable IPv6 address does not strand requests.
    validated.sort((a, b) {
      final aV4 = a.type == InternetAddressType.IPv4;
      final bV4 = b.type == InternetAddressType.IPv4;
      if (aV4 != bV4) return aV4 ? -1 : 1;
      return 0;
    });
    return validated.first.address.split('%').first;
  }

  /// Sends an explicitly-constructed request with redirects disabled.
  /// package:http follows 3xx by default, which would contact a redirect
  /// target before rejectRedirect could see it (redirect-based SSRF).
  Future<http.Response> _send(http.Request request, Duration t) {
    return _client.send(request).then(http.Response.fromStream).timeout(t);
  }

  /// https keeps the original hostname so TLS SNI and certificate-name
  /// verification use the domain certificate; http pins to the validated IP
  /// so the client cannot re-resolve to a private address (DNS rebinding).
  /// Rebuilt from components so a foreign query/fragment on the configured
  /// base URL (Uri.replace keeps query: null in Dart) can never leak into a
  /// request URL.
  Uri _pinnedUri(Uri baseUri, String resolvedHost, String path) {
    final rebuilt = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.port == 0 ? null : baseUri.port,
      path: path,
    );
    return baseUri.scheme == 'https'
        ? rebuilt
        : rebuilt.replace(host: resolvedHost);
  }

  /// Joins the base path and endpoint without producing double slashes,
  /// regardless of how many trailing slashes the configured base URL has.
  String _endpointPath(Uri baseUri, String endpoint) {
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    return '$basePath$endpoint';
  }

  @override
  Future<PredictionResult> predict(HouseFeatures features) async {
    final base = _base;
    validation.assertAllowedHost(base);
    final baseUri = Uri.parse(base);
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = _pinnedUri(baseUri, resolvedHost,
        _endpointPath(baseUri, AppConstants.predictEndpoint));
    final body = jsonEncode(features.toJson());

    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..body = body;
    final response = await _send(request, timeout);

    validation.rejectRedirect(response);
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
    final base = _base;
    validation.assertAllowedHost(base);
    final baseUri = Uri.parse(base);
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = _pinnedUri(baseUri, resolvedHost,
        _endpointPath(baseUri, AppConstants.predictBatchEndpoint));
    final body = jsonEncode({
      'features': features.map((f) => f.toJson()).toList(),
    });

    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..body = body;
    final response = await _send(request, timeout);

    validation.rejectRedirect(response);
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
    final base = _base;
    validation.assertAllowedHost(base);
    final baseUri = Uri.parse(base);
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = _pinnedUri(baseUri, resolvedHost,
        _endpointPath(baseUri, AppConstants.modelInfoEndpoint));

    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _send(request, timeout);

    validation.rejectRedirect(response);
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
    final base = _base;
    validation.assertAllowedHost(base);
    final baseUri = Uri.parse(base);
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = _pinnedUri(baseUri, resolvedHost,
        _endpointPath(baseUri, AppConstants.modelComparisonEndpoint));

    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _send(request, timeout);

    validation.rejectRedirect(response);
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
    if (_ownsClient) {
      _client.close();
    }
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
