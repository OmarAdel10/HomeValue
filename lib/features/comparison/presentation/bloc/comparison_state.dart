part of 'comparison_bloc.dart';

abstract class ComparisonState extends Equatable {
  const ComparisonState();

  @override
  List<Object?> get props => [];
}

class ComparisonInitial extends ComparisonState {
  const ComparisonInitial();
}

class ComparisonLoading extends ComparisonState {
  const ComparisonLoading();
}

class ComparisonLoaded extends ComparisonState {
  final ModelComparison comparison;

  const ComparisonLoaded(this.comparison);

  @override
  List<Object?> get props => [comparison];
}

class ComparisonFailure extends ComparisonState {
  final String message;

  const ComparisonFailure(this.message);

  @override
  List<Object?> get props => [message];
}
