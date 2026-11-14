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
    assertAllowedHost(baseUrl);
  }

  String get baseUrl => baseUrlProvider?.call() ?? _baseUrl;

  // Resolve DNS at request time and re-validate every resolved IP to
  // prevent DNS rebinding TOCTOU for domain-name hosts.
  Future<void> _resolveAndValidateHost(String host) async {
    final resolved = InternetAddress.tryParse(host);
    if (resolved == null) {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) {
        throw ArgumentError('DNS resolution returned no addresses');
      }
      for (final address in addresses) {
        if (!isAllowedHost(address.address)) {
          throw ArgumentError('Resolved host is blocked: SSRF protection');
        }
      }
      return;
    }
    if (!isAllowedHost(resolved.address)) {
      throw ArgumentError('Resolved host is blocked: SSRF protection');
    }
  }

  Future<ModelComparisonModel> fetchModelComparison() async {
    assertAllowedHost(baseUrl);
    final uri = Uri.parse('$baseUrl${AppConstants.modelComparisonEndpoint}');
    await _resolveAndValidateHost(uri.host);
    final response = await client.get(uri).timeout(AppConstants.apiTimeout);

    rejectRedirect(response);
    if (response.statusCode == 200) {
      return ModelComparisonModel.fromJson(response.body);
    } else {
      throw Exception(
          'Failed to load model comparison: ${response.statusCode}');
    }
  }
}
