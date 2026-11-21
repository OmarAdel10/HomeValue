import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../../core/constants.dart';
import '../../../../core/validation.dart' as validation;
import '../models/model_comparison_model.dart';

class ComparisonRemoteDataSource {
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Duration _timeout;
  final String Function()? baseUrlProvider;

  ComparisonRemoteDataSource({
    http.Client? client,
    required String baseUrl,
    this.baseUrlProvider,
    Duration? timeout,
  })  : _client = client ?? IOClient(HttpClient()),
        _ownsClient = client == null,
        _timeout = timeout ?? AppConstants.predictionTimeout,
        _baseUrl = baseUrl {
    validation.assertAllowedHost(baseUrl);
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
  // Uses the injectable validation.dnsLookup seam so tests can stub DNS, and
  // applies the request deadline to resolution itself.
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
            _timeout,
            onTimeout: () => throw ArgumentError('DNS lookup timed out'),
          );
    } on SocketException {
      // DNS transport failure must fail closed as ArgumentError so callers
      // classify it as a blocked retrain (not a transport failure).
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

  Future<ModelComparisonModel> fetchModelComparison() async {
    validation.assertAllowedHost(baseUrl);
    final baseUri = Uri.parse(baseUrl);
    // Rebuild from components: string concatenation pushes the endpoint into
    // the query string for bases like 'http://host:8000?x=1' (GET lands on
    // '/' and the request silently fails), and Uri.replace(query: null)
    // keeps the existing query in Dart. A fresh Uri() drops query/fragment
    // and normalizes any number of trailing slashes in the base path.
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    final requestUri = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.port == 0 ? null : baseUri.port,
      path: '$basePath${AppConstants.modelComparisonEndpoint}',
    );
    final resolvedHost = await _resolveAndValidateHost(requestUri.host);
    // https keeps the original hostname so TLS SNI and certificate-name
    // verification use the domain certificate; http pins to the validated IP
    // so the client cannot re-resolve to a private address (DNS rebinding).
    final uri = requestUri.scheme == 'https'
        ? requestUri
        : requestUri.replace(host: resolvedHost);
    // Explicit request with redirects disabled: package:http follows 3xx by
    // default, which would contact a redirect target before rejectRedirect
    // could see it (redirect-based SSRF).
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(_timeout);

    validation.rejectRedirect(response);
    if (response.statusCode == 200) {
      return ModelComparisonModel.fromJson(response.body);
    } else {
      throw Exception(
          'Failed to load model comparison: ${response.statusCode}');
    }
  }
}
