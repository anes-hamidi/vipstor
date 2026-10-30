import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Compact quantity control shared by the catalogue card and the detail sheet.
///
/// Every step is a 44 dp target so the control stays usable on small phones
/// without making the product card visually heavy.
class CatalogQuantityStepper extends StatelessWidget {
  final int quantity;
  final int maxQuantity;
  final ValueChanged<int> onChanged;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? disabledColor;
  final bool compact;

  const CatalogQuantityStepper({
    super.key,
    required this.quantity,
    required this.maxQuantity,
    required this.onChanged,
    required this.backgroundColor,
    required this.foregroundColor,
    this.disabledColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = compact ? 44.0 : 48.0;
    final disabled = (disabledColor ?? foregroundColor).withValues(alpha: 0.38);
    final canAdd = quantity < maxQuantity;

    return Material(
      color: backgroundColor,
      borderRadius: AppRadius.pillAll,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              tooltip: quantity == 1 ? 'حذف من السلة' : 'إنقاص الكمية',
              icon: quantity == 1
                  ? Icons.delete_outline_rounded
                  : Icons.remove_rounded,
              color: foregroundColor,
              size: height,
              onPressed: () => onChanged(quantity - 1),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 22),
              child: Semantics(
                label: 'الكمية في السلة: $quantity',
                child: Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _StepButton(
              tooltip: 'زيادة الكمية',
              icon: Icons.add_rounded,
              color: canAdd ? foregroundColor : disabled,
              size: height,
              onPressed: canAdd ? () => onChanged(quantity + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onPressed;

  const _StepButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.size,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }
}
