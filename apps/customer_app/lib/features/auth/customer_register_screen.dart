import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/customer_providers.dart';
import 'widgets/algomend_auth_widgets.dart';

/// Password-only customer self-registration.
///
/// The server creates a Supabase Auth identity with a deterministic synthetic
/// email and returns a one-time recovery code. No SMS or email is sent.
class CustomerRegisterScreen extends ConsumerStatefulWidget {
  const CustomerRegisterScreen({super.key});

  @override
  ConsumerState<CustomerRegisterScreen> createState() =>
      _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState
    extends ConsumerState<CustomerRegisterScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  String _friendly(Object error) {
    final raw = error.toString();
    if (raw.contains('message: ')) {
      final message = raw
          .split('message: ')
          .last
          .split(RegExp(r',\s*(statusCode|code|details):'))
          .first
          .trim();
      if (message.isNotEmpty) {
        return message.replaceFirst(RegExp(r'\)$'), '');
      }
    }
    return raw.replaceFirst('Exception: ', '');
  }

  Future<void> _register() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.length < 2) {
      setState(() => _error = 'أدخل الاسم الكامل (حرفان على الأقل).');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'كلمة المرور يجب أن تكون 8 أحرف على الأقل.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(customerAuthStateProvider.notifier);
      final result = await auth.registerCustomer(
        name: name,
        phone: phone,
        password: password,
      );

      if (!mounted) return;
      await _showRecoveryCode(result.recoveryCode, result.phone);
      if (!mounted) return;

      // Sign in immediately so the newly created account is usable. If this
      // fails the account still exists; the customer can log in manually.
      try {
        await auth.signIn(phone: result.phone, password: password);
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'تم إنشاء الحساب بنجاح، لكن تعذر تسجيل الدخول تلقائياً. '
              'سجّل الدخول برقم هاتفك وكلمة المرور. ${_friendly(error)}';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(error);
      });
    }
  }

  Future<void> _showRecoveryCode(String code, String phone) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.key_rounded, color: algomendGreen, size: 34),
          title: const Text('احفظ رمز الاستعادة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'تم إنشاء حسابك بنجاح. هذا الرمز يُعرض مرة واحدة فقط ويُستخدم '
                  'لاستعادة كلمة المرور إذا نسيتها.',
                  style: TextStyle(height: 1.55),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: algomendGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: algomendGreen.withValues(alpha: 0.4),
                    ),
                  ),
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'رقم الهاتف: $phone',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: algomendGray,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ رمز الاستعادة')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('نسخ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حفظت الرمز، متابعة'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurfaceVariant = isDark ? const Color(0xFFB2C9BC) : algomendGray;
    final inputFill =
        isDark ? const Color(0xFF171F1A) : const Color(0xFFEEF5F0);
    final borderColor =
        isDark ? const Color(0xFF2C352F) : const Color(0xFFD7E5DC);

    return PopScope(
      canPop: !_busy,
      child: AlgomendAuthShell(
        title: 'إنشاء حساب زبون',
        subtitle:
            'سجّل برقم هاتفك وكلمة مرور. لا حاجة لرمز SMS، وستحصل على رمز استعادة بعد التسجيل.',
        bottom: TextButton.icon(
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('لديك حساب؟ تسجيل الدخول'),
        ),
        children: [
          AlgomendAuthTextField(
            controller: _nameController,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            onSubmitted: (_) => _phoneFocus.requestFocus(),
            labelText: 'الاسم الكامل',
            hintText: 'مثال: محمد أحمد',
            prefixIcon: Icons.person_outline_rounded,
            fillColor: inputFill,
            borderColor: borderColor,
            focusColor: algomendGreen,
            isDark: isDark,
            onSurfaceVariant: onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          AlgomendAuthTextField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
            ],
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            labelText: 'رقم الهاتف',
            hintText: '0550123456',
            prefixIcon: Icons.phone_iphone_rounded,
            fillColor: inputFill,
            borderColor: borderColor,
            focusColor: algomendGreen,
            isDark: isDark,
            onSurfaceVariant: onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          AlgomendAuthTextField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: _obscurePassword,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _confirmFocus.requestFocus(),
            labelText: 'كلمة المرور',
            hintText: '8 أحرف على الأقل',
            prefixIcon: Icons.lock_outline_rounded,
            fillColor: inputFill,
            borderColor: borderColor,
            focusColor: algomendGreen,
            isDark: isDark,
            onSurfaceVariant: onSurfaceVariant,
            suffixIcon: IconButton(
              tooltip:
                  _obscurePassword ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: onSurfaceVariant,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 14),
          AlgomendAuthTextField(
            controller: _confirmController,
            focusNode: _confirmFocus,
            enabled: !_busy,
            obscureText: _obscureConfirm,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _register(),
            labelText: 'تأكيد كلمة المرور',
            hintText: 'أعد كتابة كلمة المرور',
            prefixIcon: Icons.lock_reset_rounded,
            fillColor: inputFill,
            borderColor: borderColor,
            focusColor: algomendGreen,
            isDark: isDark,
            onSurfaceVariant: onSurfaceVariant,
            suffixIcon: IconButton(
              tooltip:
                  _obscureConfirm ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: onSurfaceVariant,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          const SizedBox(height: 20),
          AlgomendGradientButton(
            label: 'إنشاء الحساب',
            icon: Icons.person_add_alt_1_rounded,
            busy: _busy,
            onPressed: _register,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            AlgomendAuthError(message: _error!),
          ],
        ],
      ),
    );
  }
}
