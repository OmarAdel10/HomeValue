import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../features/comparison/data/datasources/comparison_remote_datasource.dart';
import '../features/comparison/data/repositories/comparison_repository_impl.dart';
import '../features/comparison/domain/repositories/comparison_repository.dart';
import '../features/comparison/presentation/bloc/comparison_bloc.dart';
import '../features/prediction/data/datasources/prediction_remote_datasource.dart';
import '../features/prediction/data/repositories/prediction_repository_impl.dart';
import '../features/prediction/domain/repositories/prediction_repository.dart';
import '../features/prediction/presentation/bloc/prediction_bloc.dart';
import '../features/settings/data/datasources/settings_local_datasource.dart';
import '../features/settings/data/repositories/settings_repository_impl.dart';
import '../features/settings/domain/repositories/settings_repository.dart';
import '../features/settings/presentation/bloc/settings_bloc.dart';

final GetIt sl = GetIt.instance;

Future<void> initDependencies() async {
  // External dependencies
  final prefs = await SharedPreferences.getInstance();
  sl.registerLazySingleton<SharedPreferences>(() => prefs);

  // Data sources - Settings (server URL is read before each HTTP request)
  sl.registerLazySingleton<SettingsLocalDataSource>(
    () => SettingsLocalDataSource(sl<SharedPreferences>()),
  );

  // Data sources - Prediction
  sl.registerLazySingleton<PredictionRemoteDataSource>(
    () => PredictionRemoteDataSource(
      baseUrl: AppConstants.apiBaseUrl,
      baseUrlProvider: () => sl<SettingsLocalDataSource>().serverUrl,
      timeout: AppConstants.apiTimeout,
    ),
  );

  // Data sources - Comparison
  sl.registerLazySingleton<ComparisonRemoteDataSource>(
    () => ComparisonRemoteDataSource(
      client: http.Client(),
      baseUrl: AppConstants.apiBaseUrl,
      baseUrlProvider: () => sl<SettingsLocalDataSource>().serverUrl,
    ),
  );

  // Repositories
  sl.registerLazySingleton<PredictionRepository>(
    () => PredictionRepositoryImpl(
      remoteDataSource: sl<PredictionRemoteDataSource>(),
    ),
  );

  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(
      localDataSource: sl<SettingsLocalDataSource>(),
    ),
  );

  sl.registerLazySingleton<ComparisonRepository>(
    () => ComparisonRepositoryImpl(
      remoteDataSource: sl<ComparisonRemoteDataSource>(),
    ),
  );

  // BLoCs
  sl.registerFactory(
    () => PredictionBloc(repository: sl<PredictionRepository>()),
  );

  sl.registerFactory(
    () => SettingsBloc(repository: sl<SettingsRepository>()),
  );

  sl.registerFactory(
    () => ComparisonBloc(repository: sl<ComparisonRepository>()),
  );
}
