import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../providers/customer_providers.dart';
import '../../orders/my_orders_screen.dart';
import 'product_details_sheet.dart';
import 'product_image.dart';

/// Compact shortcut to the products a customer orders most recently.
///
/// It is deliberately one horizontal row: the grid below remains the primary
/// way to shop, while this removes friction for repeat purchases.
class QuickReorderStrip extends StatelessWidget {
  final List<ProductEntity> products;

  const QuickReorderStrip({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'أعد طلبك المعتاد',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
              ),
              style: TextButton.styleFrom(
                foregroundColor: scheme.secondary,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.sm,
                ),
              ),
              child: const Text('كل الطلبيات'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, index) =>
                _QuickReorderTile(product: products[index]),
          ),
        ),
      ],
    );
  }
}

class _QuickReorderTile extends ConsumerWidget {
  final ProductEntity product;

  const _QuickReorderTile({required this.product});

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

    return Semantics(
      button: true,
      label: '${product.nameAr}، أعد طلبه',
      child: Material(
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: InkWell(
          onTap: () => showProductDetailsSheet(context, product),
          child: SizedBox(
            width: 224,
            height: 64,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.mdAll,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: CatalogProductImage(product: product),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.nameAr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: DzdPriceTag.sm(
                            centimes: price,
                            color: scheme.secondary,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  IconButton.filled(
                    tooltip: qty > 0 ? 'أضف واحدة أخرى' : 'أضف للسلة',
                    onPressed: () => ref
                        .read(customerCartProvider.notifier)
                        .addProduct(product),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.secondary,
                      foregroundColor: scheme.onSecondary,
                      minimumSize: const Size(44, 44),
                      maximumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                    ),
                    icon: Badge.count(
                      count: qty,
                      isLabelVisible: qty > 0,
                      backgroundColor: scheme.surface,
                      textColor: scheme.secondary,
                      child: const Icon(Icons.add_rounded, size: 21),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
