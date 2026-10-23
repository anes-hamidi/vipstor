import 'package:core/core.dart';
import 'package:flutter/material.dart';
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
            ? context.roleTheme.roleBrandColor
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

    // Brand variant: wrap in a subtle role-tinted container for hero/lg sizes
    if (gold && _size == _Size.hero) {
      final brand = context.roleTheme.roleBrandColor;
      return Container(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              theme.colorScheme.surfaceContainerLow,
              brand.withValues(alpha: isDark ? 0.14 : 0.10),
            ],
          ),
          borderRadius: AppRadius.smAll,
          border: Border.all(
            color: brand.withValues(alpha: 0.25),
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
