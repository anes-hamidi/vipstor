import 'package:core/core.dart';
import 'package:flutter/material.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GoldButton
// ─────────────────────────────────────────────────────────────────────────────

/// Primary CTA with royal gold gradient, animated glow, and press-down feel.
///
/// ```dart
/// GoldButton(label: 'تأكيد الطلب', onPressed: _submit)
/// GoldButton.icon(icon: Icons.check, label: 'تم', onPressed: _done, width: 200)
/// ```
class GoldButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final double? width;
  final double height;
  final bool compact;

  const GoldButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.width,
    this.height = 48,
    this.compact = false,
  });

  const GoldButton.icon({
    super.key,
    required this.label,
    required IconData this.icon,
    this.onPressed,
    this.loading = false,
    this.width,
    this.height = 48,
    this.compact = false,
  });

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onHover(bool h) {
    h ? _ctrl.forward() : _ctrl.reverse();
  }

  void _onTapDown(_) {
    setState(() => _pressed = true);
  }

  void _onTapUp(_) {
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = context.roleTheme.roleBrandColor;
    final isDisabled = widget.onPressed == null || widget.loading;
    final onBrand = scheme.onPrimary;
    final disabledForeground = scheme.onSurface.withValues(alpha: 0.38);
    final brandGradient = LinearGradient(
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
      colors: [
        Color.lerp(brand, Colors.white, 0.30)!,
        brand,
        Color.lerp(brand, Colors.black, 0.16)!,
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    final ph = widget.compact
        ? const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs)
        : const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md);

    return MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => _onHover(true),
      onExit:  (_) => _onHover(false),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, child) => Transform.scale(
          scale: (_pressed && !isDisabled) ? 0.97 : 1.0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              gradient: isDisabled ? null : brandGradient,
              color: isDisabled ? scheme.surfaceContainerHighest : null,
              boxShadow: isDisabled
                  ? null
                  : [
                      BoxShadow(
                        color: brand.withValues(
                          alpha: 0.24 + 0.24 * _glow.value,
                        ),
                        blurRadius: 10 + 12 * _glow.value,
                        offset: Offset(0, 3 + 3 * _glow.value),
                      ),
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.10),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: child,
          ),
        ),
        child: SizedBox(
          width: widget.width,
          height: widget.compact ? null : widget.height,
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.mdAll,
            child: InkWell(
              onTap: isDisabled ? null : widget.onPressed,
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: () => setState(() => _pressed = false),
              borderRadius: AppRadius.mdAll,
              splashColor: scheme.onPrimary.withValues(alpha: 0.18),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: ph,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: widget.width != null ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (widget.loading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            onBrand.withValues(alpha: 0.70),
                          ),
                        ),
                      )
                    else ...[
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: widget.compact ? 15 : 18,
                            color: isDisabled ? disabledForeground : onBrand),
                        SizedBox(width: widget.compact ? AppSpacing.xs : AppSpacing.sm),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: widget.compact ? 12 : 14,
                            fontWeight: FontWeight.bold,
                            color: isDisabled ? disabledForeground : onBrand,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GoldBadge
// ─────────────────────────────────────────────────────────────────────────────

/// Pill-shaped gold gradient badge — VIP tier labels, role indicators.
class GoldBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool small;

  const GoldBadge({super.key, required this.label, this.icon, this.small = false});

  @override
  Widget build(BuildContext context) {
    final iconSize = small ? 10.0 : 12.0;
    final fontSize = small ? 10.0 : 11.0;
    final role = context.roleTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: role.badgeBackground,
        borderRadius: AppRadius.fullAll,
        border: Border.all(
          color: role.badgeText.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: small ? AppSpacing.sm : AppSpacing.md,
          vertical: small ? 1.5 : 3.0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: iconSize, color: role.badgeText),
              SizedBox(width: small ? AppSpacing.xxs : AppSpacing.xs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: role.badgeText,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SectionHeader
// ─────────────────────────────────────────────────────────────────────────────

/// Gold-accented section heading with an optional trailing action widget.
///
/// ```dart
/// SectionHeader(title: 'المنتجات')
/// SectionHeader(title: 'الطلبات', trailing: TextButton(...))
/// ```
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final bool dense;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = context.roleTheme.roleBrandColor;
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        vertical: dense ? AppSpacing.xs : AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Brand accent bar
          Container(
            width: 3,
            height: dense ? 14 : 18,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(brand, Colors.white, 0.28)!,
                  brand,
                ],
              ),
              borderRadius: AppRadius.fullAll,
              boxShadow: [
                BoxShadow(
                  color: brand.withValues(alpha: 0.28),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: dense ? 12 : 13,
                color: scheme.primary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GoldDivider
// ─────────────────────────────────────────────────────────────────────────────

/// Hairline decorative gold gradient divider.
class GoldDivider extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry? margin;

  const GoldDivider({super.key, this.height = 1.0, this.margin});

  @override
  Widget build(BuildContext context) {
    final brand = context.roleTheme.roleBrandColor;
    final w = Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [
            brand.withValues(alpha: 0.0),
            brand.withValues(alpha: 0.50),
            brand.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
    if (margin != null) return Padding(padding: margin!, child: w);
    return w;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GoldIconButton
// ─────────────────────────────────────────────────────────────────────────────

/// Compact gold-rimmed icon button with hover glow.
class GoldIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool filled;

  const GoldIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36,
    this.filled = false,
  });

  @override
  State<GoldIconButton> createState() => _GoldIconButtonState();
}

class _GoldIconButtonState extends State<GoldIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final brand = context.roleTheme.roleBrandColor;
    final borderColor = brand.withValues(alpha: isDark ? 0.28 : 0.20);

    return MouseRegion(
      onEnter: (_) => _ctrl.forward(),
      onExit:  (_) => _ctrl.reverse(),
      cursor: widget.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: AnimatedBuilder(
        animation: _glow,
        builder: (ctx, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: widget.filled
                ? LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [
                      Color.lerp(brand, Colors.white, 0.26)!,
                      brand,
                    ],
                  )
                : null,
            color: widget.filled
                ? null
                : Color.lerp(
                    Colors.transparent,
                    scheme.primaryContainer.withValues(alpha: 0.55),
                    _glow.value,
                  ),
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: Color.lerp(borderColor, brand, _glow.value)!,
              width: 1,
            ),
            boxShadow: _glow.value > 0.1
                ? [
                    BoxShadow(
                      color: brand.withValues(alpha: 0.20 * _glow.value),
                      blurRadius: 8,
                    )
                  ]
                : null,
          ),
          child: child,
        ),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              widget.icon,
              size: widget.size * 0.50,
              color: widget.filled
                  ? scheme.onPrimary
                  : (isDark ? scheme.primary : brand),
            ),
            tooltip: widget.tooltip,
            onPressed: widget.onPressed,
            splashRadius: widget.size * 0.45,
          ),
        ),
      ),
    );
  }
}
