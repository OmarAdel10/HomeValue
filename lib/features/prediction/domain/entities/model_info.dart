import 'package:equatable/equatable.dart';

class ModelInfo extends Equatable {
  final String? model;
  final bool loaded;
  final List<String>? steps;

  const ModelInfo({
    this.model,
    required this.loaded,
    this.steps,
  });

  @override
  List<Object?> get props => [model, loaded, steps];

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      model: json['model'] as String?,
      loaded: json['loaded'] as bool,
      steps: (json['steps'] as List?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'loaded': loaded,
        'steps': steps,
      };
}