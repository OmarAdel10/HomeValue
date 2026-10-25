import '../../../../core/constants.dart';
import '../models/model_comparison_model.dart';
import 'package:http/http.dart' as http;

class ComparisonRemoteDataSource {
  final http.Client client;
  final String _baseUrl;
  final String Function()? baseUrlProvider;

  ComparisonRemoteDataSource({
    required this.client,
    required String baseUrl,
    this.baseUrlProvider,
  }) : _baseUrl = baseUrl;

  String get baseUrl => baseUrlProvider?.call() ?? _baseUrl;

  Future<ModelComparisonModel> fetchModelComparison() async {
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
