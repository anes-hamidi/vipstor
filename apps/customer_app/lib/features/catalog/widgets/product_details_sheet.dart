import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../providers/customer_providers.dart';
import 'product_image.dart';
import 'quantity_stepper.dart';

/// Opens the single product detail sheet used by cards and quick reorder tiles.
Future<void> showProductDetailsSheet(
  BuildContext context,
  ProductEntity product,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProductDetailsSheet(product: product),
  );
}

class _ProductDetailsSheet extends ConsumerWidget {
  final ProductEntity product;

  const _ProductDetailsSheet({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final qty = ref.watch(
      customerCartProvider.select((items) {
        for (final item in items) {
          if (item.product.id == product.id) return item.quantity;
        }
        return 0;
      }),
    );
    final profile = ref.watch(customerProfileProvider);
    final tier = profile.hasAccount ? profile.priceTier : PriceTier.retail;
    final price = product.getPriceForQuantity(tier, 1);
    final available = product.availableQty > 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xxl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.xs,
                0,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.28),
                      borderRadius: AppRadius.pillAll,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 21),
                      style: IconButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant,
                        minimumSize: const Size(44, 44),
                        maximumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.xlAll,
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: CatalogProductImage(product: product),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      product.nameAr,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (product.nameFr.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        product.nameFr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    StockBadge(
                      availableQty: product.availableQty,
                      unitName: product.unitType.arabicLabel,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _PricePanel(
                      price: price,
                      tier: tier,
                      unitLabel: product.unitType.arabicLabel,
                      packSize: product.packSize,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _InfoPill(
                          icon: Icons.category_outlined,
                          label: product.category.isEmpty
                              ? 'عام'
                              : product.category,
                        ),
                        _InfoPill(
                          icon: Icons.scale_outlined,
                          label: product.unitType.arabicLabel,
                        ),
                        if (product.packSize > 1)
                          _InfoPill(
                            icon: Icons.inventory_2_outlined,
                            label: 'عبوة ×${product.packSize}',
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      available
                          ? 'أضفه إلى سلتك وسيُحسب السعر حسب الكمية المطلوبة.'
                          : 'هذا المنتج غير متوفر حالياً. يمكنك متابعة التسوق من بقية المنتجات.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _BottomAction(
              product: product,
              qty: qty,
              available: available,
            ),
          ],
        ),
      ),
    );
  }
}

class _PricePanel extends StatelessWidget {
  final int price;
  final PriceTier tier;
  final String unitLabel;
  final int packSize;

  const _PricePanel({
    required this.price,
    required this.tier,
    required this.unitLabel,
    required this.packSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = tier == PriceTier.retail ? 'سعر التجزئة' : 'سعر الجملة';

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                DzdPriceTag.lg(
                  centimes: price,
                  color: scheme.secondary,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Text(
            packSize > 1 ? 'لكل $unitLabel · ×$packSize' : 'لكل $unitLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends ConsumerWidget {
  final ProductEntity product;
  final int qty;
  final bool available;

  const _BottomAction({
    required this.product,
    required this.qty,
    required this.available,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ref.read(customerCartProvider.notifier);
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: scheme.secondary,
      foregroundColor: scheme.onSecondary,
      minimumSize: const Size(0, 52),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );

    final Widget action;
    if (!available && qty == 0) {
      action = Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: AppRadius.mdAll,
        ),
        child: Text(
          'غير متوفر حالياً',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else if (qty == 0) {
      action = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: buttonStyle,
          onPressed: () {
            notifier.addProduct(product);
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
          label: const Text('أضف للطلبية'),
        ),
      );
    } else {
      action = Row(
        children: [
          CatalogQuantityStepper(
            quantity: qty,
            maxQuantity: product.availableQty,
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            onChanged: (next) => notifier.updateQuantity(product.id, next),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton(
              style: buttonStyle,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('تم'),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: action,
    );
  }
}
