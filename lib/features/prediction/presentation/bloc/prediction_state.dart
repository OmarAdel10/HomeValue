import 'package:equatable/equatable.dart';

import '../../domain/entities/house_features.dart';
import '../../domain/entities/prediction_result.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/repositories/prediction_repository.dart';

abstract class PredictionState extends Equatable {
  const PredictionState();

  @override
  List<Object?> get props => [];
}

class PredictionInitial extends PredictionState {
  const PredictionInitial();
}

class PredictionLoading extends PredictionState {
  const PredictionLoading();
}

class PredictionSuccess extends PredictionState {
  final PredictionResult result;

  const PredictionSuccess(this.result);

  @override
  List<Object?> get props => [result];
}

class PredictionFailure extends PredictionState {
  final String message;

  const PredictionFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class ModelInfoLoaded extends PredictionState {
  final ModelInfo modelInfo;

  const ModelInfoLoaded(this.modelInfo);

  @override
  List<Object?> get props => [modelInfo];
}

class ModelComparisonLoaded extends PredictionState {
  final List<ModelComparison> models;

  const ModelComparisonLoaded(this.models);

  @override
  List<Object?> get props => [models];
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
}
