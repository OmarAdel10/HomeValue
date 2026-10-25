import 'package:home_value/features/comparison/domain/entities/model_comparison.dart';
import 'dart:convert';

class ModelMetricModel extends ModelMetric {
  const ModelMetricModel({
    required super.name,
    required super.rmse,
    required super.mae,
    required super.r2,
    required super.cvStd,
    required super.isBest,
  });

  factory ModelMetricModel.fromJson(Map<String, dynamic> json) {
    return ModelMetricModel(
      name: json['model_name'] as String? ?? json['name'] as String,
      rmse: (json['rmse'] as num?)?.toDouble() ?? 0.0,
      mae: (json['mae'] as num?)?.toDouble() ?? 0.0,
      r2: (json['r2'] as num?)?.toDouble() ?? 0.0,
      cvStd: (json['cv_std'] as num?)?.toDouble() ?? 0.0,
      isBest: json['is_best'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'model_name': name,
        'rmse': rmse,
        'mae': mae,
        'r2': r2,
        'cv_std': cvStd,
        'is_best': isBest,
      };

  ModelMetric toEntity() => ModelMetric(
        name: name,
        rmse: rmse,
        mae: mae,
        r2: r2,
        cvStd: cvStd,
        isBest: isBest,
      );
}

class ModelComparisonModel extends ModelComparison {
  const ModelComparisonModel({required super.metrics});

  factory ModelComparisonModel.fromJson(String jsonString) {
    final List<dynamic> jsonList = json.decode(jsonString);
    final metrics = jsonList
        .map((e) => ModelMetricModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return ModelComparisonModel(metrics: metrics);
  }

  Map<String, dynamic> toJson() => {
        'metrics':
            metrics.map((e) => (e as ModelMetricModel).toJson()).toList(),
      };

  ModelComparison toEntity() => ModelComparison(
        metrics:
            metrics.map((e) => (e as ModelMetricModel).toEntity()).toList(),
      );
}
