import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/prediction_result.dart';
import '../../domain/repositories/prediction_repository.dart'
    as repo; // Domain ModelComparison
import 'prediction_event.dart';
import 'prediction_state.dart';

class PredictionBloc extends Bloc<PredictionEvent, PredictionState> {
  final repo.PredictionRepository repository;

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
      final predictions = await repository.predictBatch(event.features);
      if (predictions.isEmpty) {
        emit(const PredictionFailure('No features provided for batch prediction'));
        return;
      }
      final results = predictions
          .map((p) => PredictionResult(
                prediction: p,
                model: 'best_model.joblib',
                modelVersion: '1.0.0',
              ))
          .toList();
      emit(BatchPredictionSuccess(results));
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
    try {
      final domainModels = await repository.getModelComparison();
      final models = domainModels
          .map((m) => ModelComparison(
                model: m.model,
                rmse: m.rmse,
                mae: m.mae,
                r2: m.r2,
                cvRmse: m.cvRmse,
                cvRmseStd: m.cvRmseStd,
              ))
          .toList();
      emit(ModelComparisonLoaded(models));
    } catch (e) {
      emit(PredictionFailure(e.toString()));
    }
  }
}
