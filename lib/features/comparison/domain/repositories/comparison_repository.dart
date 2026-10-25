import '../entities/model_comparison.dart';

abstract class ComparisonRepository {
  Future<ModelComparison> getModelComparison();
}
