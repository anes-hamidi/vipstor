import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../providers/customer_providers.dart';
import 'product_details_sheet.dart';
import 'product_image.dart';
import 'quantity_stepper.dart';

/// Storefront product tile.
///
/// One image, one name, one price. Availability is expressed once, on the
/// image, and the cart control lives in the same place for every tile.
class CatalogProductCard extends ConsumerWidget {
  final ProductEntity product;

  const CatalogProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
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
    final lowStock = available && product.availableQty <= 5;
    final inCart = qty > 0;

    return Semantics(
      container: true,
      button: true,
      label: '${product.nameAr}، ${available ? 'متوفر' : 'نفذ من المخزون'}',
      child: Material(
        color:
            isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.xlAll,
          side: BorderSide(
            color: inCart
                ? scheme.secondary.withValues(alpha: 0.55)
                : scheme.outlineVariant.withValues(alpha: 0.72),
            width: inCart ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => showProductDetailsSheet(context, product),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CatalogProductImage(product: product),
                    if (!available)
                      ColoredBox(
                        color: scheme.scrim.withValues(alpha: 0.40),
                      ),
                    if (!available)
                      Center(
                        child: Container(
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: context.appColors.errorContainer,
                            borderRadius: AppRadius.pillAll,
                          ),
                          child: Text(
                            'نفذ من المخزون',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: context.appColors.onErrorContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (lowStock)
                      PositionedDirectional(
                        top: AppSpacing.sm,
                        start: AppSpacing.sm,
                        child: _StockPill(
                          label: 'آخر ${product.availableQty}',
                          background: context.appColors.warningContainer,
                          foreground: context.appColors.onWarningContainer,
                        ),
                      ),
                    if (available)
                      PositionedDirectional(
                        bottom: AppSpacing.sm,
                        end: AppSpacing.sm,
                        child: qty == 0
                            ? _AddButton(product: product)
                            : CatalogQuantityStepper(
                                compact: true,
                                quantity: qty,
                                maxQuantity: product.availableQty,
                                backgroundColor: scheme.secondary,
                                foregroundColor: scheme.onSecondary,
                                onChanged: (next) => ref
                                    .read(customerCartProvider.notifier)
                                    .updateQuantity(product.id, next),
                              ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.nameAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: available
                              ? scheme.onSurface
                              : scheme.onSurface.withValues(alpha: 0.48),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _metaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: DzdPriceTag(
                          centimes: price,
                          color: scheme.secondary,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _metaLabel {
    final unit = product.unitType.arabicLabel;
    if (product.packSize > 1) return '$unit · عبوة ${product.packSize}';
    return unit;
  }
}

class _AddButton extends ConsumerWidget {
  final ProductEntity product;

  const _AddButton({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'أضف ${product.nameAr} إلى السلة',
      child: Material(
        color: scheme.secondary,
        elevation: 2,
        shadowColor: scheme.shadow.withValues(alpha: 0.28),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              ref.read(customerCartProvider.notifier).addProduct(product),
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.add_rounded,
              size: 23,
              color: scheme.onSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _StockPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}
