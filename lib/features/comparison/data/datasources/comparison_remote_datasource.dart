import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../../core/constants.dart';
import '../../../../core/validation.dart';
import '../models/model_comparison_model.dart';

class ComparisonRemoteDataSource {
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final String Function()? baseUrlProvider;

  ComparisonRemoteDataSource({
    http.Client? client,
    required String baseUrl,
    this.baseUrlProvider,
  })  : _client = client ?? IOClient(HttpClient()),
        _ownsClient = client == null,
        _baseUrl = baseUrl {
    assertAllowedHost(baseUrl);
  }

  String get baseUrl => baseUrlProvider?.call() ?? _baseUrl;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  // Resolve DNS at request time, re-validate every resolved IP, and return
  // the first validated IP to pin the connection (prevents DNS rebinding TOCTOU
  // where validation passes on one IP but the client connects to another).
  Future<String> _resolveAndValidateHost(String host) async {
    final resolved = InternetAddress.tryParse(host);
    if (resolved != null) {
      if (!isAllowedHost(resolved.address)) {
        throw ArgumentError('Resolved host is blocked: SSRF protection');
      }
      return resolved.address.split('%').first;
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
      firstValidated ??= address.address.split('%').first;
    }
    return firstValidated!;
  }

  Future<ModelComparisonModel> fetchModelComparison() async {
    assertAllowedHost(baseUrl);
    final baseUri =
        Uri.parse('$baseUrl${AppConstants.modelComparisonEndpoint}');
    final resolvedHost = await _resolveAndValidateHost(baseUri.host);
    final uri = baseUri.replace(host: resolvedHost);
    final response = await _client.get(uri).timeout(AppConstants.apiTimeout);

    rejectRedirect(response);
    if (response.statusCode == 200) {
      return ModelComparisonModel.fromJson(response.body);
    } else {
      throw Exception(
          'Failed to load model comparison: ${response.statusCode}');
    }
  }
}
