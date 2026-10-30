import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../providers/customer_providers.dart';
import '../../cart/cart_screen.dart';

/// The storefront's single persistent cart affordance above the app nav.
class CatalogStickyCartBar extends ConsumerWidget {
  const CatalogStickyCartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      customerCartProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );
    final totalCentimes = ref.watch(
      customerCartProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.lineTotal),
      ),
    );
    if (count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Semantics(
            button: true,
            excludeSemantics: true,
            label:
                'عرض السلة، $count قطعة، الإجمالي ${DzdFormatter.formatCentimes(totalCentimes)}',
            child: Material(
              color: scheme.secondary,
              elevation: 6,
              shadowColor: scheme.shadow.withValues(alpha: 0.28),
              borderRadius: AppRadius.lgAll,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.onSecondary.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: DzdPriceTag(
                                centimes: totalCentimes,
                                color: scheme.onSecondary,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.chevron_left_rounded,
                          size: 20,
                          color: scheme.onSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
