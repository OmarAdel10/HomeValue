import '../../domain/repositories/prediction_repository.dart';
import '../../domain/entities/house_features.dart';
import '../../domain/entities/prediction_result.dart';
import '../../domain/entities/model_info.dart';
import '../datasources/prediction_remote_datasource.dart';

class PredictionRepositoryImpl implements PredictionRepository {
  final PredictionRemoteDataSource remoteDataSource;

  PredictionRepositoryImpl({required this.remoteDataSource});

  @override
  Future<PredictionResult> predict(HouseFeatures features) async {
    return await remoteDataSource.predict(features);
  }

  @override
  Future<List<double>> predictBatch(List<HouseFeatures> features) async {
    return await remoteDataSource.predictBatch(features);
  }

  @override
  Future<ModelInfo> getModelInfo() async {
    return await remoteDataSource.getModelInfo();
  }

  @override
  Future<List<ModelComparison>> getModelComparison() async {
    return await remoteDataSource.getModelComparison();
  }
}