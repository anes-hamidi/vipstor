import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';

/// Minimized, responsive modal dialog for changing a staff member's 4-digit PIN.
///
/// Features:
/// - Disables native system keyboard pop-up (`useNativeKeyboard: false`).
/// - Full on-screen tactile numpad + physical keyboard shortcut support.
/// - Compact, responsive layout adapted for Mobile, Tablet, and Desktop.
/// - Sleek VIP Gold & Obsidian design language.
class ChangePinDialog extends ConsumerStatefulWidget {
  final UserEntity staffMember;

  const ChangePinDialog({
    super.key,
    required this.staffMember,
  });

  /// Opens the change PIN dialog with full responsiveness.
  static Future<bool?> show(
    BuildContext context, {
    required UserEntity staffMember,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => ChangePinDialog(staffMember: staffMember),
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
      _pinController.text =
          _pinController.text.substring(0, _pinController.text.length - 1);
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
      } else {
        setState(() {
          _errorMessage = 'رمز PIN الحالي غير صحيح!';
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
        ref.invalidate(liveStaffUsersProvider);
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'تم تغيير رمز PIN للمستخدم "${widget.staffMember.name}" بنجاح!',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
    final colors = context.appColors;

    // Pin theme definitions
    final defaultPinTheme = PinTheme(
      width: 46,
      height: 48,
      textStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: colors.gold,
      ),
      decoration: BoxDecoration(
        color: colors.obsidianCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.goldBorder.withValues(alpha: 0.6)),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: colors.obsidianCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.gold, width: 1.8),
        boxShadow: const [AppShadows.goldGlowSm],
      ),
    );

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.error, width: 1.8),
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

    // Hardware Keyboard shortcuts
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
          backgroundColor: colors.obsidianSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: colors.goldBorder.withValues(alpha: 0.5)),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.password_rounded,
                                color: colors.gold, size: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'تغيير رمز PIN',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colors.onGold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18,
                            color: colors.onGold.withValues(alpha: 0.6)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(
                      color: colors.goldBorder.withValues(alpha: 0.3),
                      height: 1),
                  const SizedBox(height: 12),

                  // Step indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStepDot(1, 'القديم', colors),
                      Container(
                        width: 24,
                        height: 2,
                        color: _currentStep > 1
                            ? colors.gold
                            : colors.goldBorder.withValues(alpha: 0.4),
                      ),
                      _buildStepDot(2, 'الجديد', colors),
                      Container(
                        width: 24,
                        height: 2,
                        color: _currentStep > 2
                            ? colors.gold
                            : colors.goldBorder.withValues(alpha: 0.4),
                      ),
                      _buildStepDot(3, 'التأكيد', colors),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Title and Subtitle
                  Text(
                    stepTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: colors.onGold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stepSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onGold.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Pinput 4-Digit Field (Native Keyboard Suppressed)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Pinput(
                      controller: _pinController,
                      focusNode: _focusNode,
                      autofocus: false,
                      useNativeKeyboard: false, // Prevents system clavier popup
                      showCursor: false,
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
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 14, color: colors.error),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.error,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Virtual Keypad
                  _buildKeypad(colors),

                  const SizedBox(height: 10),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 1)
                        TextButton.icon(
                          onPressed: _resetSteps,
                          icon: Icon(Icons.refresh_rounded,
                              size: 14, color: colors.gold),
                          label: Text(
                            'البدء من جديد',
                            style: TextStyle(fontSize: 11, color: colors.gold),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      if (_isProcessing)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(colors.gold),
                          ),
                        )
                      else
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            'إلغاء',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onGold.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepDot(int step, String label, AppColors colors) {
    final isDone = _currentStep > step;
    final isCurrent = _currentStep == step;

    Color bg = colors.obsidianCard;
    Color fg = colors.onGold.withValues(alpha: 0.5);
    if (isDone) {
      bg = colors.gold;
      fg = const Color(0xFF1A1400);
    } else if (isCurrent) {
      bg = colors.gold.withValues(alpha: 0.2);
      fg = colors.gold;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: isCurrent
                ? Border.all(color: colors.gold, width: 1.5)
                : Border.all(color: colors.goldBorder.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check, size: 12, color: Color(0xFF1A1400))
              : Text(
                  '$step',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isCurrent ? colors.gold : colors.onGold.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildKeypad(AppColors colors) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) {
                final isAction = key == 'C' || key == '⌫';
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    if (key == 'C') {
                      _clear();
                    } else if (key == '⌫') {
                      _backspace();
                    } else {
                      _appendDigit(key);
                    }
                  },
                  child: Container(
                    width: 66,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isAction
                          ? colors.obsidianSurface
                          : colors.obsidianCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isAction
                            ? colors.goldBorder.withValues(alpha: 0.35)
                            : colors.goldBorder.withValues(alpha: 0.5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      key,
                      style: TextStyle(
                        fontSize: isAction ? 14 : 16,
                        fontWeight: FontWeight.bold,
                        color: isAction
                            ? (key == 'C' ? colors.error : colors.gold)
                            : colors.onGold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
