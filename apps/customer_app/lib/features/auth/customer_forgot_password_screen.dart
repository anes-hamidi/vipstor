import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/customer_providers.dart';
import 'widgets/algomend_auth_widgets.dart';

/// Password recovery using the one-time recovery code issued at registration.
///
/// No SMS or email is sent. A successful reset rotates the recovery code and
/// displays the replacement exactly once.
class CustomerForgotPasswordScreen extends ConsumerStatefulWidget {
  const CustomerForgotPasswordScreen({super.key});

  @override
  ConsumerState<CustomerForgotPasswordScreen> createState() =>
      _CustomerForgotPasswordScreenState();
}

class _CustomerForgotPasswordScreenState
    extends ConsumerState<CustomerForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
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

  Future<void> _resetPassword() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (phone.isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف.');
      return;
    }
    if (code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 8) {
      setState(() => _error = 'أدخل رمز الاستعادة المكوّن من 12 حرفاً.');
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
      final result = await ref
          .read(customerAuthStateProvider.notifier)
          .resetCustomerPassword(
            phone: phone,
            recoveryCode: code,
            newPassword: password,
          );

      if (!mounted) return;
      await _showResult(result.recoveryCode, result.warning);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(error);
      });
    }
  }

  Future<void> _showResult(String? newCode, String? warning) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: Icon(
            warning == null ? Icons.check_circle_rounded : Icons.info_rounded,
            color: warning == null ? algomendGreen : Colors.orange,
            size: 34,
          ),
          title: Text(
              warning == null ? 'تم تغيير كلمة المرور' : 'تم التغيير مع تنبيه'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'يمكنك الآن تسجيل الدخول برقم هاتفك وكلمة المرور الجديدة.',
                  style: TextStyle(height: 1.55),
                ),
                if (warning != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    warning,
                    style: const TextStyle(
                      color: Color(0xFF8A5A00),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
                if (newCode != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'رمز الاستعادة الجديد — يُعرض مرة واحدة فقط:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: algomendGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: algomendGreen.withValues(alpha: 0.4),
                      ),
                    ),
                    child: SelectableText(
                      newCode,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (newCode != null)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: newCode));
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
              child: const Text('العودة لتسجيل الدخول'),
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
        title: 'استعادة كلمة المرور',
        subtitle:
            'أدخل رقم هاتفك ورمز الاستعادة الذي حصلت عليه عند التسجيل، ثم اختر كلمة مرور جديدة.',
        bottom: TextButton.icon(
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('العودة لتسجيل الدخول'),
        ),
        children: [
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
            onSubmitted: (_) => _codeFocus.requestFocus(),
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
            controller: _codeController,
            focusNode: _codeFocus,
            enabled: !_busy,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.characters,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
            ],
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            labelText: 'رمز الاستعادة',
            hintText: 'XXXX-XXXX-XXXX',
            prefixIcon: Icons.key_rounded,
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
            labelText: 'كلمة المرور الجديدة',
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
            onSubmitted: (_) => _resetPassword(),
            labelText: 'تأكيد كلمة المرور الجديدة',
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
            label: 'تغيير كلمة المرور',
            icon: Icons.lock_reset_rounded,
            busy: _busy,
            onPressed: _resetPassword,
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
