import 'package:flutter/material.dart';
import '../tokens/app_gradients.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = widget.borderRadius ?? AppRadius.lgAll;

    // Resolve surface color
    Color bgColor;
    if (widget._glass) {
      bgColor = Colors.transparent;
    } else if (widget._obsidian) {
      bgColor = widget.color ?? const Color(0xFF1A1814);
    } else {
      bgColor = widget.color ??
          (isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8));
    }

    // Resolve border color
    Color borderColor;
    if (widget.selected) {
      borderColor = const Color(0xFFD4AF37);
    } else if (widget._obsidian || isDark) {
      borderColor = const Color(0x38D4AF37);
    } else {
      borderColor = const Color(0x28C59B27);
    }

    // Shadows
    List<BoxShadow> shadows;
    if (widget._glass) {
      shadows = [];
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
      shadows = [...shadows, AppShadows.goldGlow];
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
                  ? (isDark ? AppGradients.darkGlass : AppGradients.lightGlass)
                  : null,
              borderRadius: radius,
              border: Border.all(
                color: Color.lerp(
                    borderColor,
                    const Color(0xFFD4AF37),
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
              highlightColor: const Color(0xFFD4AF37).withValues(alpha: 0.06),
              splashColor:    const Color(0xFFD4AF37).withValues(alpha: 0.10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Gold foil accent stripe
                  if (widget.goldAccent)
                    Container(
                      height: 3,
                      decoration: const BoxDecoration(
                        gradient: AppGradients.goldFoil,
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
