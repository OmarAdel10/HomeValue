import 'package:equatable/equatable.dart';
import '../../domain/entities/prediction_result.dart';

class PredictionResultModel extends Equatable {
  final double prediction;
  final String model;
  final String modelVersion;

  const PredictionResultModel({
    required this.prediction,
    required this.model,
    required this.modelVersion,
  });

  factory PredictionResultModel.fromEntity(PredictionResult entity) {
    return PredictionResultModel(
      prediction: entity.prediction,
      model: entity.model,
      modelVersion: entity.modelVersion,
    );
  }

  PredictionResult toEntity() {
    return PredictionResult(
      prediction: prediction,
      model: model,
      modelVersion: modelVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'prediction': prediction,
        'model': model,
        'model_version': modelVersion,
      };

  factory PredictionResultModel.fromJson(Map<String, dynamic> json) {
    return PredictionResultModel(
      prediction: (json['prediction'] as num).toDouble(),
      model: json['model'] as String,
      modelVersion: json['model_version'] as String,
    );
  }

  @override
  List<Object?> get props => [prediction, model, modelVersion];
}