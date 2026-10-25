import 'package:equatable/equatable.dart';

class ModelMetric extends Equatable {
  final String name;
  final double rmse;
  final double mae;
  final double r2;
  final double cvStd;
  final bool isBest;

  const ModelMetric({
    required this.name,
    required this.rmse,
    required this.mae,
    required this.r2,
    required this.cvStd,
    required this.isBest,
  });

  @override
  List<Object?> get props => [name, rmse, mae, r2, cvStd, isBest];
}

class ModelComparison extends Equatable {
  final List<ModelMetric> metrics;

  const ModelComparison({required this.metrics});

  ModelMetric get bestModel =>
      metrics.firstWhere((m) => m.isBest, orElse: () => metrics.first);

  @override
  List<Object?> get props => [metrics];
}
