import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_value/core/di.dart';
import 'package:home_value/core/validation.dart' as validation;
import 'package:home_value/features/comparison/data/datasources/comparison_remote_datasource.dart';
import 'package:home_value/features/comparison/presentation/bloc/comparison_bloc.dart';
import 'package:home_value/features/comparison/domain/repositories/comparison_repository.dart';
import 'package:home_value/features/prediction/data/datasources/prediction_remote_datasource.dart';
import 'package:home_value/features/prediction/domain/repositories/prediction_repository.dart';
import 'package:home_value/features/prediction/presentation/bloc/prediction_bloc.dart';
import 'package:home_value/features/settings/data/datasources/settings_local_datasource.dart';
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

  test('datasource baseUrlProviders resolve the live server URL', () async {
    // Allow the persist-time DNS validation to run offline.
    final originalLookup = validation.dnsLookup;
    validation.dnsLookup =
        (host) async => <InternetAddress>[InternetAddress('8.8.8.8')];
    addTearDown(() => validation.dnsLookup = originalLookup);

    const newUrl = 'http://api.example.com:9000';
    await sl<SettingsLocalDataSource>().updateServerUrl(newUrl);

    // The HTTP layers must read the URL live via the provider, not the
    // compile-time default: a saved URL change must affect the next request
    // without a restart.
    expect(sl<PredictionRemoteDataSource>().baseUrlProvider!(), newUrl);
    expect(sl<ComparisonRemoteDataSource>().baseUrlProvider!(), newUrl);
  });
}
