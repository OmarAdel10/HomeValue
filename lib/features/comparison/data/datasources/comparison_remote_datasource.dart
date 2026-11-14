import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/constants.dart';
import '../../../../core/validation.dart';
import '../models/model_comparison_model.dart';

class ComparisonRemoteDataSource {
  final http.Client client;
  final String _baseUrl;
  final String Function()? baseUrlProvider;

  ComparisonRemoteDataSource({
    required this.client,
    required String baseUrl,
    this.baseUrlProvider,
  }) : _baseUrl = baseUrl {
    _assertAllowedHost(baseUrl);
  }

  String get baseUrl => baseUrlProvider?.call() ?? _baseUrl;

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
      return;
    }
    if (!isAllowedHost(resolved.address)) {
      throw ArgumentError('Resolved host is blocked: SSRF protection');
    }
  }

  Future<ModelComparisonModel> fetchModelComparison() async {
    _assertAllowedHost(baseUrl);
    final uri = Uri.parse('$baseUrl${AppConstants.modelComparisonEndpoint}');
    final response = await client.get(uri);

    if (response.statusCode == 200) {
      return ModelComparisonModel.fromJson(response.body);
    } else {
      throw Exception(
          'Failed to load model comparison: ${response.statusCode}');
    }
  }
}
