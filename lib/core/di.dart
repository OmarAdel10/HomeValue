import 'package:get_it/get_it.dart';

import '../core/constants.dart';
import '../features/prediction/data/datasources/prediction_remote_datasource.dart';
import '../features/prediction/data/repositories/prediction_repository_impl.dart';
import '../features/prediction/domain/repositories/prediction_repository.dart';
import '../features/prediction/presentation/bloc/prediction_bloc.dart';

final GetIt sl = GetIt.instance;

Future<void> initDependencies() async {
  // External dependencies
  // sl.registerLazySingleton(() => HttpClient());

  // Data sources
  sl.registerLazySingleton<PredictionRemoteDataSource>(
    () => PredictionRemoteDataSource(
      baseUrl: AppConstants.apiBaseUrl,
      timeout: AppConstants.apiTimeout,
    ),
  );

  // Repositories
  sl.registerLazySingleton<PredictionRepository>(
    () => PredictionRepositoryImpl(
      remoteDataSource: sl<PredictionRemoteDataSource>(),
    ),
  );

  // BLoCs
  sl.registerFactory(
    () => PredictionBloc(repository: sl<PredictionRepository>()),
  );
}
