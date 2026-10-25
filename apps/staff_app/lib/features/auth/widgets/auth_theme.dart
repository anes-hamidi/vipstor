import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:ui_kit/ui_kit.dart';

/// Theme-derived palette used by the authentication surfaces.
///
/// The login screen and the PIN dialog are rendered before (or outside) a
/// workspace session, so they must not rely on the legacy gold/obsidian
/// aliases. Those aliases are meaningful only for gold-on-obsidian surfaces;
/// using them for body text or page backgrounds breaks contrast as soon as the
/// active role or brightness changes.
///
/// Every value below is derived from the active [ColorScheme] and
/// [RoleThemeExtension], which means:
///
/// * light and dark mode both keep WCAG-friendly text contrast;
/// * the accent follows the active role palette;
/// * decorative tints are blended from the accent instead of being hard-coded.
@immutable
class AuthPalette {
  const AuthPalette({
    required this.theme,
    required this.scheme,
    required this.isDark,
    required this.background,
    required this.panel,
    required this.panelAlt,
    required this.field,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentFaint,
    required this.text,
    required this.muted,
    required this.faint,
    required this.danger,
    required this.dangerSoft,
    required this.success,
    required this.warning,
    required this.shadow,
  });

  factory AuthPalette.of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final AppColors appColors = context.appColors;
    final Color accent = context.roleTheme.roleBrandColor;

