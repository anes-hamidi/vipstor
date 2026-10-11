import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../models/pos_models.dart';

class PosCartLineItemTile extends StatelessWidget {
  final PosCartItem item;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<PosItemUnit> onUnitChanged;
  final VoidCallback onEditDiscount;
  final VoidCallback onRemove;

  const PosCartLineItemTile({
    super.key,
    required this.item,
    required this.onQuantityChanged,
    required this.onUnitChanged,
    required this.onEditDiscount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final hasDiscount = item.discountPercent > 0 || item.manualDiscountCentimes > 0;

    return Container(
      margin: const EdgeInsetsDirectional.symmetric(vertical: 3),
      padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Title + Remove Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nameAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Row(
                      children: [
                        Text(
                          '${DzdFormatter.formatCentimes(item.effectiveUnitPriceCentimes)} / ${item.unit.label}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (item.unitsPerPack > 1 && item.unit != PosItemUnit.piece) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(${item.unitMultiplier} قطع)',
                            style: TextStyle(fontSize: 10, color: colorScheme.secondary),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onRemove,
                borderRadius: AppRadius.pillAll,
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(4),
                  child: Icon(Icons.close, size: 16, color: colorScheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: Controls (Unit selector, Discount chip, Quantity Stepper, Line Total)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Unit Dropdown Pill
              Container(
                height: 28,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PosItemUnit>(
                    value: item.unit,
                    isDense: true,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    items: PosItemUnit.values.map((u) {
                      return DropdownMenuItem(value: u, child: Text(u.label));
                    }).toList(),
                    onChanged: (u) {
                      if (u != null) onUnitChanged(u);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Discount Action Chip
              InkWell(
                onTap: onEditDiscount,
                borderRadius: AppRadius.smAll,
                child: Container(
                  height: 28,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasDiscount ? colors.warningContainer : colorScheme.surfaceContainer,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(
                      color: hasDiscount ? colors.warning : colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.discount_outlined,
                        size: 12,
                        color: hasDiscount ? colors.onWarningContainer : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        hasDiscount
                            ? (item.discountPercent > 0 ? '-${item.discountPercent}%' : '-${item.manualDiscountCentimes ~/ 100} دج')
                            : 'تخفيض',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: hasDiscount ? colors.onWarningContainer : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Quantity Stepper
              Container(
                height: 28,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => onQuantityChanged(item.quantity - 1),
                      borderRadius: AppRadius.smAll,
                      child: const Padding(
                        padding: EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 4),
                        child: Icon(Icons.remove, size: 14),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    InkWell(
                      onTap: () => onQuantityChanged(item.quantity + 1),
                      borderRadius: AppRadius.smAll,
                      child: const Padding(
                        padding: EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 4),
                        child: Icon(Icons.add, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Line Total
              SizedBox(
                width: 80,
                child: DzdPriceTag(
                  centimes: item.lineTotalCentimes,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
