import 'package:home_value/features/comparison/domain/entities/model_comparison.dart';

abstract class ComparisonRepository {
  Future<ModelComparison> getModelComparison();
}
