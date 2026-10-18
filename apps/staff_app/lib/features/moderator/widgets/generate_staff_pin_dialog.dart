import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:ui_kit/ui_kit.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

class GenerateStaffPinDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> staffUser;

  const GenerateStaffPinDialog({
    super.key,
    required this.staffUser,
  });

  @override
  ConsumerState<GenerateStaffPinDialog> createState() => _GenerateStaffPinDialogState();
}

class _GenerateStaffPinDialogState extends ConsumerState<GenerateStaffPinDialog> {
  final _pinController = TextEditingController();
  final _adminPinController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSaving = false;
  String? _errorMessage;
  bool _obscurePin = false;

  @override
  void initState() {
    super.initState();
    _generateRandomPin();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _adminPinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _generateRandomPin() {
    final random = Random();
    // Generate a 4-digit PIN between 1000 and 9999
    final pin = (1000 + random.nextInt(9000)).toString();
    setState(() {
      _pinController.text = pin;
      _errorMessage = null;
    });
    _focusNode.requestFocus();
  }

  void _copyToClipboard() {
    if (_pinController.text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _pinController.text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم نسخ الرمز ${_pinController.text} إلى الحافظة!'),
          duration: const Duration(seconds: 2),
          backgroundColor: context.appColors.info,
        ),
      );
    }
  }

  Future<void> _handleSavePin() async {
    final pin = _pinController.text.trim();
    final adminPin = _adminPinController.text.trim();
    if (pin.length < 4) {
      setState(() => _errorMessage = 'يجب أن يتكون رمز PIN الجديد من 4 أرقام!');
      return;
    }
    if (adminPin.length < 4) {
      setState(() => _errorMessage = 'يرجى إدخال رمز PIN الخاص بك (المشرف) لتأكيد العملية!');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final currentAdmin = ref.read(authStateProvider);
    final adminId = currentAdmin?.id;
    if (adminId == null) return;
    final targetUserId = widget.staffUser['id'] as String;
    final staffName = widget.staffUser['name'] as String? ?? 'الموظف';

    try {
      final repo = ref.read(authRepositoryProvider);
      final success = await repo.resetStaffPinByModerator(
        adminId: adminId,
        adminPin: adminPin,
        targetUserId: targetUserId,
        newPin: pin,
      );

      if (!mounted) return;

      if (success) {
        ref.invalidate(staffMembersProvider);
        ref.invalidate(liveStaffUsersProvider);
        Navigator.pop(context, pin);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text('تم تعيين رمز PIN الجديد ($pin) للموظف "$staffName" بنجاح!'),
                ),
              ],
            ),
            backgroundColor: context.appColors.success,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'نسخ الرمز',
              textColor: Colors.white,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pin));
              },
            ),
          ),
        );
      } else {
        setState(() => _errorMessage = 'تعذر تحديث الرمز في الخادم.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'حدث خطأ: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final staffName = widget.staffUser['name'] as String? ?? 'موظف';
    final staffPhone = widget.staffUser['phone'] as String? ?? '';
    final role = widget.staffUser['role'] as String? ?? 'cashier';

    final defaultPinTheme = PinTheme(
      width: 58,
      height: 64,
      textStyle: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
        letterSpacing: 2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colorScheme.primary, width: 2),
      ),
    );

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      child: ContentConstrainedBox.form(
        maxWidth: 420,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.pin_outlined, color: colorScheme.primary, size: 22),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'توليد رمز PIN للموظف',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              AppSpacing.gapSm,

              // Staff Details Banner
              Container(
                padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: colorScheme.primary,
                      child: Icon(_getRoleIcon(role), color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            staffName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                _getRoleLabel(role),
                                style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text('•  $staffPhone', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              AppSpacing.gapLg,

              Text(
                'رمز PIN الجديد (4 أرقام):',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'يمكنك تعديل الرمز يدوياً أو استخدام زر التوليد العشوائي السريع',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),

              AppSpacing.gapMd,

              // Pinput 4-Digit Field
              Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: Pinput(
                    controller: _pinController,
                    focusNode: _focusNode,
                    autofocus: true,
                    length: 4,
                    obscureText: _obscurePin,
                    obscuringCharacter: '●',
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: focusedPinTheme,
                    hapticFeedbackType: HapticFeedbackType.lightImpact,
                    onCompleted: (_) => _handleSavePin(),
                  ),
                ),
              ),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 14, color: colorScheme.error),
                    const SizedBox(width: 4),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],

              AppSpacing.gapMd,

              // Fast Controls: Generate Random & Copy
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _generateRandomPin,
                    icon: const Icon(Icons.casino_outlined, size: 18),
                    label: const Text('توليد عشوائي 🎲', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.outlined(
                    tooltip: 'نسخ الرمز',
                    onPressed: _copyToClipboard,
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.outlined(
                    tooltip: _obscurePin ? 'إظهار الرمز' : 'إخفاء الرمز',
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                    icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off, size: 18),
                  ),
                ],
              ),

              AppSpacing.gapLg,

              // Virtual Touch Keypad
              _buildKeypad(theme, colorScheme),

              AppSpacing.gapLg,

              // Admin PIN confirmation input
              TextField(
                controller: _adminPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'رمز PIN الخاص بك (المشرف) لتأكيد العملية *',
                  prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  counterText: '',
                ),
              ),

              AppSpacing.gapLg,

              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _handleSavePin,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_isSaving ? 'جاري الحفظ...' : 'تأكيد وحفظ رمز PIN'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(ThemeData theme, ColorScheme colorScheme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        children: [
          for (var row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['C', '0', '⌫'],
          ]) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) {
                final isAction = key == 'C' || key == '⌫';
                return Padding(
                  padding: const EdgeInsets.all(3.0),
                  child: InkWell(
                    borderRadius: AppRadius.mdAll,
                    onTap: () {
                      if (key == 'C') {
                        _pinController.clear();
                        setState(() => _errorMessage = null);
                      } else if (key == '⌫') {
                        if (_pinController.text.isNotEmpty) {
                          _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
                        }
                      } else {
                        if (_pinController.text.length < 4) {
                          _pinController.text = _pinController.text + key;
                        }
                      }
                    },
                    child: Container(
                      width: 72,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isAction
                            ? colorScheme.surfaceContainer
                            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        key,
                        style: TextStyle(
                          fontSize: isAction ? 14 : 17,
                          fontWeight: FontWeight.bold,
                          color: isAction ? colorScheme.error : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'moderator':
        return Icons.admin_panel_settings;
      case 'manager':
        return Icons.inventory;
      case 'cashier':
        return Icons.point_of_sale;
      case 'driver':
        return Icons.local_shipping;
      default:
        return Icons.person;
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'moderator':
        return 'مشرف عام';
      case 'manager':
        return 'مدير المخزون';
      case 'cashier':
        return 'أمين الصندوق';
      case 'driver':
        return 'سائق التوصيل';
      default:
        return 'موظف';
    }
  }
}
