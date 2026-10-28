import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart' show Success, FailureResult;
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';

import '../../../providers/staff_providers.dart';
import 'auth_theme.dart';

/// Responsive modal for changing a staff member's 4-digit PIN.
///
/// The dialog is composed from the shared auth palette, so it follows the
/// active light/dark theme and role accent. The native keyboard remains
/// suppressed (`useNativeKeyboard: false`) and input is handled by the tactile
/// on-screen keypad or the physical keyboard shortcuts.
class ChangePinDialog extends ConsumerStatefulWidget {
  final UserEntity staffMember;

  const ChangePinDialog({super.key, required this.staffMember});

  /// Opens the change PIN dialog with full responsiveness.
  static Future<bool?> show(
    BuildContext context, {
    required UserEntity staffMember,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ChangePinDialog(staffMember: staffMember),
    );
  }

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

  void _appendDigit(String digit) {
    if (_isProcessing) return;
    if (_pinController.text.length < 4) {
      _pinController.text = _pinController.text + digit;
      if (_errorMessage != null) {
        setState(() => _errorMessage = null);
      }
      if (_pinController.text.length == 4) {
        _onPinSubmitted(_pinController.text);
      }
    }
  }

  void _backspace() {
    if (_isProcessing) return;
    if (_pinController.text.isNotEmpty) {
      _pinController.text = _pinController.text.substring(
        0,
        _pinController.text.length - 1,
      );
      if (_errorMessage != null) {
        setState(() => _errorMessage = null);
      }
    }
  }