    final Color panel = scheme.surfaceContainerLow;
    final Color panelAlt = scheme.surfaceContainer;
    final Color field = Color.alphaBlend(
      scheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.55 : 0.45),
      panel,
    );

    return AuthPalette(
      theme: theme,
      scheme: scheme,
      isDark: isDark,
      background: scheme.surface,
      panel: panel,
      panelAlt: panelAlt,
      field: field,
      border: scheme.outlineVariant.withValues(alpha: isDark ? 0.72 : 0.9),
      borderStrong: scheme.outline.withValues(alpha: isDark ? 0.55 : 0.45),
      accent: accent,
      onAccent: scheme.onPrimary,
      accentSoft: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.16 : 0.10),
        panel,
      ),
      accentFaint: accent.withValues(alpha: isDark ? 0.08 : 0.05),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      faint: scheme.onSurface.withValues(alpha: 0.48),
      danger: scheme.error,
      dangerSoft: Color.alphaBlend(
        scheme.error.withValues(alpha: isDark ? 0.18 : 0.08),
        panel,
      ),
      success: appColors.success,
      warning: appColors.warning,
      shadow: scheme.shadow,
    );
  }

  final ThemeData theme;
  final ColorScheme scheme;
  final bool isDark;

  /// Page backdrop, always a surface token (never an inverse surface).
  final Color background;

  /// Main card / panel surface.
  final Color panel;

  /// Secondary surface for nested rows and action keys.
  final Color panelAlt;

  /// Resting PIN boxes and input fields.
  final Color field;

  final Color border;
  final Color borderStrong;

  /// Role-aware interactive accent.
  final Color accent;
  final Color onAccent;

  /// Low-saturation accent fill for selected rows and focused PIN boxes.
  final Color accentSoft;
  final Color accentFaint;

  final Color text;
  final Color muted;
  final Color faint;

  final Color danger;
  final Color dangerSoft;
  final Color success;
  final Color warning;
  final Color shadow;

  /// Metallic variant of the role accent, used for logos and avatars.
  LinearGradient get accentGradient => LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          Color.lerp(accent, Colors.white, isDark ? 0.22 : 0.30)!,
          accent,
          Color.lerp(accent, Colors.black, 0.14)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      );

  /// Subtle vertical sheen applied to large panels.
  LinearGradient get panelGradient => LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          Color.lerp(panel, accent, isDark ? 0.075 : 0.025)!,
          panel,
          Color.lerp(panel, scheme.surfaceContainerHigh, isDark ? 0.35 : 0.45)!,
        ],
        stops: const [0.0, 0.45, 1.0],
      );

  /// Page backdrop with an accent bloom at the top and a neutral fade below.
  LinearGradient get backdropGradient => LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          Color.lerp(background, accent, isDark ? 0.10 : 0.035)!,
          background,
          Color.lerp(
            background,
            scheme.surfaceContainerHigh,
            isDark ? 0.30 : 0.60,
          )!,
        ],
        stops: const [0.0, 0.42, 1.0],
      );

  List<BoxShadow> get panelShadow => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.42 : 0.10),
          blurRadius: isDark ? 30 : 24,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: accent.withValues(alpha: isDark ? 0.10 : 0.07),
          blurRadius: 24,
          offset: const Offset(0, 4),
        ),
      ];

  List<BoxShadow> get accentGlow => [
        BoxShadow(
          color: accent.withValues(alpha: isDark ? 0.34 : 0.24),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.30 : 0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
}

extension AuthPaletteContext on BuildContext {
  AuthPalette get authPalette => AuthPalette.of(this);
}

/// Ambient, theme-aware backdrop shared by every authentication surface.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AuthPalette p = context.authPalette;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: p.backdropGradient),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          PositionedDirectional(
            top: -170,
            end: -130,
            child: _AmbientOrb(
              size: 420,
              color: p.accent.withValues(alpha: p.isDark ? 0.18 : 0.09),
            ),
          ),
          PositionedDirectional(
            bottom: -210,
            start: -160,
            child: _AmbientOrb(
              size: 500,
              color: p.scheme.secondary.withValues(
                alpha: p.isDark ? 0.10 : 0.06,
              ),
            ),
          ),
          PositionedDirectional(
            bottom: -40,
            end: -30,
            child: IgnorePointer(
              child: Icon(
                Icons.lock_outline_rounded,
                size: 280,
                color: p.text.withValues(alpha: p.isDark ? 0.025 : 0.018),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Elevated panel with a themed sheen, hairline border and soft glow.
class AuthPanel extends StatelessWidget {
  const AuthPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = AppRadius.xxl,
    this.showAccentEdge = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool showAccentEdge;

  @override
  Widget build(BuildContext context) {
    final AuthPalette p = context.authPalette;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: p.panelGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.border),
        boxShadow: p.panelShadow,
      ),
      child: Stack(
        children: [
          if (showAccentEdge)
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.accent.withValues(alpha: 0.0),
                      p.accent.withValues(alpha: 0.65),
                      p.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Compact status capsule used for connectivity and session hints.
class AuthStatusPill extends StatelessWidget {
  const AuthStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AuthPalette p = context.authPalette;

    final Widget dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6),
        ],
      ),
    );

    final Widget pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.12), p.panel),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: AppSpacing.xs),
          ] else ...[
            dot,
            if (!compact) const SizedBox(width: 6),
          ],
          if (!compact)
            Text(
              label,
              style: p.theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 10.5,
              ),
            ),
        ],
      ),
    );

    return compact ? Tooltip(message: label, child: pill) : pill;
  }
}

/// Consistent four-box PIN input used by login and PIN-management dialogs.
class AuthPinField extends StatelessWidget {
  const AuthPinField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onCompleted,
    this.onChanged,
    this.isError = false,
    this.obscuringCharacter = '●',
    this.fieldWidth = 52,
    this.fieldHeight = 56,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool isError;
  final String obscuringCharacter;
  final double fieldWidth;
  final double fieldHeight;

  @override
  Widget build(BuildContext context) {
    final AuthPalette p = context.authPalette;

    final TextStyle pinStyle =
        (p.theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: isError ? p.danger : p.accent,
      letterSpacing: 2,
    );

    final PinTheme resting = PinTheme(
      width: fieldWidth,
      height: fieldHeight,
      textStyle: pinStyle,
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: p.border),
      ),
    );

    final PinTheme focused = resting.copyWith(
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: p.accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: p.accent.withValues(alpha: p.isDark ? 0.30 : 0.22),
            blurRadius: 14,
          ),
        ],
      ),
    );

    final PinTheme error = resting.copyWith(
      textStyle: pinStyle.copyWith(color: p.danger),
      decoration: BoxDecoration(
        color: p.dangerSoft,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: p.danger, width: 1.6),
      ),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Pinput(
        controller: controller,
        focusNode: focusNode,
        autofocus: false,
        useNativeKeyboard: false,
        showCursor: false,
        length: 4,
        obscureText: true,
        obscuringCharacter: obscuringCharacter,
        defaultPinTheme: isError ? error : resting,
        focusedPinTheme: isError ? error : focused,
        errorPinTheme: error,
        hapticFeedbackType: HapticFeedbackType.mediumImpact,
        onCompleted: onCompleted,
        onChanged: onChanged,
      ),
    );
  }
}

