part of 'comparison_bloc.dart';

abstract class ComparisonEvent extends Equatable {
  const ComparisonEvent();

  @override
  List<Object?> get props => [];
}

class LoadComparison extends ComparisonEvent {
  const LoadComparison();
}

class RefreshComparison extends ComparisonEvent {
  const RefreshComparison();
}
