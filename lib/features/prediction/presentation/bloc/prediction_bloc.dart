import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/prediction_result.dart';
import '../../domain/repositories/prediction_repository.dart';
import 'prediction_event.dart';
import 'prediction_state.dart';

class PredictionBloc extends Bloc<PredictionEvent, PredictionState> {
  final PredictionRepository repository;

  PredictionBloc({required this.repository})
      : super(const PredictionInitial()) {
    on<PredictRequested>(_onPredictRequested);
    on<PredictBatchRequested>(_onPredictBatchRequested);
    on<ModelChanged>(_onModelChanged);
    on<FormFieldChanged>(_onFormFieldChanged);
    on<LoadModelInfo>(_onLoadModelInfo);
    on<LoadModelComparison>(_onLoadModelComparison);
  }

  Future<void> _onPredictRequested(
    PredictRequested event,
    Emitter<PredictionState> emit,
  ) async {
    emit(const PredictionLoading());
    try {
      final result = await repository.predict(event.features);
      emit(PredictionSuccess(result));
    } catch (e) {
      emit(PredictionFailure(e.toString()));
    }
  }

  Future<void> _onPredictBatchRequested(
    PredictBatchRequested event,
    Emitter<PredictionState> emit,
  ) async {
    emit(const PredictionLoading());
    try {
      await repository.predictBatch(event.features);
      // For batch, we emit the first prediction as success
      if (event.features.isNotEmpty) {
        // Note: Batch prediction returns list of doubles, not full PredictionResult
        // We'll create a dummy result for the first prediction
        emit(PredictionSuccess(
          PredictionResult(
            prediction: event.features.isNotEmpty ? 0.0 : 0.0,
            model: 'batch',
            modelVersion: '1.0.0',
          ),
        ));
      } else {
        emit(const PredictionFailure(
            'No features provided for batch prediction'));
      }
    } catch (e) {
      emit(PredictionFailure(e.toString()));
    }
  }

  Future<void> _onModelChanged(
    ModelChanged event,
    Emitter<PredictionState> emit,
  ) async {
    // Model change would require re-training or switching models
    // For now, just emit success with note
    emit(const PredictionFailure('Model switching not implemented yet'));
  }

  Future<void> _onFormFieldChanged(
    FormFieldChanged event,
    Emitter<PredictionState> emit,
  ) async {
    // Form field changes are handled by the UI directly
    // This is just a placeholder for any side effects
  }

  Future<void> _onLoadModelInfo(
    LoadModelInfo event,
    Emitter<PredictionState> emit,
  ) async {
    try {
      final modelInfo = await repository.getModelInfo();
      emit(ModelInfoLoaded(modelInfo));
    } catch (e) {
      emit(PredictionFailure(e.toString()));
    }
  }

  Future<void> _onLoadModelComparison(
    LoadModelComparison event,
    Emitter<PredictionState> emit,
  ) async {
    // Not implemented yet
    emit(const ModelComparisonLoaded([]));
  }
}
