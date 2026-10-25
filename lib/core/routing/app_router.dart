import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/prediction/presentation/screens/home_screen.dart';

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
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('Model Comparison - Coming Soon')),
      ),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('Settings - Coming Soon')),
      ),
    ),
  ],
);