/// Shared tactile numeric keypad.
///
/// [clearLabel] and [backspaceLabel] are configurable so both the login screen
/// and the change-PIN dialog keep their established labels. When
/// [backspaceLabel] is null a backspace icon is rendered instead.
class AuthNumericKeypad extends StatelessWidget {
  const AuthNumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    this.clearLabel = 'مسح',
    this.backspaceLabel,
    this.maxWidth = 290,
    this.keyHeight = 46,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final String clearLabel;
  final String? backspaceLabel;
  final double maxWidth;
  final double keyHeight;
  final bool enabled;

  static const List<List<String>> _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['C', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int row = 0; row < _rows.length; row++) ...[
              Row(
                children: [
                  for (int col = 0; col < _rows[row].length; col++) ...[
                    if (col > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _AuthKeypadKey(
                        label: _rows[row][col],
                        isClear: _rows[row][col] == 'C',
                        isBackspace: _rows[row][col] == '⌫',
                        clearLabel: clearLabel,
                        backspaceLabel: backspaceLabel,
                        height: keyHeight,
                        enabled: enabled,
                        onTap: switch (_rows[row][col]) {
                          'C' => onClear,
                          '⌫' => onBackspace,
                          final String digit => () => onDigit(digit),
                        },
                      ),
                    ),
                  ],
                ],
              ),
              if (row < _rows.length - 1) const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuthKeypadKey extends StatefulWidget {
  const _AuthKeypadKey({
    required this.label,
    required this.isClear,
    required this.isBackspace,
    required this.clearLabel,
    required this.backspaceLabel,
    required this.height,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool isClear;
  final bool isBackspace;
  final String clearLabel;
  final String? backspaceLabel;
  final double height;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_AuthKeypadKey> createState() => _AuthKeypadKeyState();
}

class _AuthKeypadKeyState extends State<_AuthKeypadKey> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final AuthPalette p = context.authPalette;
    final bool isAction = widget.isClear || widget.isBackspace;

    final Color background =
        _pressed ? p.accentSoft : (isAction ? p.panelAlt : p.field);
    final Color border =
        _pressed ? p.accent : (isAction ? p.border : p.borderStrong);

    final Widget child;
    if (widget.isClear) {
      child = Text(
        widget.clearLabel,
        style: p.theme.textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: p.danger,
        ),
      );
    } else if (widget.isBackspace && widget.backspaceLabel == null) {
      child = Icon(Icons.backspace_outlined, size: 18, color: p.accent);
    } else if (widget.isBackspace) {
      child = Text(
        widget.backspaceLabel!,
        style: p.theme.textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: p.muted,
        ),
      );
    } else {
      child = Text(
        widget.label,
        style: p.theme.textTheme.headlineSmall?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.isClear
          ? 'مسح الرمز'
          : (widget.isBackspace ? 'حذف رقم' : widget.label),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: widget.enabled ? widget.onTap : null,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onHover: (hovering) => _setPressed(hovering),
          child: AnimatedOpacity(
            duration: AppMotion.fast,
            opacity: widget.enabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.moveCurve,
              height: widget.height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: border),
                boxShadow: _pressed
                    ? [
                        BoxShadow(
                          color: p.accent.withValues(alpha: 0.22),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded inline error banner shared by both auth surfaces.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AuthPalette p = context.authPalette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: p.dangerSoft,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: p.danger.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: p.danger),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: p.theme.textTheme.labelSmall?.copyWith(
                color: p.danger,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
