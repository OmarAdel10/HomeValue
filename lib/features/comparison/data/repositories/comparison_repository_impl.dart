import '../datasources/comparison_remote_datasource.dart';
import '../../domain/entities/model_comparison.dart';
import '../../domain/repositories/comparison_repository.dart';

class ComparisonRepositoryImpl implements ComparisonRepository {
  final ComparisonRemoteDataSource remoteDataSource;

  ComparisonRepositoryImpl({required this.remoteDataSource});

  @override
  Future<ModelComparison> getModelComparison() async {
    final model = await remoteDataSource.fetchModelComparison();
    return model.toEntity();
  }
}
