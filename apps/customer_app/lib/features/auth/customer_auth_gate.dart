import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/customer_providers.dart';
import '../auth/customer_login_screen.dart';
import '../shell/customer_shell.dart';

/// Blocks the storefront until Supabase Auth has produced a verified customer
/// session. Catalog data is public, but orders, wallet and profile are not.
class CustomerAuthGate extends ConsumerWidget {
  const CustomerAuthGate({super.key, this.onExit});

  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(customerAuthStateProvider);
    return auth.when(
      loading: () => const _AuthSplash(),
      error: (error, _) => _AuthErrorScreen(
        error: error,
        onRetry: () => ref.read(customerAuthStateProvider.notifier).refresh(),
        onSignOut: () => ref.read(customerAuthStateProvider.notifier).signOut(),
      ),
      data: (user) {
        if (user == null) return const CustomerLoginScreen();
        return CustomerShell(onExit: onExit);
      },
    );
  }
}

class _AuthSplash extends StatelessWidget {
  const _AuthSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, size: 54),
            SizedBox(height: 18),
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('جارٍ التحقق من الجلسة…'),
          ],
        ),
      ),
    );
  }
}

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({
    required this.error,
    required this.onRetry,
    required this.onSignOut,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 48, color: colors.error),
                    const SizedBox(height: 12),
                    Text(
                      'تعذر التحقق من جلستك',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                    TextButton(
                      onPressed: onSignOut,
                      child: const Text('تسجيل الخروج والعودة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
