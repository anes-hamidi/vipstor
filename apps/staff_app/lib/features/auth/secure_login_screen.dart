import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';

enum _LoginMode { password, otp }

/// Real staff login. Identity comes from a Supabase Auth session only.
/// PIN is never accepted here; it is a step-up confirmation after login.
class SecureLoginScreen extends ConsumerStatefulWidget {
  const SecureLoginScreen({super.key});

  @override
  ConsumerState<SecureLoginScreen> createState() => _SecureLoginScreenState();
}

class _SecureLoginScreenState extends ConsumerState<SecureLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  _LoginMode _mode = _LoginMode.password;
  bool _busy = false;
  bool _otpSent = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
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

  Future<void> _sendOtp() async {
    if (_busy) return;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف أولاً.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.sendPhoneOtp(phone, shouldCreateUser: false);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (_busy) return;
    final phone = _phoneController.text.trim();
    final token = _otpController.text.trim();
    if (phone.isEmpty || token.length < 4) {
      setState(() => _error = 'أدخل رقم الهاتف ورمز التحقق.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final user = await repo.verifyPhoneOtp(phone: phone, token: token);
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
    if (message.contains('Phone not confirmed')) {
      return 'رقم الهاتف غير مؤكد. راجع الإدارة.';
    }
    if (message.contains('Signups not allowed')) {
      return 'لا يوجد حساب موظف بهذا الرقم. راجع الإدارة.';
    }
    if (message.contains('AuthException')) {
      return message.replaceFirst('AuthException(message: ', '').split(',').first;
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
                      Icon(Icons.shield_outlined, size: 44, color: colors.primary),
                      const SizedBox(height: 12),
                      Text(
                        'دخول الموظفين',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                      const SizedBox(height: 20),
                      SegmentedButton<_LoginMode>(
                        segments: const [
                          ButtonSegment(
                            value: _LoginMode.password,
                            icon: Icon(Icons.lock_outline),
                            label: Text('كلمة المرور'),
                          ),
                          ButtonSegment(
                            value: _LoginMode.otp,
                            icon: Icon(Icons.sms_outlined),
                            label: Text('رمز SMS'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _mode = value.first;
                                  _error = null;
                                  _otpSent = false;
                                }),
                      ),
                      const SizedBox(height: 20),
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
                      if (_mode == _LoginMode.password) ...[
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
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: const Text('تسجيل الدخول'),
                        ),
                      ] else ...[
                        if (_otpSent)
                          TextField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            textDirection: TextDirection.ltr,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'رمز التحقق',
                              prefixIcon: Icon(Icons.password_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : (_otpSent ? _verifyOtp : _sendOtp),
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(_otpSent ? Icons.verified_outlined : Icons.sms),
                          label: Text(_otpSent ? 'تأكيد الرمز' : 'إرسال رمز SMS'),
                        ),
                        if (_otpSent)
                          TextButton(
                            onPressed: _busy ? null : _sendOtp,
                            child: const Text('إعادة إرسال الرمز'),
                          ),
                      ],
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
                        'لا تملك حساباً؟ اطلب من المدير إنشاء حساب موظف وربطه برقم هاتفك في Supabase Auth.',
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
