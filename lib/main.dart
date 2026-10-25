import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di.dart';
import 'core/routing/app_router.dart';
import 'core/theme.dart';
import 'features/prediction/presentation/bloc/prediction_bloc.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';
import 'features/settings/presentation/bloc/settings_event.dart';
import 'features/settings/presentation/bloc/settings_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<PredictionBloc>()),
        BlocProvider(
          create: (_) {
            final bloc = sl<SettingsBloc>();
            bloc.add(const LoadSettings());
            return bloc;
          },
        ),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          final themeMode = state is SettingsLoaded
              ? state.settings.themeMode
              : ThemeMode.system;

          return MaterialApp.router(
            title: 'HomeValue',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            routerConfig: appRouter,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
