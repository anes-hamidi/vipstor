import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';

/// Blocks the workspace while `users.must_change_pin` is true.
///
/// Temporary seed/reset PINs (for example the legacy `1234`) must be replaced
/// before any cashier, manager, driver or moderator action is allowed.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _currentPin = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentPin.dispose();
    _newPin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final user = ref.read(authStateProvider);
    if (user == null) return;

    final current = _currentPin.text.trim();
    final next = _newPin.text.trim();
    final confirm = _confirmPin.text.trim();

    // Empty current PIN is valid only for the first PIN setup of a staff
    // account provisioned directly in Supabase Auth.
    if (current.isNotEmpty && current.length < 4) {
      setState(() => _error = 'أدخل رمز PIN الحالي.');
      return;
    }
    if (next.length != 4 || !RegExp(r'^\d{4}$').hasMatch(next)) {
      setState(() => _error = 'رمز PIN الجديد يجب أن يكون 4 أرقام.');
      return;
    }
    if (next == current) {
      setState(() => _error = 'لا يمكن إعادة استخدام رمز PIN المؤقت.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'تأكيد رمز PIN غير مطابق.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref.read(authRepositoryProvider).changePin(
            userId: user.id,
            oldPin: current,
            newPin: next,
          );
      if (!ok) {
        throw Exception('تعذر تغيير رمز PIN.');
      }
      ref.read(authStateProvider.notifier).state =
          user.copyWith(mustChangePin: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    ref.read(authStateProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = ref.watch(authStateProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
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
                        Icon(Icons.key_rounded, size: 46, color: colors.primary),
                        const SizedBox(height: 12),
                        Text(
                          'تغيير رمز PIN إلزامي',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'مرحباً ${user?.name ?? ''}. تم تعيين رمز PIN مؤقت لحسابك. '
                          'اختر رمزاً جديداً قبل استخدام مساحة العمل.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 20),
                        _PinField(
                          controller: _currentPin,
                          label: 'رمز PIN الحالي / المؤقت',
                          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 12),
                        _PinField(
                          controller: _newPin,
                          label: 'رمز PIN الجديد',
                          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 12),
                        _PinField(
                          controller: _confirmPin,
                          label: 'تأكيد رمز PIN الجديد',
                          onSubmitted: (_) => _submit(),
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
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: const Text('حفظ رمز PIN والمتابعة'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _signOut,
                          child: const Text('تسجيل الخروج'),
                        ),
                      ],
                    ),
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

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.label,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
