import 'package:core/core.dart' show AppRole;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:domain/domain.dart';

import '../features/auth/change_pin_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/secure_login_screen.dart';
import '../features/moderator/moderator_dashboard_screen.dart';
import '../features/manager/purchase_receiving_screen.dart';
import '../features/cashier/counter_pos_screen.dart';
import '../features/driver/driver_deliveries_screen.dart';
import '../providers/staff_providers.dart';

// ── Auth state ─────────────────────────────────────────────────────────────────
// Holds the resolved public staff user. PIN login and session restore both
// resolve through the repository, which also installs the Supabase session.
final authStateProvider = StateProvider<UserEntity?>((ref) => null);

/// Maps the authenticated staff account onto the theme role whose palette the
/// application shell should display. Unauthenticated sessions and customer
/// accounts fall back to the neutral customer storefront theme.
AppRole roleForStaffUser(UserEntity? user) {
  return switch (user?.role) {
    UserRole.cashier => AppRole.cashier,
    UserRole.manager => AppRole.inventory,
    UserRole.driver => AppRole.delivery,
    UserRole.moderator => AppRole.moderator,
    UserRole.customer || null => AppRole.customer,
  };
}

// Tracks whether session restore has been attempted on boot.
final sessionRestoredProvider = StateProvider<bool>((ref) => false);

// ── Router refresh listenable ──────────────────────────────────────────────────
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen<UserEntity?>(authStateProvider, (prev, next) {
      if (prev != null && next == null) {
        // Staff logged out
        ref.read(staffAuditLoggerProvider).logLogout(user: prev);
      }
      notifyListeners();
    });
    ref.listen<bool>(sessionRestoredProvider, (_, __) => notifyListeners());
  }
}

final _authListenableProvider = Provider<_AuthChangeNotifier>((ref) {
  return _AuthChangeNotifier(ref);
});

// ── Session restore on boot ────────────────────────────────────────────────────
// Attempts to rehydrate from an existing Supabase session (survives app restart).
final _sessionRestoreProvider = FutureProvider<void>((ref) async {
  try {
    final repo = ref.read(authRepositoryProvider);
    final store = ref.read(staffLocalAuthStoreProvider);
    await store.purgeLegacyAuthCache();
    final user = await repo.getCurrentUser();
    if (user == null || !user.active || user.role == UserRole.customer) {
      return;
    }

    // Staff sessions are restored only when they were established through the
    // PIN terminal on this device. A legacy password-created staff session is
    // signed out so it cannot bypass the PIN-only login screen.
    if (user.role != UserRole.moderator) {
      final hasPinSession = await store.hasPinSession(user.id);
      if (!hasPinSession) {
        await repo.signOut();
        return;
      }
    }

    ref.read(authStateProvider.notifier).state = user;
  } catch (_) {
    // No valid session — stays on login screen
  } finally {
    ref.read(sessionRestoredProvider.notifier).state = true;
  }
});

// ── Router ────────────────────────────────────────────────────────────────────
final staffRouterProvider = Provider<GoRouter>((ref) {
  // Trigger session restore once
  ref.watch(_sessionRestoreProvider);
  final listenable = ref.watch(_authListenableProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: listenable,
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      // Moderator-only password login. Ordinary staff use the PIN terminal
      // above and never see a password field.
      GoRoute(
        path: '/moderator-login',
        builder: (_, __) => const SecureLoginScreen(),
      ),
      GoRoute(
        path: '/change-pin',
        builder: (_, __) => const ChangePinScreen(),
      ),
      GoRoute(
        path: '/moderator',
        builder: (_, __) => const ModeratorDashboardScreen(),
      ),
      GoRoute(
        path: '/manager',
        builder: (_, __) => const PurchaseReceivingScreen(),
      ),
      GoRoute(
        path: '/cashier',
        builder: (_, __) => const CounterPosScreen(),
      ),
      GoRoute(
        path: '/driver',
        builder: (_, __) => const DriverDeliveriesScreen(),
      ),
    ],
    redirect: (context, state) {
      final restored = ref.read(sessionRestoredProvider);
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/moderator-login';

      // While session restore is in flight, stay on a login route — no redirect
      if (!restored) return isAuthRoute ? null : '/login';

      final authUser = ref.read(authStateProvider);

      // Not authenticated → login (either the PIN terminal or moderator form)
      if (authUser == null) {
        return isAuthRoute ? null : '/login';
      }

      // Inactive account → back to login (cleared below)
      if (!authUser.active) {
        ref.read(authStateProvider.notifier).state = null;
        return '/login';
      }

      // A temporary/reset PIN blocks every workspace route until replaced.
      if (authUser.mustChangePin) {
        return state.matchedLocation == '/change-pin' ? null : '/change-pin';
      }
      if (state.matchedLocation == '/change-pin') {
        return _dashboardFor(authUser.role);
      }

      // Authenticated + on either login page → redirect to role dashboard
      if (isAuthRoute) {
        return _dashboardFor(authUser.role);
      }

      // Role guard: ensure current route matches the user's role
      final expected = _dashboardFor(authUser.role);
      if (state.matchedLocation != expected) {
        return expected;
      }

      return null;
    },
  );
});

String _dashboardFor(UserRole role) {
  switch (role) {
    case UserRole.moderator:
      return '/moderator';
    case UserRole.manager:
      return '/manager';
    case UserRole.cashier:
      return '/cashier';
    case UserRole.driver:
      return '/driver';
    case UserRole.customer:
      return '/login'; // customers use the customer app
  }
}
