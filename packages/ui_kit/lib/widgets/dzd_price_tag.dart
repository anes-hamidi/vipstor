import 'package:core/core.dart';
import 'package:flutter/material.dart';
import '../tokens/app_gradients.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

/// Formatted DZD price display widget.
///
/// Sizes: [DzdPriceTag.sm] · [DzdPriceTag] (default) · [DzdPriceTag.lg] · [DzdPriceTag.hero]
///
/// ```dart
/// DzdPriceTag(centimes: wholesalePrice)
/// DzdPriceTag.lg(centimes: totalCentimes, gold: true)
/// ```
class DzdPriceTag extends StatelessWidget {
  final int centimes;
  final TextStyle? style;
  final bool showDecimals;
  final Color? color;
  final bool gold;
  final _Size _size;

  const DzdPriceTag({
    super.key,
    required this.centimes,
    this.style,
    this.showDecimals = true,
    this.color,
    this.gold = false,
  }) : _size = _Size.md;

  const DzdPriceTag.sm({
    super.key,
    required this.centimes,
    this.style,
    this.showDecimals = true,
    this.color,
    this.gold = false,
  }) : _size = _Size.sm;

  const DzdPriceTag.lg({
    super.key,
    required this.centimes,
    this.style,
    this.showDecimals = true,
    this.color,
    this.gold = false,
  }) : _size = _Size.lg;

  const DzdPriceTag.hero({
    super.key,
    required this.centimes,
    this.style,
    this.showDecimals = true,
    this.color,
    this.gold = false,
  }) : _size = _Size.hero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fontSize = switch (_size) {
      _Size.sm   => 12.0,
      _Size.md   => 15.0,
      _Size.lg   => 20.0,
      _Size.hero => 28.0,
    };

    final resolvedColor = color ??
        (gold
            ? (isDark ? const Color(0xFFF3D278) : const Color(0xFFC59B27))
            : theme.colorScheme.primary);

    final defaultStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      color: resolvedColor,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
    );

    final text = Text(
      DzdFormatter.formatCentimes(centimes, showDecimals: showDecimals),
      style: style != null ? defaultStyle.merge(style) : defaultStyle,
    );

    // Gold variant: wrap in a subtle gold shimmer container for hero/lg sizes
    if (gold && _size == _Size.hero) {
      return Container(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          gradient: AppGradients.goldSubtleLight,
          borderRadius: AppRadius.smAll,
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: text,
      );
    }

    return text;
  }
}

enum _Size { sm, md, lg, hero }
