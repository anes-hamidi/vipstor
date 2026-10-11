import 'package:core/core.dart';
import 'package:flutter/material.dart';

class DzdPriceTag extends StatelessWidget {
  final int centimes;
  final TextStyle? style;
  final bool showDecimals;
  final Color? color;

  const DzdPriceTag({
    super.key,
    required this.centimes,
    this.style,
    this.showDecimals = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: color ?? theme.colorScheme.primary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Text(
      DzdFormatter.formatCentimes(centimes, showDecimals: showDecimals),
      style: style != null ? defaultStyle.merge(style) : defaultStyle,
    );
  }
}
