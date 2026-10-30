import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../providers/customer_providers.dart';
import 'product_details_sheet.dart';
import 'product_image.dart';

/// Storefront product tile (compact, responsive).
///
/// Layout: an inset rounded image that flexes to fill the available height,
/// with floating status + cart controls, followed by a tight info block
/// (name, unit, price). Because the image is `Expanded`, the card never
/// overflows whatever `mainAxisExtent` / column width the grid gives it —
/// phone, tablet or desktop.
///
/// Tap adds the product to the cart; long-press opens the details sheet.
class CatalogProductCard extends ConsumerWidget {
  final ProductEntity product;

  const CatalogProductCard({super.key, required this.product});

  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

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
      hint: 'اضغط للإضافة إلى السلة، واضغط مطولاً لعرض التفاصيل',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isDark
              ? scheme.surfaceContainerLow
              : scheme.surfaceContainerLowest,
          borderRadius: AppRadius.xlAll,
          border: Border.all(
            color: inCart
                ? scheme.secondary.withValues(alpha: 0.7)
                : scheme.outlineVariant.withValues(alpha: 0.55),
            width: inCart ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (inCart ? scheme.secondary : scheme.shadow)
                  .withValues(alpha: inCart ? 0.16 : 0.06),
              blurRadius: inCart ? 14 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: AppRadius.xlAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () =>
                ref.read(customerCartProvider.notifier).addProduct(product),
            onLongPress: () => showProductDetailsSheet(context, product),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ───────── Image + floating controls ─────────
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          available
                              ? CatalogProductImage(product: product)
                              : ColorFiltered(
                                  colorFilter: _grayscale,
                                  child: CatalogProductImage(product: product),
                                ),
                          if (available)
                            // Soft bottom fade so the controls stay legible
                            // on any photo.
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: const [0.55, 1],
                                    colors: [
                                      Colors.transparent,
                                      scheme.scrim.withValues(alpha: 0.22),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            ColoredBox(
                              color: scheme.scrim.withValues(alpha: 0.42),
                              child: Center(
                                child: _Pill(
                                  label: 'نفذ من المخزون',
                                  background: context.appColors.errorContainer,
                                  foreground:
                                      context.appColors.onErrorContainer,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          if (lowStock)
                            PositionedDirectional(
                              top: 6,
                              start: 6,
                              child: _Pill(
                                label: 'آخر ${product.availableQty}',
                                background: context.appColors.warningContainer,
                                foreground:
                                    context.appColors.onWarningContainer,
                              ),
                            ),
                          if (inCart)
                            PositionedDirectional(
                              top: 6,
                              end: 6,
                              child: Semantics(
                                label: 'الكمية في السلة: $qty',
                                excludeSemantics: true,
                                child: _Pill(
                                  key: ValueKey('catalog-qty-${product.id}'),
                                  label: '$qty',
                                  background: scheme.secondaryContainer,
                                  foreground: scheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ───────── Info block ─────────
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 7, 4, 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.nameAr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 12.5,
                            height: 1.22,
                            fontWeight: FontWeight.w700,
                            color: available
                                ? scheme.onSurface
                                : scheme.onSurface.withValues(alpha: 0.48),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _metaLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            height: 1.2,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: DzdPriceTag(
                            centimes: price,
                            color: available
                                ? scheme.secondary
                                : scheme.onSurface.withValues(alpha: 0.4),
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
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

  String get _metaLabel {
    final unit = product.unitType.arabicLabel;
    if (product.packSize > 1) return '$unit · عبوة ${product.packSize}';
    return unit;
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final double fontSize;

  const _Pill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.fontSize = 9.5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}
