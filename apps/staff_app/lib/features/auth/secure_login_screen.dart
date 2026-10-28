import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';

/// Staff login. Identity comes from a password-only Supabase Auth session.
/// PIN is never accepted here; it is a step-up confirmation after login.
class SecureLoginScreen extends ConsumerStatefulWidget {
  const SecureLoginScreen({super.key});

  @override
  ConsumerState<SecureLoginScreen> createState() => _SecureLoginScreenState();
}

class _SecureLoginScreenState extends ConsumerState<SecureLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithPassword() async {
    if (_busy) return;
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (phone.isEmpty || password.isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف وكلمة المرور.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final user = await repo.signInWithPhoneAndPassword(phone, password);
      await _completeLogin(user);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _completeLogin(UserEntity user) async {
    final repo = ref.read(authRepositoryProvider);
    if (user.role == UserRole.customer) {
      await repo.signOut();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'هذا حساب زبون. استخدم تطبيق الزبائن.';
      });
      return;
    }
    if (!user.active) {
      await repo.signOut();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'هذا الحساب معطّل. راجع الإدارة.';
      });
      return;
    }

    try {
      await ref.read(staffAuditLoggerProvider).logLogin(user: user);
    } catch (_) {
      // Audit failure must not block a valid login.
    }
    if (!mounted) return;
    ref.read(authStateProvider.notifier).state = user;
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('Invalid login credentials')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
    }
    if (message.contains('Email not confirmed') ||
        message.contains('Phone not confirmed')) {
      return 'بيانات الدخول غير مؤكدة. راجع الإدارة.';
    }
    if (message.contains('Signups not allowed')) {
      return 'لا يوجد حساب موظف بهذا الرقم. راجع الإدارة.';
    }
    if (message.contains('AuthException')) {
      return message
          .replaceFirst('AuthException(message: ', '')
          .split(',')
          .first;
    }
    return message.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 44, color: colors.primary),
                      const SizedBox(height: 12),
                      Text(
                        'دخول الموظفين',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'جلسة آمنة عبر Supabase Auth. رمز PIN يُطلب فقط لتأكيد العمليات الحساسة.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          hintText: '0670000000',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textDirection: TextDirection.ltr,
                        onSubmitted: (_) => _signInWithPassword(),
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(Icons.key_outlined),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _signInWithPassword,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: const Text('تسجيل الدخول'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(color: colors.onErrorContainer),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'لا تملك حساباً؟ اطلب من المشرف إنشاء حساب موظف وتعيين كلمة مرور مؤقتة. لا تُستخدم رسائل SMS.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
