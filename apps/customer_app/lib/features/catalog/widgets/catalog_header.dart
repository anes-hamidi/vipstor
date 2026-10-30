import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../providers/customer_providers.dart';
import '../../cart/cart_screen.dart';

/// Slim, personalized storefront header.
///
/// Replaces the previous hero card: one brand mark, one greeting, connectivity
/// and catalogue size in a single quiet line, and one cart entry point.
class CatalogHeader extends ConsumerWidget {
  final CustomerProfileInfo profile;
  final int productCount;
  final bool online;
  final VoidCallback? onExit;

  const CatalogHeader({
    super.key,
    required this.profile,
    required this.productCount,
    required this.online,
    this.onExit,
  });

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير';
    if (hour < 18) return 'مساء الخير';
    return 'مساء النور';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = profile.name.trim();
    final title = name.isEmpty ? _greeting : '$_greeting، $name';
    final status = online ? 'متصل' : 'بدون اتصال';
    final subtitle = '$status · $productCount منتج';
    final cartCount = ref.watch(
      customerCartProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );

    return Row(
      children: [
        if (onExit != null) ...[
          IconButton(
            tooltip: 'العودة',
            onPressed: onExit,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: AppRadius.mdAll,
          ),
          child: Icon(
            Icons.developer_board_rounded,
            color: scheme.onPrimaryContainer,
            size: 22,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (profile.hasAccount) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const GoldBadge(label: 'جملة', small: true),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: online
                          ? context.appColors.success
                          : context.appColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          tooltip: 'السلة',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CartScreen()),
          ),
          icon: Badge.count(
            count: cartCount > 99 ? 99 : cartCount,
            isLabelVisible: cartCount > 0,
            backgroundColor: scheme.secondary,
            textColor: scheme.onSecondary,
            child: Icon(
              Icons.shopping_bag_outlined,
              color: scheme.onSurface,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}
