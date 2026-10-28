import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../providers/customer_providers.dart';
import '../../services/customer_image_cache.dart';
import '../profile/profile_form_screen.dart';

/// Full cart / checkout experience.
///
/// Works offline for established accounts: the order is queued locally and the
/// sync coordinator replays it as soon as connectivity returns.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  void _editProfile(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
      );

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    if (ref.read(customerCheckoutInProgressProvider)) return;
    final profile = ref.read(customerProfileProvider);
    if (!profile.isComplete) {
      _editProfile(context);
      return;
    }

    final unavailableNow = ref
        .read(customerCartProvider)
        .where((item) => !item.isAvailable)
        .toList();
    if (unavailableNow.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'احذف ${unavailableNow.length} منتج غير متوفر قبل تأكيد الطلبية.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final colors = context.appColors;
    final cart = ref.read(customerCartProvider.notifier);

    try {
      final outcome = await cart.checkout(profile: profile);
      if (!context.mounted) return;

      final shortId = outcome.orderId.length > 8
          ? outcome.orderId.substring(0, 8)
          : outcome.orderId;

      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: outcome.queued ? null : colors.success,
          duration: Duration(seconds: outcome.queued ? 5 : 3),
          content: Row(
            children: [
              Icon(
                outcome.queued
                    ? Icons.cloud_upload_outlined
                    : Icons.check_circle_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  outcome.queued
                      ? 'تم حفظ الطلبية #$shortId — ستُرسل تلقائياً عند عودة الاتصال.'
                      : 'تم إرسال طلبيتك بنجاح! رقم الطلب: $shortId',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );

      if (navigator.canPop()) navigator.pop();
    } catch (e) {
      if (!context.mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(
            msg.isNotEmpty ? msg : 'تعذر إرسال الطلبية، حاول مرة أخرى.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفريغ السلة؟'),
        content: const Text('سيتم حذف كل المنتجات من سلتك الحالية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'تفريغ',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(customerCartProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(customerCartProvider);
    final profile = ref.watch(customerProfileProvider);
    final online = ref.watch(customerIsOnlineProvider);
    final isSubmitting = ref.watch(customerCheckoutInProgressProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.appColors;

    final totalCentimes =
        cart.fold<int>(0, (sum, item) => sum + item.lineTotal);
    final quantitySummary = _quantitySummary(cart);
    final unavailable = cart.where((item) => !item.isAvailable).toList();
    final overStock = cart.where((item) => item.exceedsStock).toList();
    final needsProfile = !profile.isComplete;
    final needsOnlineSetup = needsProfile && !online;
    final hasAccount = profile.hasAccount;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: AppRadius.smAll,
                boxShadow: [BoxShadow(color: Color(0x3D1DAB61), blurRadius: 8, offset: Offset(0,3))],
              ),
              child: Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.shopping_bag_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                cart.isEmpty ? 'سلة الطلب' : 'سلة الطلب (${cart.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (cart.isNotEmpty)
            IconButton(
              tooltip: 'تفريغ السلة',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF131B16)
                      : const Color(0xFFEEF5F0),
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFF1DAB61)
                          .withValues(alpha: isDark ? 0.24 : 0.16),
                    ),
                  ),
                  boxShadow: isDark
                      ? const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 14,
                            offset: Offset(0, -4),
                          )
                        ]
                      : const [
                          BoxShadow(
                            color: Color(0x0C000000),
                            blurRadius: 10,
                            offset: Offset(0, -2),
                          )
                        ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('المجموع الكلي',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                              if (quantitySummary.isNotEmpty)
                                Text(
                                  quantitySummary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 9.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        DzdPriceTag.lg(
                          centimes: totalCentimes,
                          gold: true,
                        ),
                      ],
                    ),
                    if (unavailable.isNotEmpty || overStock.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _WarningLine(
                        icon: Icons.inventory_2_outlined,
                        text: unavailable.isNotEmpty
                            ? '${unavailable.length} منتج غير متوفر — احذفه لإتمام الطلبية.'
                            : '${overStock.length} منتج تتجاوز كميته المخزون المتاح.',
                        color: colors.warning,
                      ),
                    ],
                    if (!online) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _WarningLine(
                        icon: Icons.wifi_off_rounded,
                        text: needsOnlineSetup
                            ? 'أول طلبية تحتاج اتصالاً واحداً لتأكيد حسابك.'
                            : hasAccount
                                ? 'وضع عدم الاتصال — ستُحفظ الطلبية وتُرسل تلقائياً لاحقاً.'
                                : 'وضع عدم الاتصال — تحقق من الاتصال قبل إتمام الطلب.',
                        color: needsOnlineSetup
                            ? colors.warning
                            : (hasAccount
                                ? const Color(0xFF34D399)
                                : colors.warning),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    GoldButton.icon(
                      icon: isSubmitting
                          ? Icons.hourglass_top_rounded
                          : needsProfile
                              ? Icons.person_pin_circle_outlined
                              : online
                                  ? Icons.check_circle_rounded
                                  : Icons.cloud_upload_outlined,
                      label: isSubmitting
                          ? 'جاري الإرسال...'
                          : needsProfile
                              ? 'أكمل بيانات التوصيل'
                              : online
                                  ? 'تأكيد وإرسال الطلبية'
                                  : 'حفظ الطلبية وإرسالها لاحقاً',
                      onPressed:
                          isSubmitting ? null : () => _submit(context, ref),
                      loading: isSubmitting,
                      width: double.infinity,
                      height: 46,
                    ),
                  ],
                ),
              ),
            ),
      body: ContentConstrainedBox.dashboard(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: cart.isEmpty
            ? AppStates.empty(
                icon: Icons.shopping_cart_outlined,
                title: 'سلتك فارغة',
                description: 'اختر منتجات من المتجر لتبدأ طلبيتك.',
                actionLabel: 'تصفح المنتجات',
                onAction: () => Navigator.pop(context),
              )
            : RefreshIndicator(
                color: const Color(0xFF1DAB61),
                backgroundColor:
                    isDark ? const Color(0xFF131B16) : const Color(0xFFEEF5F0),
                onRefresh: () => ref
                    .read(customerCatalogProvider.notifier)
                    .refresh(silent: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _DeliveryCard(
                      profile: profile,
                      needsProfile: needsProfile,
                      online: online,
                      onEdit: () => _editProfile(context),
                      isDark: isDark,
                      theme: theme,
                    ),
                    if (unavailable.isNotEmpty || overStock.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _StockAlertCard(
                        unavailableCount: unavailable.length,
                        overStockCount: overStock.length,
                        onRemoveUnavailable: unavailable.isEmpty
                            ? null
                            : () {
                                final notifier =
                                    ref.read(customerCartProvider.notifier);
                                for (final item in unavailable) {
                                  notifier.removeProduct(item.product.id);
                                }
                              },
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    SectionHeader(
                      title: 'المنتجات (${cart.length})',
                      dense: true,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ...cart.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Dismissible(
                          key: ValueKey(item.product.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: AlignmentDirectional.centerEnd,
                            padding: const EdgeInsetsDirectional.only(
                                end: AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: AppRadius.lgAll,
                            ),
                            child: Icon(Icons.delete_outline,
                                color: theme.colorScheme.onErrorContainer),
                          ),
                          onDismissed: (_) => ref
                              .read(customerCartProvider.notifier)
                              .removeProduct(item.product.id),
                          child: _CartLine(
                            item: item,
                            isDark: isDark,
                            theme: theme,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
      ),
    );
  }
}

/// `2 كرتون · 3 كغ · 1 لتر` — totals quantities by their real sale unit
/// instead of incorrectly calling every line a "piece".
String _quantitySummary(List<CustomerCartItem> cart) {
  final counts = <ProductUnit, int>{};
  for (final item in cart) {
    final unit = item.product.unitType;
    counts.update(
      unit,
      (value) => value + item.quantity,
      ifAbsent: () => item.quantity,
    );
  }
  return ProductUnit.values
      .where(counts.containsKey)
      .map((unit) => '${counts[unit]} ${unit.arabicLabel}')
      .join(' · ');
}

// ── Cart line ─────────────────────────────────────────────────────────────────

class _CartLine extends ConsumerWidget {
  final CustomerCartItem item;
  final bool isDark;
  final ThemeData theme;

  const _CartLine({
    required this.item,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(customerCartProvider.notifier);
    final product = item.product;
    final unavailable = !item.isAvailable;
    final overStock = item.exceedsStock;
    final colors = context.appColors;
    final accent = unavailable
        ? theme.colorScheme.error
        : (overStock ? colors.warning : const Color(0xFF1DAB61));

    return LuxuryCard(
      selected: overStock,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo
          ClipRRect(
            borderRadius: AppRadius.smAll,
            child: SizedBox(
              width: 50,
              height: 50,
              child: _CartThumb(product: product),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.nameAr.isNotEmpty ? product.nameAr : product.nameFr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: unavailable
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                        : null,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${item.quantity} × ${DzdFormatter.formatCentimes(item.unitPrice)} دج / ${product.unitLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (unavailable || overStock) ...[
                  const SizedBox(height: 1),
                  Text(
                    unavailable
                        ? 'نفدت الكمية — احذفه للمتابعة'
                        : 'المتاح ${product.availableQty} ${product.unitLabel} فقط',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    _QtyButton(
                      icon: item.quantity <= 1
                          ? Icons.delete_outline_rounded
                          : Icons.remove_rounded,
                      color: item.quantity <= 1
                          ? theme.colorScheme.error
                          : (isDark
                              ? const Color(0xFF72DFA0)
                              : const Color(0xFF0A6B3A)),
                      onTap: () => notifier.updateQuantity(
                          product.id, item.quantity - 1),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${item.quantity}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    _QtyButton(
                      icon: Icons.add_rounded,
                      color: const Color(0xFF1DAB61),
                      onTap: product.availableQty > item.quantity
                          ? () => notifier.updateQuantity(
                              product.id, item.quantity + 1)
                          : null,
                    ),
                    const Spacer(),
                    DzdPriceTag(
                      centimes: item.lineTotal,
                      gold: true,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _QtyButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smAll,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF221E14) : const Color(0xFFDFF7EC),
            borderRadius: AppRadius.smAll,
            border: Border.all(
              color: const Color(0xFF1DAB61).withValues(alpha: 0.38),
              width: 0.8,
            ),
          ),
          child: Icon(
            icon,
            size: 14,
            color: onTap == null ? color.withValues(alpha: 0.3) : color,
          ),
        ),
      ),
    );
  }
}

class _CartThumb extends StatelessWidget {
  final ProductEntity product;

  const _CartThumb({required this.product});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = product.photoUrl;
    if (url == null || url.isEmpty) return _fallback(cs);

    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: CustomerImageCache.manager,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) =>
          AppStates.skeleton(borderRadius: BorderRadius.zero),
      errorWidget: (_, __, ___) => _fallback(cs),
    );
  }

  Widget _fallback(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: 22,
          color: const Color(0xFF1DAB61).withValues(alpha: 0.42),
        ),
      ),
    );
  }
}

// ── Delivery card ─────────────────────────────────────────────────────────────

class _DeliveryCard extends StatelessWidget {
  final CustomerProfileInfo profile;
  final bool needsProfile;
  final bool online;
  final VoidCallback onEdit;
  final bool isDark;
  final ThemeData theme;

  const _DeliveryCard({
    required this.profile,
    required this.needsProfile,
    required this.online,
    required this.onEdit,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final gold = isDark ? const Color(0xFF72DFA0) : const Color(0xFFC59B27);
    final colors = context.appColors;

    return LuxuryCard(
      goldAccent: !needsProfile,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: needsProfile ? null : const LinearGradient(colors: [Color(0xFF1DAB61), Color(0xFF034F40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              color: needsProfile ? cs.tertiaryContainer : null,
              borderRadius: AppRadius.smAll,
              boxShadow: needsProfile ? null : const [BoxShadow(color: Color(0x3D1DAB61), blurRadius: 8, offset: Offset(0,3))],
            ),
            child: Icon(
              needsProfile
                  ? Icons.info_outline_rounded
                  : Icons.local_shipping_outlined,
              size: 16,
              color: needsProfile
                  ? cs.onTertiaryContainer
                  : Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        needsProfile ? 'أكمل بيانات التوصيل' : profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: needsProfile ? gold : null,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!needsProfile && profile.isSynced) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.verified_rounded,
                          size: 12, color: colors.success),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  needsProfile
                      ? (online
                          ? 'نحتاج اسم المحل، الهاتف والعنوان مرة واحدة فقط.'
                          : 'لا يمكن إنشاء الحساب دون اتصال. تحقق من الشبكة.')
                      : [
                          if (profile.phone.isNotEmpty) profile.phone,
                          profile.wilaya,
                          profile.commune,
                          profile.addressText,
                        ].where((part) => part.trim().isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(needsProfile ? 'أكمل' : 'تعديل',
                style: const TextStyle(fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}

// ── Alerts / summary ──────────────────────────────────────────────────────────

class _StockAlertCard extends StatelessWidget {
  final int unavailableCount;
  final int overStockCount;
  final VoidCallback? onRemoveUnavailable;

  const _StockAlertCard({
    required this.unavailableCount,
    required this.overStockCount,
    this.onRemoveUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unavailableCount > 0
                      ? 'منتجات نفدت من المخزون'
                      : 'كمية تتجاوز المخزون المتاح',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colors.onWarningContainer,
                  ),
                ),
                Text(
                  unavailableCount > 0
                      ? 'احذف المنتجات غير المتوفرة قبل تأكيد الطلبية.'
                      : 'سيتم تعديل الكمية تلقائياً إلى الحد المتاح.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: colors.onWarningContainer,
                  ),
                ),
              ],
            ),
          ),
          if (onRemoveUnavailable != null)
            TextButton(
              onPressed: onRemoveUnavailable,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'حذف غير المتوفر',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _WarningLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
