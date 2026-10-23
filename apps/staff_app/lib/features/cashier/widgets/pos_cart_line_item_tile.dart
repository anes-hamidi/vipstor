import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../models/pos_models.dart';

/// Responsive cart line-item tile.
///
/// - Phone  (compact):  stacked layout, larger touch targets (48dp)
/// - Tablet (medium):   single-row with inline stepper
/// - Desktop (expanded+): compact single-row, dense spacing
class PosCartLineItemTile extends StatelessWidget {
  final PosCartItem item;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<PosItemUnit> onUnitChanged;
  final ValueChanged<PriceTier> onTierChanged;
  final VoidCallback onEditDiscount;
  final VoidCallback onRemove;

  const PosCartLineItemTile({
    super.key,
    required this.item,
    required this.onQuantityChanged,
    required this.onUnitChanged,
    required this.onTierChanged,
    required this.onEditDiscount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use stacked layout on phones or inside narrow cart panels (< 520px)
        final useStacked = constraints.hasBoundedWidth
            ? constraints.maxWidth < 520
            : context.isCompact;

        return useStacked
            ? _PhoneTile(
                item: item,
                onQuantityChanged: onQuantityChanged,
                onUnitChanged: onUnitChanged,
                onTierChanged: onTierChanged,
                onEditDiscount: onEditDiscount,
                onRemove: onRemove,
              )
            : _DesktopTile(
                item: item,
                onQuantityChanged: onQuantityChanged,
                onUnitChanged: onUnitChanged,
                onTierChanged: onTierChanged,
                onEditDiscount: onEditDiscount,
                onRemove: onRemove,
              );
      },
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _QuantityStepper extends StatelessWidget {
  final int qty;
  final bool large;
  final ValueChanged<int> onChange;

  const _QuantityStepper({
    required this.qty,
    required this.onChange,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = context.roleTheme.roleBrandColor;
    final size = large ? 36.0 : 28.0;
    final fontSize = large ? 14.0 : 12.0;

    return Container(
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: brand.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(
            icon: Icons.remove_rounded,
            size: size,
            onTap: () => onChange(qty - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '$qty',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize,
                  color: brand),
            ),
          ),
          _StepBtn(
            icon: Icons.add_rounded,
            size: size,
            onTap: () => onChange(qty + 1),
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _StepBtn({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smAll,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon,
              size: size * 0.45, color: context.roleTheme.roleBrandColor),
        ),
      );
}

class _DiscountChip extends StatelessWidget {
  final PosCartItem item;
  final VoidCallback onTap;
  final bool large;
  const _DiscountChip(
      {required this.item, required this.onTap, this.large = false});

  @override
  Widget build(BuildContext context) {
    final hasDiscount =
        item.discountPercent > 0 || item.manualDiscountCentimes > 0;
    final h = large ? 36.0 : 28.0;

    final cs = Theme.of(context).colorScheme;
    final brand = context.roleTheme.roleBrandColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: h,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hasDiscount
              ? brand.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color:
                hasDiscount ? brand.withValues(alpha: 0.55) : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.discount_rounded,
              size: large ? 14 : 12,
              color: hasDiscount ? brand : cs.onSurfaceVariant,
            ),
            if (hasDiscount) ...[
              const SizedBox(width: 4),
              Text(
                item.discountPercent > 0
                    ? '-${item.discountPercent.toStringAsFixed(0)}%'
                    : '-${DzdFormatter.formatCentimes(item.manualDiscountCentimes)}',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: brand),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnitPill extends StatelessWidget {
  final PosCartItem item;
  final ValueChanged<PosItemUnit> onChanged;
  final bool large;
  const _UnitPill(
      {required this.item, required this.onChanged, this.large = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = context.roleTheme.roleBrandColor;
    final h = large ? 36.0 : 28.0;

    return Container(
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: brand.withValues(alpha: 0.25)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PosItemUnit>(
          value: item.unit,
          isDense: true,
          icon: Icon(Icons.expand_more_rounded,
              size: 14, color: brand.withValues(alpha: 0.7)),
          style: TextStyle(
              fontSize: large ? 12 : 11,
              fontWeight: FontWeight.bold,
              color: cs.onSurface),
          items: PosItemUnit.values
              .map((u) => DropdownMenuItem(value: u, child: Text(u.label)))
              .toList(),
          onChanged: (u) {
            if (u != null) onChanged(u);
          },
        ),
      ),
    );
  }
}

// ── Tier pill ─────────────────────────────────────────────────────────────────

/// Three-chip selector for Retail / Wholesale / Bulk tiers.
/// Hidden for custom items or products with no tier data.
class _TierPill extends StatelessWidget {
  final PosCartItem item;
  final ValueChanged<PriceTier> onChanged;
  final bool large;

  const _TierPill(
      {required this.item, required this.onChanged, this.large = false});

  static String _label(PriceTier t) {
    switch (t) {
      case PriceTier.retail:
        return 'تجزئة';
      case PriceTier.wholesale:
        return 'جملة';
      case PriceTier.bulk:
        return 'كميات';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show when the product has multi-tier pricing data
    if (item.isCustomItem || item.availableTiers.isEmpty) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final brand = context.roleTheme.roleBrandColor;
    final active = item.activeTier ?? PriceTier.wholesale;
    final h = large ? 36.0 : 28.0;
    final fontSize = large ? 11.0 : 10.0;

    return Container(
      height: h,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: brand.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: PriceTier.values.map((tier) {
          final isActive = tier == active;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isActive ? null : () => onChanged(tier),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: h,
              padding: EdgeInsets.symmetric(horizontal: large ? 10 : 7),
              decoration: BoxDecoration(
                color: isActive ? brand : null,
                borderRadius: AppRadius.smAll,
              ),
              child: Center(
                child: Text(
                  _label(tier),
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Phone tile — stacked, large touch targets ──────────────────────────────────

class _PhoneTile extends StatelessWidget {
  final PosCartItem item;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<PosItemUnit> onUnitChanged;
  final ValueChanged<PriceTier> onTierChanged;
  final VoidCallback onEditDiscount;
  final VoidCallback onRemove;

  const _PhoneTile({
    required this.item,
    required this.onQuantityChanged,
    required this.onUnitChanged,
    required this.onTierChanged,
    required this.onEditDiscount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brand = context.roleTheme.roleBrandColor;

    return Container(
      margin: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: brand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: name + remove
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Role index circle
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: brand,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      item.isCustomItem
                          ? Icons.edit_note_rounded
                          : Icons.shopping_cart_rounded,
                      size: 14,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nameAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        '${DzdFormatter.formatCentimes(item.effectiveUnitPriceCentimes)} / ${item.unit.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: brand.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Remove button — large tap target
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.appColors.error.withValues(alpha: 0.10),
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Icon(Icons.delete_rounded,
                        size: 18, color: context.appColors.error),
                  ),
                ),
              ],
            ),
          ),

          // Options row: unit + tier + discount
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _UnitPill(item: item, onChanged: onUnitChanged, large: false),
                _TierPill(item: item, onChanged: onTierChanged, large: false),
                _DiscountChip(item: item, onTap: onEditDiscount, large: false),
              ],
            ),
          ),

          // Bottom row: stepper + total
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.xs + 2, AppSpacing.md, AppSpacing.md),
            child: Row(
              children: [
                _QuantityStepper(
                    qty: item.quantity,
                    onChange: onQuantityChanged,
                    large: false),
                const Spacer(),
                DzdPriceTag(
                  centimes: item.lineTotalCentimes,
                  gold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Desktop/Tablet tile — compact single row ───────────────────────────────────

class _DesktopTile extends StatefulWidget {
  final PosCartItem item;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<PosItemUnit> onUnitChanged;
  final ValueChanged<PriceTier> onTierChanged;
  final VoidCallback onEditDiscount;
  final VoidCallback onRemove;

  const _DesktopTile({
    required this.item,
    required this.onQuantityChanged,
    required this.onUnitChanged,
    required this.onTierChanged,
    required this.onEditDiscount,
    required this.onRemove,
  });

  @override
  State<_DesktopTile> createState() => _DesktopTileState();
}

class _DesktopTileState extends State<_DesktopTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = context.appColors;
    final brand = context.roleTheme.roleBrandColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsetsDirectional.symmetric(vertical: 2),
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: _hovered ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: brand.withValues(alpha: _hovered ? 0.45 : 0.18),
          ),
        ),
        child: Row(
          children: [
            // Name + price
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.nameAr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '${DzdFormatter.formatCentimes(widget.item.effectiveUnitPriceCentimes)} / ${widget.item.unit.label}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: brand.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Unit pill
            _UnitPill(item: widget.item, onChanged: widget.onUnitChanged),
            const SizedBox(width: AppSpacing.sm),
            // Tier selector
            _TierPill(item: widget.item, onChanged: widget.onTierChanged),
            const SizedBox(width: AppSpacing.sm),
            // Discount chip
            _DiscountChip(item: widget.item, onTap: widget.onEditDiscount),
            const SizedBox(width: AppSpacing.sm),
            // Stepper
            _QuantityStepper(
                qty: widget.item.quantity, onChange: widget.onQuantityChanged),
            const SizedBox(width: AppSpacing.sm),
            // Line total
            SizedBox(
              width: 90,
              child: DzdPriceTag(
                centimes: widget.item.lineTotalCentimes,
                gold: true,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            // Remove
            AnimatedOpacity(
              opacity: _hovered ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: widget.onRemove,
                child: Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: AppSpacing.sm),
                  child:
                      Icon(Icons.close_rounded, size: 16, color: colors.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
