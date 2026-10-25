import 'package:go_router/go_router.dart';

import '../../features/comparison/presentation/screens/comparison_screen.dart';
import '../../features/prediction/presentation/screens/home_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/comparison',
      name: 'comparison',
      builder: (context, state) => const ComparisonScreen(),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
