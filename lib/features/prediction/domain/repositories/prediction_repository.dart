import 'package:equatable/equatable.dart';

import '../entities/house_features.dart';
import '../entities/prediction_result.dart';
import '../entities/model_info.dart';

abstract class PredictionRepository {
  Future<PredictionResult> predict(HouseFeatures features);

  Future<List<double>> predictBatch(List<HouseFeatures> features);

  Future<ModelInfo> getModelInfo();

  Future<List<ModelComparison>> getModelComparison();
}

class ModelComparison extends Equatable {
  final String model;
  final double rmse;
  final double mae;
  final double r2;
  final double cvRmse;
  final double cvRmseStd;

  const ModelComparison({
    required this.model,
    required this.rmse,
    required this.mae,
    required this.r2,
    required this.cvRmse,
    required this.cvRmseStd,
  });

  @override
  List<Object?> get props => [model, rmse, mae, r2, cvRmse, cvRmseStd];

  factory ModelComparison.fromJson(Map<String, dynamic> json) {
    return ModelComparison(
      model: json['model'] as String,
      rmse: (json['rmse'] as num).toDouble(),
      mae: (json['mae'] as num).toDouble(),
      r2: (json['r2'] as num).toDouble(),
      cvRmse: (json['cv_rmse'] as num).toDouble(),
      cvRmseStd: (json['cv_rmse_std'] as num).toDouble(),
    );
  }
}
