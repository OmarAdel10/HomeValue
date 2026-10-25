import 'package:home_value/features/comparison/data/datasources/comparison_remote_datasource.dart';
import 'package:home_value/features/comparison/data/models/model_comparison_model.dart';
import 'package:home_value/features/comparison/domain/entities/model_comparison.dart';
import 'package:home_value/features/comparison/domain/repositories/comparison_repository.dart';

class ComparisonRepositoryImpl implements ComparisonRepository {
  final ComparisonRemoteDataSource remoteDataSource;

  ComparisonRepositoryImpl({required this.remoteDataSource});

  @override
  Future<ModelComparison> getModelComparison() async {
    final model = await remoteDataSource.fetchModelComparison();
    return model.toEntity();
  }
}
