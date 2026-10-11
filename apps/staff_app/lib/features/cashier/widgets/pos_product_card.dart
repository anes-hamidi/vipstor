import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';

class PosProductCard extends StatelessWidget {
  final ProductEntity product;
  final int cartQuantity;
  final VoidCallback? onAddToCart;

  const PosProductCard({
    super.key,
    required this.product,
    this.cartQuantity = 0,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final wholesalePrice = product.getPriceForQuantity(PriceTier.wholesale, 1);
    final isAvailable = product.availableQty > 0;
    final isLowStock = isAvailable && product.availableQty <= 5;
    final inCart = cartQuantity > 0;

    return Card(
      elevation: inCart ? 2 : 0,
      color: inCart ? colorScheme.primaryContainer.withValues(alpha: 0.18) : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(
          color: inCart
              ? colorScheme.primary
              : (isAvailable ? colorScheme.outlineVariant.withValues(alpha: 0.7) : colorScheme.outlineVariant),
          width: inCart ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isAvailable ? onAddToCart : null,
        borderRadius: AppRadius.lgAll,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header: Stock Pill + In-Cart Quantity Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Stock status
                  Flexible(
                    child: Container(
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: !isAvailable
                            ? colorScheme.errorContainer
                            : (isLowStock ? colors.warningContainer : colors.successContainer),
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            !isAvailable
                                ? Icons.cancel_outlined
                                : (isLowStock ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                            size: 11,
                            color: !isAvailable
                                ? colorScheme.onErrorContainer
                                : (isLowStock ? colors.onWarningContainer : colors.onSuccessContainer),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              !isAvailable
                                  ? 'نفذ'
                                  : (isLowStock ? 'قليل: ${product.availableQty}' : '${product.availableQty} ${product.unit}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: !isAvailable
                                    ? colorScheme.onErrorContainer
                                    : (isLowStock ? colors.onWarningContainer : colors.onSuccessContainer),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (inCart) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Text(
                        '×$cartQuantity',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Product Name & Meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.nameAr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        height: 1.25,
                      ),
                    ),
                    if (product.nameFr.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.nameFr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (product.packSize > 1) ...[
                      const SizedBox(height: 3),
                      Text(
                        'حزمة: ${product.packSize} ${product.unit}',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Footer: Price Tag + Action Add Button
              Container(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سعر الجملة',
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.5, color: colorScheme.onSurfaceVariant),
                        ),
                        DzdPriceTag(
                          centimes: wholesalePrice,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: isAvailable ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                        foregroundColor: isAvailable ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                        minimumSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                      tooltip: isAvailable ? 'إضافة إلى السلة' : 'غير متاح',
                      onPressed: isAvailable ? onAddToCart : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
