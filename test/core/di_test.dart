import 'package:flutter_test/flutter_test.dart';
import 'package:home_value/core/di.dart';
import 'package:home_value/features/comparison/presentation/bloc/comparison_bloc.dart';
import 'package:home_value/features/comparison/domain/repositories/comparison_repository.dart';
import 'package:home_value/features/prediction/domain/repositories/prediction_repository.dart';
import 'package:home_value/features/prediction/presentation/bloc/prediction_bloc.dart';
import 'package:home_value/features/settings/domain/repositories/settings_repository.dart';
import 'package:home_value/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    await initDependencies();
  });

  tearDown(() async {
    await sl.reset();
  });

  test('initDependencies resolves every repository and BLoC', () {
    expect(sl<PredictionRepository>(), isA<PredictionRepository>());
    expect(sl<SettingsRepository>(), isA<SettingsRepository>());
    expect(sl<ComparisonRepository>(), isA<ComparisonRepository>());
    expect(sl<PredictionBloc>(), isA<PredictionBloc>());
    expect(sl<SettingsBloc>(), isA<SettingsBloc>());
    expect(sl<ComparisonBloc>(), isA<ComparisonBloc>());
  });

  test('BLoCs are factory-scoped', () {
    expect(identical(sl<PredictionBloc>(), sl<PredictionBloc>()), isFalse);
    expect(identical(sl<SettingsBloc>(), sl<SettingsBloc>()), isFalse);
    expect(identical(sl<ComparisonBloc>(), sl<ComparisonBloc>()), isFalse);
  });
}
