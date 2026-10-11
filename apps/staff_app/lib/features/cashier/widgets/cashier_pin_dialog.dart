import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:staff_app/providers/staff_providers.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../router/staff_router.dart';
import '../../auth/widgets/change_pin_dialog.dart';

enum CashierPinMode {
  unlockTerminal,
  switchCashier,
}

class CashierPinDialog extends ConsumerStatefulWidget {
  final CashierPinMode mode;
  final UserEntity? lockedUser;

  const CashierPinDialog({
    super.key,
    this.mode = CashierPinMode.switchCashier,
    this.lockedUser,
  });

  @override
  ConsumerState<CashierPinDialog> createState() => _CashierPinDialogState();
}

class _CashierPinDialogState extends ConsumerState<CashierPinDialog> {
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();

  UserEntity? _selectedStaff;
  String? _errorMessage;
  bool _isVerifying = false;

  

  List<UserEntity> get _availableStaff {
    final currentAuth = ref.read(authStateProvider);
    final list = <UserEntity>[];
    final staffList = ref.read(staffListProvider).value ?? const <UserEntity>[];
    if (currentAuth != null) {
      list.add(currentAuth);
    }
    for (final staff in staffList) {
      if (!list.any((u) => u.id == staff.id)) {
        list.add(staff);
      }
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    final currentAuth = ref.read(authStateProvider);
    final staffList = ref.read(staffListProvider).value ?? const <UserEntity>[];
    final fallbackStaff = staffList.isNotEmpty ? staffList.first : null;
    if (widget.mode == CashierPinMode.unlockTerminal) {
      _selectedStaff = widget.lockedUser ?? currentAuth ?? fallbackStaff;
    } else {
      _selectedStaff = currentAuth ?? fallbackStaff;
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _verifyPin(String pin) async {
    if (pin.length < 4) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 350));

    // Accepted default PIN for fast switch / unlock is '1234' or any 4-digit PIN in demo
    // In production, PIN hash matching will occur
    const validPin = '1234';

    if (pin == validPin || pin == '0000' || pin == '1111' || pin == '2222') {
      if (!mounted) return;
      final selected = _selectedStaff;
      Navigator.of(context, rootNavigator: true).pop(true);
      if (widget.mode == CashierPinMode.switchCashier && selected != null) {
        ref.read(authStateProvider.notifier).state = selected;
      }
    } else {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = 'رمز PIN غير صحيح! جرب 1234';
        _pinController.clear();
      });
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLockMode = widget.mode == CashierPinMode.unlockTerminal;

    final defaultPinTheme = PinTheme(
      width: 56,
      height: 60,
      textStyle: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.primary,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: colorScheme.primary, width: 2.5),
        color: colorScheme.primaryContainer.withValues(alpha: 0.2),
      ),
    );

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: colorScheme.error, width: 2),
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
      ),
    );

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header Icon
              Container(
                padding: const EdgeInsetsDirectional.all(14),
                decoration: BoxDecoration(
                  color: isLockMode
                      ? colorScheme.errorContainer
                      : colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isLockMode
                      ? Icons.lock_outline_rounded
                      : Icons.lock_person_outlined,
                  size: 32,
                  color: isLockMode
                      ? colorScheme.onErrorContainer
                      : colorScheme.onPrimaryContainer,
                ),
              ),
              AppSpacing.gapMd,

              // Title
              Text(
                isLockMode
                    ? 'شاشة الكاشير مقفلة'
                    : 'التبديل السريع للكاشير (PIN)',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                isLockMode
                    ? 'أدخل رمز PIN المكون من 4 أرقام لفتح قفل الشاشة ومتابعة البيع'
                    : 'اختر حساب الكاشير ثم أدخل رمز PIN للتبديل الفوري',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              AppSpacing.gapLg,

              // Staff Selector (when in Switch Mode)
              if (!isLockMode) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'اختر الكاشير:',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                AppSpacing.gapSm,
                Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedStaff?.id,
                      items: _availableStaff.map((staff) {
                        return DropdownMenuItem<String>(
                          value: staff.id,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: colorScheme.primaryContainer,
                                child: Icon(Icons.person,
                                    size: 16, color: colorScheme.primary),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(staff.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              const Spacer(),
                              Text(
                                staff.role == UserRole.manager
                                    ? 'مشرف'
                                    : 'كاشير',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final selected = _availableStaff.firstWhere(
                            (s) => s.id == val,
                            orElse: () => _availableStaff.first,
                          );
                          setState(() {
                            _selectedStaff = selected;
                            _errorMessage = null;
                            _pinController.clear();
                          });
                          _focusNode.requestFocus();
                        }
                      },
                    ),
                  ),
                ),
                AppSpacing.gapLg,
              ] else if (_selectedStaff != null) ...[
                Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: colorScheme.primary,
                        child: Icon(Icons.person,
                            size: 14, color: colorScheme.onPrimary),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(_selectedStaff!.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                AppSpacing.gapLg,
              ],

              // Pinput 4-Digit Field
              Directionality(
                textDirection: TextDirection.ltr,
                child: Pinput(
                  controller: _pinController,
                  focusNode: _focusNode,
                  autofocus: true,
                  length: 4,
                  obscureText: true,
                  obscuringCharacter: '●',
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: focusedPinTheme,
                  errorPinTheme: errorPinTheme,
                  hapticFeedbackType: HapticFeedbackType.mediumImpact,
                  onCompleted: _verifyPin,
                  onChanged: (_) {
                    if (_errorMessage != null) {
                      setState(() => _errorMessage = null);
                    }
                  },
                ),
              ),

              // Error Message
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 14, color: colorScheme.error),
                    const SizedBox(width: 4),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.error,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],

              AppSpacing.gapLg,

              // Virtual Number Keypad (Touch / Pointer-First Friendly)
              _buildKeypad(theme, colorScheme),

              if (_selectedStaff != null) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) =>
                          ChangePinDialog(staffMember: _selectedStaff!),
                    );
                  },
                  icon: const Icon(Icons.password_rounded, size: 15),
                  label: const Text('تغيير رمز PIN',
                      style: TextStyle(fontSize: 12)),
                ),
              ],

              AppSpacing.gapSm,

              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!isLockMode)
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    )
                  else
                    const SizedBox.shrink(),
                  if (_isVerifying)
                    const CircularProgressIndicator.adaptive()
                  else
                    FilledButton.icon(
                      onPressed: () => _verifyPin(_pinController.text),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(isLockMode ? 'فتح القفل' : 'تأكيد التبديل'),
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
                  padding: const EdgeInsets.all(4.0),
                  child: InkWell(
                    borderRadius: AppRadius.mdAll,
                    onTap: () {
                      if (key == 'C') {
                        _pinController.clear();
                        setState(() => _errorMessage = null);
                      } else if (key == '⌫') {
                        if (_pinController.text.isNotEmpty) {
                          _pinController.text = _pinController.text
                              .substring(0, _pinController.text.length - 1);
                        }
                      } else {
                        if (_pinController.text.length < 4) {
                          _pinController.text = _pinController.text + key;
                          if (_pinController.text.length == 4) {
                            _verifyPin(_pinController.text);
                          }
                        }
                      }
                    },
                    child: Container(
                      width: 72,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isAction
                            ? colorScheme.surfaceContainer
                            : colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        key,
                        style: TextStyle(
                          fontSize: isAction ? 15 : 18,
                          fontWeight: FontWeight.bold,
                          color: isAction
                              ? colorScheme.error
                              : colorScheme.onSurface,
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
}
