import 'package:core/core.dart';
import 'package:flutter/material.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_shadows.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LuxuryCard
// ─────────────────────────────────────────────────────────────────────────────

/// Premium gold-bordered card with adaptive shadow and optional gold accent.
///
/// Variants:
///  - default — standard surface card with hairline gold border.
///  - [LuxuryCard.glass] — glassmorphic translucent panel.
///  - [LuxuryCard.obsidian] — deep dark card with gold rim (dark-mode hero panels).
///  - [goldAccent] — shows a 3dp top gold foil stripe.
///
/// ```dart
/// LuxuryCard(child: Text('Hello'), padding: AppSpacing.pLg)
/// LuxuryCard.glass(child: Text('Overlay'))
/// ```
class LuxuryCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final VoidCallback? onTap;
  final bool goldAccent;
  final bool _glass;
  final bool _obsidian;
  final bool selected;
  final double? elevation;

  const LuxuryCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.color,
    this.onTap,
    this.goldAccent = false,
    this.selected   = false,
    this.elevation,
  })  : _glass    = false,
        _obsidian = false;

  const LuxuryCard.glass({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.selected = false,
    this.elevation,
  })  : color      = null,
        goldAccent = false,
        _glass     = true,
        _obsidian  = false;

  const LuxuryCard.obsidian({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.goldAccent = false,
    this.selected   = false,
    this.elevation,
  })  : color     = null,
        _glass    = false,
        _obsidian = true;

  @override
  State<LuxuryCard> createState() => _LuxuryCardState();
}

class _LuxuryCardState extends State<LuxuryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _hover;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _hover = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
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
    final radius = widget.borderRadius ?? AppRadius.lgAll;

    // Resolve surface color from the active role scheme.
    Color bgColor;
    if (widget._glass) {
      bgColor = Colors.transparent;
    } else if (widget._obsidian) {
      bgColor = widget.color ?? scheme.surfaceContainerHighest;
    } else {
      bgColor = widget.color ?? scheme.surfaceContainerLow;
    }

    // Resolve border color.
    Color borderColor;
    if (widget.selected) {
      borderColor = brand;
    } else if (widget._obsidian) {
      borderColor = brand.withValues(alpha: isDark ? 0.30 : 0.24);
    } else {
      borderColor = scheme.outlineVariant;
    }

    // Shadows
    List<BoxShadow> shadows;
    if (widget._glass) {
      shadows = <BoxShadow>[];
    } else if (widget._obsidian || isDark) {
      shadows = widget.selected
          ? AppShadows.cardElevatedDark
          : AppShadows.cardSoftDark;
    } else {
      shadows = widget.selected
          ? AppShadows.cardElevatedLight
          : AppShadows.cardSoftLight;
    }
    if (widget.selected) {
      shadows = <BoxShadow>[
        ...shadows,
        BoxShadow(
          color: brand.withValues(alpha: 0.20),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
    }

    return MouseRegion(
      onEnter: (_) { if (widget.onTap != null) _ctrl.forward(); },
      onExit:  (_) => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _hover,
        builder: (ctx, child) {
          final extraBorder = widget.selected ? 0.0 : (_hover.value * 1.0);
          return DecoratedBox(
            decoration: BoxDecoration(
              color: widget._glass ? null : bgColor,
              gradient: widget._glass
                  ? LinearGradient(
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                      colors: [
                        scheme.surfaceContainerHighest.withValues(
                          alpha: isDark ? 0.42 : 0.78,
                        ),
                        scheme.surfaceContainerLowest.withValues(
                          alpha: isDark ? 0.18 : 0.52,
                        ),
                      ],
                    )
                  : null,
              borderRadius: radius,
              border: Border.all(
                color: Color.lerp(
                    borderColor,
                    brand,
                    widget.selected ? 1.0 : _hover.value * 0.6)!,
                width: 1.0 + extraBorder,
              ),
              boxShadow: shadows,
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: radius,
              highlightColor: brand.withValues(alpha: 0.06),
              splashColor: brand.withValues(alpha: 0.10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand foil accent stripe
                  if (widget.goldAccent)
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [
                            brand,
                            Color.lerp(brand, Colors.white, 0.42)!,
                            brand,
                          ],
                        ),
                      ),
                    ),
                  if (widget.padding != null)
                    Padding(padding: widget.padding!, child: widget.child)
                  else
                    widget.child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