  void _clear() {
    if (_isProcessing) return;
    _pinController.clear();
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  void _onPinSubmitted(String pin) async {
    if (pin.length < 4) return;

    if (_currentStep == 1) {
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      final repo = ref.read(authRepositoryProvider);
      final result = await repo.verifyPin(
        userId: widget.staffMember.id,
        pin: pin,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      switch (result) {
        case Success(:final value) when value:
          setState(() {
            _oldPin = pin;
            _currentStep = 2;
            _pinController.clear();
          });
        case Success():
          setState(() {
            _errorMessage = 'رمز PIN الحالي غير صحيح!';
            _pinController.clear();
          });
        case FailureResult(:final error):
          setState(() {
            _errorMessage = error.message;
            _pinController.clear();
          });
      }
    } else if (_currentStep == 2) {
      setState(() {
        _newPin = pin;
        _currentStep = 3;
        _pinController.clear();
        _errorMessage = null;
      });
    } else if (_currentStep == 3) {
      if (pin != _newPin) {
        setState(() {
          _errorMessage = 'الرمز التأكيدي غير متطابق!';
          _pinController.clear();
        });
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
        final messenger = ScaffoldMessenger.of(context);
        final ColorScheme scheme = Theme.of(context).colorScheme;

        ref.invalidate(liveStaffUsersProvider);
        Navigator.pop(context, true);
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.onInverseSurface,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'تم تغيير رمز PIN للمستخدم "${widget.staffMember.name}" بنجاح!',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'فشل تحديث الرمز. حاول مجدداً.';
          _pinController.clear();
        });
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
  }

  @override
  Widget build(BuildContext context) {
    final AuthPalette p = context.authPalette;

    final String stepTitle;
    final String stepSubtitle;
    switch (_currentStep) {
      case 1:
        stepTitle = 'أدخل رمز PIN الحالي';
        stepSubtitle = 'التحقق من هوية ${widget.staffMember.name}';
      case 2:
        stepTitle = 'أدخل رمز PIN الجديد';
        stepSubtitle = 'اختر 4 أرقام يسهل تذكرها لك';
      default:
        stepTitle = 'تأكيد رمز PIN الجديد';
        stepSubtitle = 'أعد كتابة الرمز الجديد لتأكيد الحفظ';
    }

    // Hardware keyboard shortcuts.
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context, false),
      const SingleActivator(LogicalKeyboardKey.backspace): _backspace,
      const SingleActivator(LogicalKeyboardKey.delete): _clear,
      const SingleActivator(LogicalKeyboardKey.digit0): () => _appendDigit('0'),
      const SingleActivator(LogicalKeyboardKey.digit1): () => _appendDigit('1'),
      const SingleActivator(LogicalKeyboardKey.digit2): () => _appendDigit('2'),
      const SingleActivator(LogicalKeyboardKey.digit3): () => _appendDigit('3'),
      const SingleActivator(LogicalKeyboardKey.digit4): () => _appendDigit('4'),
      const SingleActivator(LogicalKeyboardKey.digit5): () => _appendDigit('5'),
      const SingleActivator(LogicalKeyboardKey.digit6): () => _appendDigit('6'),
      const SingleActivator(LogicalKeyboardKey.digit7): () => _appendDigit('7'),
      const SingleActivator(LogicalKeyboardKey.digit8): () => _appendDigit('8'),
      const SingleActivator(LogicalKeyboardKey.digit9): () => _appendDigit('9'),
      const SingleActivator(LogicalKeyboardKey.numpad0): () =>
          _appendDigit('0'),
      const SingleActivator(LogicalKeyboardKey.numpad1): () =>
          _appendDigit('1'),
      const SingleActivator(LogicalKeyboardKey.numpad2): () =>
          _appendDigit('2'),
      const SingleActivator(LogicalKeyboardKey.numpad3): () =>
          _appendDigit('3'),
      const SingleActivator(LogicalKeyboardKey.numpad4): () =>
          _appendDigit('4'),
      const SingleActivator(LogicalKeyboardKey.numpad5): () =>
          _appendDigit('5'),
      const SingleActivator(LogicalKeyboardKey.numpad6): () =>
          _appendDigit('6'),
      const SingleActivator(LogicalKeyboardKey.numpad7): () =>
          _appendDigit('7'),
      const SingleActivator(LogicalKeyboardKey.numpad8): () =>
          _appendDigit('8'),
      const SingleActivator(LogicalKeyboardKey.numpad9): () =>
          _appendDigit('9'),
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: AuthPanel(
              radius: AppRadius.xxl,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(p),
                    const SizedBox(height: AppSpacing.md),
                    Divider(color: p.border, height: 1),
                    const SizedBox(height: AppSpacing.md),
                    _buildStepIndicator(p),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      stepTitle,
                      textAlign: TextAlign.center,
                      style: p.theme.textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stepSubtitle,
                      textAlign: TextAlign.center,
                      style: p.theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: p.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: AuthPinField(
                        controller: _pinController,
                        focusNode: _focusNode,
                        isError: _errorMessage != null,
                        obscuringCharacter: '●',
                        fieldWidth: 50,
                        fieldHeight: 54,
                        onCompleted: _onPinSubmitted,
                        onChanged: (_) {
                          if (_errorMessage != null) {
                            setState(() => _errorMessage = null);
                          }
                        },
                      ),
                    ),
                    AnimatedSize(
                      duration: AppMotion.fast,
                      curve: AppMotion.enterCurve,
                      child: _errorMessage == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsetsDirectional.only(
                                top: AppSpacing.sm,
                              ),
                              child: AuthErrorBanner(message: _errorMessage!),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AuthNumericKeypad(
                      maxWidth: 280,
                      keyHeight: 46,
                      enabled: !_isProcessing,
                      clearLabel: 'C',
                      backspaceLabel: '⌫',
                      onDigit: _appendDigit,
                      onBackspace: _backspace,
                      onClear: _clear,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildFooter(p),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AuthPalette p) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: p.accentSoft,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: p.accent.withValues(alpha: 0.26)),
          ),
          child: Icon(Icons.password_rounded, color: p.accent, size: 19),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تغيير رمز PIN',
                style: p.theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: p.text,
                ),
              ),
              Text(
                widget.staffMember.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: p.theme.textTheme.labelSmall?.copyWith(color: p.muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'إغلاق',
          icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    );
  }

  Widget _buildStepIndicator(AuthPalette p) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStepDot(p, 1, 'القديم'),
        _buildStepConnector(p, active: _currentStep > 1),
        _buildStepDot(p, 2, 'الجديد'),
        _buildStepConnector(p, active: _currentStep > 2),
        _buildStepDot(p, 3, 'التأكيد'),
      ],
    );
  }

  Widget _buildStepConnector(AuthPalette p, {required bool active}) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      width: 26,
      height: 2,
      margin: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: active ? p.accent : p.border,
        borderRadius: AppRadius.pillAll,
      ),
    );
  }

  Widget _buildStepDot(AuthPalette p, int step, String label) {
    final bool isDone = _currentStep > step;
    final bool isCurrent = _currentStep == step;

    final Color background = isDone
        ? p.accent
        : (isCurrent ? p.accentSoft : p.panelAlt);
    final Color foreground = isDone
        ? p.onAccent
        : (isCurrent ? p.accent : p.muted);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: AppMotion.fast,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(
              color: isCurrent || isDone ? p.accent : p.border,
              width: isCurrent ? 1.5 : 1,
            ),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.20),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: isDone
              ? Icon(Icons.check_rounded, size: 13, color: foreground)
              : Text(
                  '$step',
                  style: p.theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: foreground,
                  ),
                ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: p.theme.textTheme.labelSmall?.copyWith(
            fontSize: 9.5,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            color: isCurrent ? p.accent : p.muted,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(AuthPalette p) {
    return Row(
      children: [
        if (_currentStep > 1)
          TextButton.icon(
            onPressed: _isProcessing ? null : _resetSteps,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: Icon(Icons.refresh_rounded, size: 14, color: p.accent),
            label: Text(
              'البدء من جديد',
              style: p.theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                color: p.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        const Spacer(),
        if (_isProcessing)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(
              'إلغاء',
              style: p.theme.textTheme.labelSmall?.copyWith(
                fontSize: 12,
                color: p.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
