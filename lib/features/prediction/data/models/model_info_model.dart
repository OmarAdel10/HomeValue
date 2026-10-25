import 'package:equatable/equatable.dart';
import '../../domain/entities/model_info.dart';

class ModelInfoModel extends Equatable {
  final String? model;
  final bool loaded;
  final List<String>? steps;

  const ModelInfoModel({
    this.model,
    required this.loaded,
    this.steps,
  });

  factory ModelInfoModel.fromEntity(ModelInfo entity) {
    return ModelInfoModel(
      model: entity.model,
      loaded: entity.loaded,
      steps: entity.steps,
    );
  }

  ModelInfo toEntity() {
    return ModelInfo(
      model: model,
      loaded: loaded,
      steps: steps,
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'loaded': loaded,
        'steps': steps,
      };

  factory ModelInfoModel.fromJson(Map<String, dynamic> json) {
    return ModelInfoModel(
      model: json['model'] as String?,
      loaded: json['loaded'] as bool,
      steps: (json['steps'] as List?)?.cast<String>(),
    );
  }

  @override
  List<Object?> get props => [model, loaded, steps];
}
