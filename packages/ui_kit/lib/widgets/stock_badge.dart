import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

class StockBadge extends StatelessWidget {
  final int availableQty;
  final int minAlert;
  final String? unitName;

  const StockBadge({
    super.key,
    required this.availableQty,
    this.minAlert = 5,
    this.unitName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    IconData icon;
    String label;

    final unitStr = unitName != null ? ' $unitName' : '';

    if (availableQty <= 0) {
      bg = colorScheme.errorContainer;
      fg = colorScheme.onErrorContainer;
      icon = Icons.error_outline;
      label = 'نفذ المخزون (Épuisé)';
    } else if (availableQty <= minAlert) {
      bg = colors.warningContainer;
      fg = colors.onWarningContainer;
      icon = Icons.warning_amber_rounded;
      label = 'مخزون منخفض ($availableQty$unitStr)';
    } else {
      bg = colors.successContainer;
      fg = colors.onSuccessContainer;
      icon = Icons.check_circle_outline;
      label = 'متوفر ($availableQty$unitStr)';
    }

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
