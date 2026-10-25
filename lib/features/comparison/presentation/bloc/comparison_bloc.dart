library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../domain/entities/model_comparison.dart';
import '../../domain/repositories/comparison_repository.dart';
part 'comparison_event.dart';
part 'comparison_state.dart';

class ComparisonBloc extends Bloc<ComparisonEvent, ComparisonState> {
  final ComparisonRepository repository;

  ComparisonBloc({required this.repository})
      : super(const ComparisonInitial()) {
    on<LoadComparison>(_onLoadComparison);
    on<RefreshComparison>(_onRefreshComparison);
  }

  Future<void> _onLoadComparison(
    LoadComparison event,
    Emitter<ComparisonState> emit,
  ) async {
    emit(const ComparisonLoading());
    try {
      final comparison = await repository.getModelComparison();
      emit(ComparisonLoaded(comparison));
    } catch (e) {
      emit(ComparisonFailure(e.toString()));
    }
  }

  Future<void> _onRefreshComparison(
    RefreshComparison event,
    Emitter<ComparisonState> emit,
  ) async {
    try {
      final comparison = await repository.getModelComparison();
      emit(ComparisonLoaded(comparison));
    } catch (e) {
      emit(ComparisonFailure(e.toString()));
    }
  }
}
