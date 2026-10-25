import 'package:equatable/equatable.dart';

import '../../domain/entities/house_features.dart';
import '../../domain/entities/prediction_result.dart';

abstract class PredictionEvent extends Equatable {
  const PredictionEvent();

  @override
  List<Object?> get props => [];
}

class PredictRequested extends PredictionEvent {
  final HouseFeatures features;

  const PredictRequested(this.features);

  @override
  List<Object?> get props => [features];
}

class PredictBatchRequested extends PredictionEvent {
  final List<HouseFeatures> features;

  const PredictBatchRequested(this.features);

  @override
  List<Object?> get props => [features];
}

class ModelChanged extends PredictionEvent {
  final String modelName;

  const ModelChanged(this.modelName);

  @override
  List<Object?> get props => [modelName];
}

class FormFieldChanged extends PredictionEvent {
  final String field;
  final dynamic value;

  const FormFieldChanged({
    required this.field,
    required this.value,
  });

  @override
  List<Object?> get props => [field, value];
}

class LoadModelInfo extends PredictionEvent {
  const LoadModelInfo();

  @override
  List<Object?> get props => [];
}

class LoadModelComparison extends PredictionEvent {
  const LoadModelComparison();

  @override
  List<Object?> get props => [];
}
