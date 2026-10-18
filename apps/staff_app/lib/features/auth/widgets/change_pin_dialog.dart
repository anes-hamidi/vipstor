import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';

class ChangePinDialog extends ConsumerStatefulWidget {
  final UserEntity staffMember;

  const ChangePinDialog({
    super.key,
    required this.staffMember,
  });

  @override
  ConsumerState<ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends ConsumerState<ChangePinDialog> {
  int _currentStep = 1; // 1: Old PIN, 2: New PIN, 3: Confirm PIN
  String _oldPin = '';
  String _newPin = '';

  final _pinController = TextEditingController();
  final _focusNode = FocusNode();
  String? _errorMessage;
  bool _isProcessing = false;

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPinSubmitted(String pin) async {
    if (pin.length < 4) return;

    if (_currentStep == 1) {
      // Verify old PIN
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      final repo = ref.read(authRepositoryProvider);
      final isValid = await repo.verifyPin(
        userId: widget.staffMember.id,
        pin: pin,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (isValid) {
        setState(() {
          _oldPin = pin;
          _currentStep = 2;
          _pinController.clear();
        });
        _focusNode.requestFocus();
      } else {
        setState(() {
          _errorMessage = 'رمز PIN الحالي غير صحيح! جرب 1234';
          _pinController.clear();
        });
        _focusNode.requestFocus();
      }
    } else if (_currentStep == 2) {
      // Store new PIN and move to confirm
      setState(() {
        _newPin = pin;
        _currentStep = 3;
        _pinController.clear();
        _errorMessage = null;
      });
      _focusNode.requestFocus();
    } else if (_currentStep == 3) {
      // Confirm new PIN
      if (pin != _newPin) {
        setState(() {
          _errorMessage = 'الرمز التأكيدي غير متطابق!';
          _pinController.clear();
        });
        _focusNode.requestFocus();
        return;
      }

      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      final repo = ref.read(authRepositoryProvider);
      final success = await repo.changePin(
        userId: widget.staffMember.id,
        oldPin: _oldPin,
        newPin: _newPin,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (success) {
        ref.invalidate(liveStaffUsersProvider);
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: AppSpacing.md),
                Text('تم تغيير رمز PIN للمستخدم "${widget.staffMember.name}" بنجاح!'),
              ],
            ),
            backgroundColor: context.appColors.success,
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'فشل تحديث الرمز. حاول مجدداً.';
          _pinController.clear();
        });
        _focusNode.requestFocus();
      }
    }
  }

  void _resetSteps() {
    setState(() {
      _currentStep = 1;
      _oldPin = '';
      _newPin = '';
      _errorMessage = null;
      _pinController.clear();
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final defaultPinTheme = PinTheme(
      width: 52,
      height: 56,
      textStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
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

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colorScheme.error, width: 2),
      ),
    );

    String stepTitle;
    String stepSubtitle;
    if (_currentStep == 1) {
      stepTitle = 'أدخل رمز PIN الحالي';
      stepSubtitle = 'التحقق من هوية ${widget.staffMember.name}';
    } else if (_currentStep == 2) {
      stepTitle = 'أدخل رمز PIN الجديد';
      stepSubtitle = 'اختر 4 أرقام يسهل تذكرها لك';
    } else {
      stepTitle = 'تأكيد رمز PIN الجديد';
      stepSubtitle = 'أعد كتابة الرمز الجديد لتأكيد الحفظ';
    }

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      child: ContentConstrainedBox.form(
        maxWidth: 380,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                        child: Icon(Icons.password_rounded, color: colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'تغيير رمز PIN',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const Divider(),
              AppSpacing.gapSm,

              // Step indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepDot(1, 'القديم'),
                  Container(
                    width: 30,
                    height: 2,
                    color: _currentStep > 1 ? colorScheme.primary : colorScheme.outlineVariant,
                  ),
                  _buildStepDot(2, 'الجديد'),
                  Container(
                    width: 30,
                    height: 2,
                    color: _currentStep > 2 ? colorScheme.primary : colorScheme.outlineVariant,
                  ),
                  _buildStepDot(3, 'التأكيد'),
                ],
              ),
              AppSpacing.gapLg,

              // Title and Subtitle
              Text(
                stepTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                stepSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              AppSpacing.gapLg,

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
                  onCompleted: _onPinSubmitted,
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

              // Virtual Number Keypad
              _buildKeypad(theme, colorScheme),

              AppSpacing.gapSm,

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 1)
                    TextButton.icon(
                      onPressed: _resetSteps,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('البدء من جديد', style: TextStyle(fontSize: 12)),
                    )
                  else
                    const SizedBox.shrink(),
                  if (_isProcessing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  else
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepDot(int step, String label) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDone = _currentStep > step;
    final isCurrent = _currentStep == step;

    Color bg = colorScheme.surfaceContainerHighest;
    Color fg = colorScheme.onSurfaceVariant;
    if (isDone) {
      bg = colorScheme.primary;
      fg = colorScheme.onPrimary;
    } else if (isCurrent) {
      bg = colorScheme.primaryContainer;
      fg = colorScheme.primary;
    }

    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: isCurrent ? Border.all(color: colorScheme.primary, width: 2) : null,
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '$step',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
                ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildKeypad(ThemeData theme, ColorScheme colorScheme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
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
                          if (_pinController.text.length == 4) {
                            _onPinSubmitted(_pinController.text);
                          }
                        }
                      }
                    },
                    child: Container(
                      width: 68,
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
}
