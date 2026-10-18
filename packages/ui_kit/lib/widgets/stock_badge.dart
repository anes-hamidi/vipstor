import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

/// Stock level indicator badge.
///
/// States: out-of-stock (error), low (warning), in-stock (success).
///
/// ```dart
/// StockBadge(availableQty: product.availableQty)
/// StockBadge(availableQty: product.availableQty, unitName: 'قطعة', compact: true)
/// ```
class StockBadge extends StatelessWidget {
  final int availableQty;
  final int minAlert;
  final String? unitName;
  final bool compact;

  const StockBadge({
    super.key,
    required this.availableQty,
    this.minAlert = 5,
    this.unitName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    Color border;
    IconData icon;
    String label;

    final unitStr = unitName != null ? ' $unitName' : '';

    if (availableQty <= 0) {
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
      border = cs.onErrorContainer.withValues(alpha: 0.25);
      icon = Icons.remove_shopping_cart_outlined;
      label = compact ? 'نفذ' : 'نفذ من المخزون';
    } else if (availableQty <= minAlert) {
      bg = colors.warningContainer;
      fg = colors.onWarningContainer;
      border = colors.onWarningContainer.withValues(alpha: 0.25);
      icon = Icons.warning_amber_rounded;
      label = compact ? '$availableQty$unitStr' : 'قليل: $availableQty$unitStr';
    } else {
      bg = colors.successContainer;
      fg = colors.onSuccessContainer;
      border = colors.onSuccessContainer.withValues(alpha: 0.25);
      icon = Icons.inventory_2_outlined;
      label = compact ? '$availableQty$unitStr' : 'متوفر: $availableQty$unitStr';
    }

    final resolvedBg = isDark
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.15), bg)
        : bg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidget = Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w600,
            color: fg,
            letterSpacing: 0.2,
          ),
        );

        return Container(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: compact ? AppSpacing.sm : AppSpacing.md,
            vertical: compact ? 1.5 : 3.0,
          ),
          decoration: BoxDecoration(
            color: resolvedBg,
            borderRadius: AppRadius.fullAll,
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 11 : 13, color: fg),
              SizedBox(width: compact ? AppSpacing.xxs : AppSpacing.xs),
              if (constraints.hasBoundedWidth)
                Flexible(child: textWidget)
              else
                textWidget,
            ],
          ),
        );
      },
    );
  }
}
