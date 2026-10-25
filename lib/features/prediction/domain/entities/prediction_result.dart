import 'package:equatable/equatable.dart';

class PredictionResult extends Equatable {
  final double prediction;
  final String model;
  final String modelVersion;

  const PredictionResult({
    required this.prediction,
    required this.model,
    required this.modelVersion,
  });

  @override
  List<Object?> get props => [prediction, model, modelVersion];

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      prediction: (json['prediction'] as num).toDouble(),
      model: json['model'] as String,
      modelVersion: json['model_version'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'prediction': prediction,
        'model': model,
        'model_version': modelVersion,
      };
}
