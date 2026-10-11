import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:domain/domain.dart';

import '../features/auth/login_screen.dart';
import '../features/moderator/moderator_dashboard_screen.dart';
import '../features/manager/purchase_receiving_screen.dart';
import '../features/cashier/counter_pos_screen.dart';
import '../features/driver/driver_deliveries_screen.dart';

final authStateProvider = StateProvider<UserEntity?>((ref) => null);

class AuthNotifierListenable extends ChangeNotifier {
  final Ref ref;
  AuthNotifierListenable(this.ref) {
    ref.listen<UserEntity?>(authStateProvider, (_, __) {
      notifyListeners();
    });
  }
}

final authListenableProvider = Provider<AuthNotifierListenable>((ref) {
  return AuthNotifierListenable(ref);
});

final staffRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = ref.watch(authListenableProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authListenable,
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/moderator',
        builder: (context, state) => const ModeratorDashboardScreen(),
      ),
      GoRoute(
        path: '/manager',
        builder: (context, state) => const PurchaseReceivingScreen(),
      ),
      GoRoute(
        path: '/cashier',
        builder: (context, state) => const CounterPosScreen(),
      ),
      GoRoute(
        path: '/driver',
        builder: (context, state) => const DriverDeliveriesScreen(),
      ),
    ],
    redirect: (context, state) {
      final authUser = ref.read(authStateProvider);
      final isLoggingIn = state.matchedLocation == '/login';
      if (authUser == null) {
        return isLoggingIn ? null : '/login';
      }

      if (isLoggingIn) {
        switch (authUser.role) {
          case UserRole.moderator:
            return '/moderator';
          case UserRole.manager:
            return '/manager';
          case UserRole.cashier:
            return '/cashier';
          case UserRole.driver:
            return '/driver';
          case UserRole.customer:
            return '/login';
        }
      }
      return null;
    },
  );
});
