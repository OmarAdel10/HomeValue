import 'package:home_value/core/constants.dart';
import 'package:home_value/features/comparison/data/models/model_comparison_model.dart';
import 'package:home_value/features/comparison/domain/entities/model_comparison.dart';
import 'package:http/http.dart' as http;

class ComparisonRemoteDataSource {
  final http.Client client;
  final String baseUrl;

  ComparisonRemoteDataSource({required this.client, required this.baseUrl});

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
