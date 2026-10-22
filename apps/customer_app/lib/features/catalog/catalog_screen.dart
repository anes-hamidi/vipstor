import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../core/catalog_ranking.dart';
import '../../models/customer_models.dart';
import '../../providers/customer_providers.dart';
import '../../services/customer_image_cache.dart';
import '../cart/cart_screen.dart';
import '../orders/my_orders_screen.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  final VoidCallback? onExit;

  const CatalogScreen({super.key, this.onExit});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _category;
  CatalogSort _sort = CatalogSort.recommended;
  bool _onlyAvailable = false;
  Set<String> _warmedPhotoIds = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  void _warmImages(List<ProductEntity> products) {
    final pending = products
        .where((p) =>
            p.photoUrl != null &&
            p.photoUrl!.isNotEmpty &&
            !_warmedPhotoIds.contains(p.id))
        .take(24)
        .toList();
    if (pending.isEmpty) return;
    _warmedPhotoIds = {..._warmedPhotoIds, ...pending.map((p) => p.id)};
    unawaited(CustomerImageCache.warmUp(pending.map((p) => p.photoUrl)));
  }

  Future<void> _refresh() =>
      ref.read(customerCatalogProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(customerCatalogProvider);
    final online = ref.watch(customerIsOnlineProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: catalogAsync.when(
          loading: () => const _CatalogSkeleton(),
          error: (error, _) => ContentConstrainedBox.dashboard(
            padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
            child: AppStates.error(
              error.toString().replaceFirst('Exception: ', ''),
              title: 'تعذر فتح المتجر',
              onRetry: _refresh,
            ),
          ),
          data: (snapshot) => _buildCatalog(snapshot, online),
        ),
      ),
      bottomNavigationBar: const _StickyCartBar(),
    );
  }

  Widget _buildCatalog(CatalogSnapshot snapshot, bool online) {
    final profile = ref.watch(customerProfileProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (snapshot.products.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _warmImages(snapshot.products);
      });
    }

    final counts = categoryCounts(
      snapshot.products,
      onlyAvailable: _onlyAvailable,
    );
    final effectiveCategory =
        _category != null && counts.containsKey(_category) ? _category : null;
    final tier = profile.hasAccount ? profile.priceTier : PriceTier.retail;

    final ranked = rankCatalog(
      snapshot.products,
      query: _query,
      category: effectiveCategory,
      sort: _sort,
      onlyAvailable: _onlyAvailable,
      tier: tier,
      affinity: snapshot.affinity,
    );

    final quickProducts = _quickReorderProducts(snapshot.products);
    final showQuickReorder = _query.trim().isEmpty &&
        effectiveCategory == null &&
        quickProducts.isNotEmpty;

    final offline = !online || snapshot.isOffline;
    final staleMessage = snapshot.lastError;

    return RefreshIndicator(
      color: const Color(0xFFD4AF37),
      backgroundColor: isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _HeroHeader(
                profile: profile,
                productCount: snapshot.products.length,
                online: online,
                onExit: widget.onExit,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _SearchField(
                controller: _searchCtrl,
                query: _query,
                onChanged: _onSearchChanged,
                onClear: _clearSearch,
              ),
            ),
          ),
          if (offline || staleMessage != null)
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _OfflineBanner(
                  offline: offline,
                  message: staleMessage,
                  syncedAt: snapshot.syncedAt,
                  onRetry: _refresh,
                ),
              ),
            ),
          if (counts.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xxs,
                  ),
                  children: [
                    _CategoryChip(
                      label: 'الكل',
                      count: snapshot.products
                          .where((p) =>
                              p.active && (!_onlyAvailable || p.availableQty > 0))
                          .length,
                      selected: effectiveCategory == null,
                      onTap: () => setState(() => _category = null),
                    ),
                    ...counts.entries.map(
                      (entry) => _CategoryChip(
                        label: entry.key,
                        count: entry.value,
                        selected: effectiveCategory == entry.key,
                        onTap: () => setState(() {
                          _category =
                              effectiveCategory == entry.key ? null : entry.key;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            sliver: SliverToBoxAdapter(
              child: _FilterBar(
                resultCount: ranked.length,
                sort: _sort,
                onlyAvailable: _onlyAvailable,
                onSortChanged: (sort) => setState(() => _sort = sort),
                onAvailabilityChanged: (value) =>
                    setState(() => _onlyAvailable = value),
              ),
            ),
          ),
          if (showQuickReorder)
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              sliver: SliverToBoxAdapter(
                child: _QuickReorderStrip(products: quickProducts),
              ),
            ),
          if (ranked.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppStates.empty(
                icon: Icons.search_off_rounded,
                title: _query.isNotEmpty
                    ? 'لا نتائج لـ "$_query"'
                    : 'لا توجد منتجات متاحة',
                description: _query.isNotEmpty
                    ? 'جرّب كلمة أخرى أو امسح البحث.'
                    : 'ستظهر المنتجات هنا فور توفرها.',
                actionLabel: _query.isNotEmpty ? 'مسح البحث' : null,
                onAction: _query.isNotEmpty ? _clearSearch : null,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = width < 520
                      ? 2
                      : width < 820
                          ? 3
                          : width < 1120
                              ? 4
                              : 5;
                  final extent = width < 520 ? 256.0 : 268.0;
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: extent,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisSpacing: AppSpacing.sm,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _ProductCard(product: ranked[i]),
                      childCount: ranked.length,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Products from the customer's most recent order that are still available.
  List<ProductEntity> _quickReorderProducts(List<ProductEntity> catalog) {
    final orders = ref.watch(customerOrdersProvider).valueOrNull;
    if (orders == null || orders.orders.isEmpty) return const [];
    final byId = {for (final p in catalog) p.id: p};
    final result = <ProductEntity>[];
    final seen = <String>{};
    for (final order in orders.orders) {
      for (final item in order.items) {
        if (seen.contains(item.productId)) continue;
        final product = byId[item.productId];
        if (product == null || product.availableQty <= 0) continue;
        seen.add(item.productId);
        result.add(product);
        if (result.length >= 6) return result;
      }
    }
    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header / filters
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends ConsumerWidget {
  final CustomerProfileInfo profile;
  final int productCount;
  final bool online;
  final VoidCallback? onExit;

  const _HeroHeader({
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
    final cartCount = ref.watch(
      customerCartProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: AppGradients.obsidianHero,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: const Color(0x40D4AF37)),
        boxShadow: AppShadows.cardElevatedDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onExit != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: IconButton(
                    tooltip: 'العودة',
                    onPressed: onExit,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Color(0xFFFBF8F0), size: 20),
                  ),
                ),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: AppGradients.gold,
                  borderRadius: AppRadius.mdAll,
                  boxShadow: [AppShadows.goldGlowSm],
                ),
                child: const Icon(Icons.diamond_rounded,
                    color: Color(0xFF1A1400), size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_greeting${profile.name.isNotEmpty ? '، ${profile.name}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFBF8F0),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: online
                                ? const Color(0xFF34D399)
                                : const Color(0xFFFBBF24),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          online ? 'متصل · $productCount منتج' : 'وضع محلي · $productCount منتج',
                          style: const TextStyle(
                            color: Color(0xFFB8A882),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'السلة',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_bag_outlined,
                        color: Color(0xFFF3D278), size: 24),
                    if (cartCount > 0)
                      PositionedDirectional(
                        top: -6,
                        end: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: const BoxDecoration(
                            gradient: AppGradients.gold,
                            borderRadius: AppRadius.pillAll,
                          ),
                          child: Text(
                            cartCount > 99 ? '99+' : '$cartCount',
                            style: const TextStyle(
                              color: Color(0xFF1A1400),
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const GoldDivider(height: 0.7),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const GoldBadge(
                label: 'VIP WHOLESALE',
                icon: Icons.storefront_rounded,
                small: true,
              ),
              const Spacer(),
              Text(
                profile.hasAccount ? 'أسعار الجملة مفعّلة' : 'أسعار التجزئة',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: profile.hasAccount
                      ? const Color(0xFFF3D278)
                      : const Color(0xFFB8A882),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFFD4AF37)
              .withValues(alpha: isDark ? 0.24 : 0.18),
        ),
        boxShadow: isDark ? AppShadows.cardSoftDark : AppShadows.cardSoftLight,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'ابحث عن منتج، فئة أو باركود...',
          hintStyle: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  tooltip: 'مسح',
                  icon: const Icon(Icons.close_rounded, size: 17),
                  onPressed: onClear,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pillAll,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md, vertical: 6),
            decoration: BoxDecoration(
              gradient: selected ? AppGradients.gold : null,
              color: selected
                  ? null
                  : (isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8)),
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : const Color(0xFFD4AF37)
                        .withValues(alpha: isDark ? 0.22 : 0.16),
              ),
              boxShadow: selected ? const [AppShadows.goldGlowSm] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    color: selected
                        ? const Color(0xFF1A1400)
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0x33000000)
                        : const Color(0xFFD4AF37).withValues(alpha: 0.14),
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: selected
                          ? const Color(0xFF1A1400)
                          : (isDark
                              ? const Color(0xFFF3D278)
                              : const Color(0xFF9A7319)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final int resultCount;
  final CatalogSort sort;
  final bool onlyAvailable;
  final ValueChanged<CatalogSort> onSortChanged;
  final ValueChanged<bool> onAvailabilityChanged;

  const _FilterBar({
    required this.resultCount,
    required this.sort,
    required this.onlyAvailable,
    required this.onSortChanged,
    required this.onAvailabilityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        Text(
          '$resultCount منتج',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: () => onAvailabilityChanged(!onlyAvailable),
          borderRadius: AppRadius.pillAll,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: onlyAvailable
                  ? const Color(0xFFD4AF37).withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: const Color(0xFFD4AF37)
                    .withValues(alpha: onlyAvailable ? 0.55 : 0.22),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 12,
                  color: onlyAvailable
                      ? (isDark
                          ? const Color(0xFFF3D278)
                          : const Color(0xFF9A7319))
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Text(
                  'المتوفر فقط',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: onlyAvailable
                        ? (isDark
                            ? const Color(0xFFF3D278)
                            : const Color(0xFF9A7319))
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        PopupMenuButton<CatalogSort>(
          tooltip: 'ترتيب',
          initialValue: sort,
          onSelected: onSortChanged,
          color: isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.mdAll,
            side: BorderSide(color: Color(0x40D4AF37)),
          ),
          itemBuilder: (_) => CatalogSort.values
              .map(
                (value) => PopupMenuItem(
                  value: value,
                  child: Row(
                    children: [
                      Icon(
                        value == sort
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 16,
                        color: value == sort
                            ? const Color(0xFFD4AF37)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(value.label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              )
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.sort_rounded,
                    size: 13, color: Color(0xFFD4AF37)),
                const SizedBox(width: 3),
                Text(
                  sort.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFF3D278)
                        : const Color(0xFF9A7319),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final bool offline;
  final String? message;
  final DateTime? syncedAt;
  final VoidCallback onRetry;

  const _OfflineBanner({
    required this.offline,
    required this.message,
    required this.syncedAt,
    required this.onRetry,
  });

  String get _subtitle {
    if (syncedAt != null) {
      final local = syncedAt!.toLocal();
      final d = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
      final t =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      return 'آخر نسخة محفوظة $d · $t';
    }
    return 'تُعرض البيانات المحفوظة على جهازك';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2212) : const Color(0xFFFFF7DE),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
            size: 17,
            color: isDark ? const Color(0xFFF3D278) : const Color(0xFF9A7319),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offline
                      ? 'وضع عدم الاتصال — المتجر يعمل من الذاكرة'
                      : 'تعذر تحديث القائمة الآن',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold),
                ),
                Text(
                  _subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إعادة المحاولة',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick reorder
// ─────────────────────────────────────────────────────────────────────────────

class _QuickReorderStrip extends ConsumerWidget {
  final List<ProductEntity> products;

  const _QuickReorderStrip({required this.products});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'أعد طلبك المعتاد',
          dense: true,
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
            ),
            child: const Text('طلبياتي', style: TextStyle(fontSize: 11)),
          ),
        ),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) {
              final product = products[i];
              return Container(
                width: 220,
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.sm, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? const Color(0xFF1A1814)
                      : const Color(0xFFFFFDF8),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.smAll,
                      child: SizedBox(
                        width: 46,
                        height: 58,
                        child: _ProductImage(product: product),
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
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${product.category} · متوفر',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          DzdPriceTag.sm(
                            centimes: product.getPriceForQuantity(
                              PriceTier.retail,
                              1,
                            ),
                            gold: true,
                            style: const TextStyle(fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'أضف للسلة',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ref.read(customerCartProvider.notifier).addProduct(product);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('أُضيف ${product.nameAr} إلى السلة'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_circle_rounded,
                          color: Color(0xFFD4AF37), size: 22),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product card + details
// ─────────────────────────────────────────────────────────────────────────────

class _ProductCard extends ConsumerWidget {
  final ProductEntity product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
    final inCart = qty > 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171512) : const Color(0xFFFFFDF8),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: inCart
              ? const Color(0xFFD4AF37)
              : const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.22 : 0.15),
          width: inCart ? 1.4 : 1,
        ),
        boxShadow: inCart
            ? const [AppShadows.goldGlowSm]
            : (isDark ? AppShadows.cardSoftDark : AppShadows.cardSoftLight),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.lgAll,
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: () => _showDetails(context, price, tier, available),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(14)),
                      child: _ProductImage(product: product),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.22),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.10),
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 6,
                      start: 6,
                      child: _StockChip(available: available),
                    ),
                    if (inCart)
                      PositionedDirectional(
                        top: 6,
                        end: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: const BoxDecoration(
                            gradient: AppGradients.gold,
                            borderRadius: AppRadius.pillAll,
                          ),
                          child: Text(
                            '$qty في السلة',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1400),
                            ),
                          ),
                        ),
                      ),
                    if (!available)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(14)),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.28),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.sm, 6, AppSpacing.sm, AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: isDark
                            ? const Color(0xFFB8A882)
                            : const Color(0xFF9A8A60),
                      ),
                    ),
                    const SizedBox(height: 1),
                    SizedBox(
                      height: 31,
                      child: Text(
                        product.nameAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.bold,
                          color: available
                              ? null
                              : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: DzdPriceTag.sm(
                            centimes: price,
                            gold: true,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        if (product.packSize > 1)
                          Text(
                            '×${product.packSize}',
                            style: TextStyle(
                              fontSize: 8,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 28,
                      child: _CardAction(
                        product: product,
                        qty: qty,
                        available: available,
                      ),
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

  void _showDetails(
    BuildContext context,
    int price,
    PriceTier tier,
    bool available,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductDetailsSheet(
        product: product,
        displayPrice: price,
        tier: tier,
        isAvailable: available,
      ),
    );
  }
}

class _CardAction extends ConsumerWidget {
  final ProductEntity product;
  final int qty;
  final bool available;

  const _CardAction({
    required this.product,
    required this.qty,
    required this.available,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(customerCartProvider.notifier);
    final isDark = theme.brightness == Brightness.dark;

    if (!available) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: AppRadius.smAll,
        ),
        child: Text(
          'نفذت الكمية',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    if (qty == 0) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.smAll,
          onTap: () => notifier.addProduct(product),
          child: Container(
            decoration: const BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: AppRadius.smAll,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_shopping_cart_rounded,
                    size: 12, color: Color(0xFF1A1400)),
                SizedBox(width: 4),
                Text(
                  'أضف للسلة',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1400),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF221E14) : const Color(0xFFFBF4DC),
        borderRadius: AppRadius.smAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StepButton(
            icon: qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            color: qty == 1 ? theme.colorScheme.error : const Color(0xFFD4AF37),
            onTap: () => notifier.updateQuantity(product.id, qty - 1),
          ),
          Text(
            '$qty',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
              color: isDark
                  ? const Color(0xFFF3D278)
                  : const Color(0xFFC59B27),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            color: const Color(0xFFD4AF37),
            onTap: qty < product.availableQty
                ? () => notifier.updateQuantity(product.id, qty + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StepButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smAll,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(
          icon,
          size: 14,
          color: onTap == null ? color.withValues(alpha: 0.3) : color,
        ),
      ),
    );
  }
}

class _StockChip extends StatelessWidget {
  final bool available;

  const _StockChip({required this.available});

  @override
  Widget build(BuildContext context) {
    final color = available
        ? const Color(0xFF0D5E36)
        : const Color(0xB32A1414);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.pillAll,
        border: Border.all(
          color: available
              ? const Color(0x662ECC71)
              : const Color(0x66E74C3C),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: available
                  ? const Color(0xFF2ECC71)
                  : const Color(0xFFE74C3C),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            available ? 'متوفر' : 'نفذ',
            style: TextStyle(
              color: available ? Colors.white : const Color(0xFFFF8A80),
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final ProductEntity product;

  const _ProductImage({required this.product});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = product.photoUrl;
    if (url == null || url.isEmpty) return _fallback(cs);

    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: CustomerImageCache.manager,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 220),
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
          size: 26,
          color: const Color(0xFFD4AF37).withValues(alpha: 0.42),
        ),
      ),
    );
  }
}

class _ProductDetailsSheet extends ConsumerWidget {
  final ProductEntity product;
  final int displayPrice;
  final PriceTier tier;
  final bool isAvailable;

  const _ProductDetailsSheet({
    required this.product,
    required this.displayPrice,
    required this.tier,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = ref.watch(
      customerCartProvider.select((items) {
        for (final item in items) {
          if (item.product.id == product.id) return item.quantity;
        }
        return 0;
      }),
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final notifier = ref.read(customerCartProvider.notifier);
    final canAddMore = qty < product.availableQty;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191714) : const Color(0xFFFFFDF8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
        ),
        boxShadow: AppShadows.dialogLuxury,
      ),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: AppRadius.fullAll,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: AppRadius.lgAll,
              child: SizedBox(
                height: 170,
                child: _ProductImage(product: product),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.nameAr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                _StockChip(available: isAvailable),
              ],
            ),
            if (product.nameFr.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                product.nameFr,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF221F1A) : const Color(0xFFF9F5EC),
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  _InfoCell(
                    label: 'الفئة',
                    value: product.category.isNotEmpty ? product.category : 'عام',
                  ),
                  _InfoCell(
                    label: 'الوحدة',
                    value: product.unit.isNotEmpty ? product.unit : 'قطعة',
                  ),
                  if (product.packSize > 1)
                    _InfoCell(
                      label: 'العبوة',
                      value: '${product.packSize} قطع',
                    ),
                  _InfoCell(
                    label: tier == PriceTier.retail ? 'سعر التجزئة' : 'سعر الجملة',
                    value: DzdFormatter.formatCentimes(displayPrice),
                    highlight: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isAvailable
                  ? 'متوفر الآن في المستودع — أضفه إلى سلتك وسيصلك مع طلبيتك القادمة.'
                  : 'هذا المنتج غير متوفر حالياً. يمكنك طلب منتجات أخرى.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!isAvailable)
              Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: AppRadius.mdAll,
                ),
                child: const Text(
                  'عذراً، هذا المنتج غير متوفر حالياً',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              )
            else if (qty == 0)
              GoldButton.icon(
                icon: Icons.add_shopping_cart_rounded,
                label: 'أضف للطلبية',
                onPressed: () {
                  notifier.addProduct(product);
                  Navigator.of(context).pop();
                },
              )
            else
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF211D10)
                          : const Color(0xFFFBF4DC),
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            qty == 1
                                ? Icons.delete_outline_rounded
                                : Icons.remove_rounded,
                            color: qty == 1
                                ? cs.error
                                : const Color(0xFFD4AF37),
                          ),
                          onPressed: () =>
                              notifier.updateQuantity(product.id, qty - 1),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            '$qty',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.add_rounded,
                            color: canAddMore
                                ? const Color(0xFFD4AF37)
                                : cs.onSurfaceVariant.withValues(alpha: 0.35),
                          ),
                          onPressed: canAddMore
                              ? () => notifier.updateQuantity(product.id, qty + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: GoldButton(
                      label: 'تم (إغلاق)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _InfoCell({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9.5,
              color: highlight
                  ? (theme.brightness == Brightness.dark
                      ? const Color(0xFFF3D278)
                      : const Color(0xFFC59B27))
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton + sticky cart
// ─────────────────────────────────────────────────────────────────────────────

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    return ContentConstrainedBox.dashboard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Column(
        children: [
          AppStates.skeleton(height: 140, borderRadius: AppRadius.xlAll),
          const SizedBox(height: AppSpacing.sm),
          AppStates.skeleton(height: 46, borderRadius: AppRadius.mdAll),
          const SizedBox(height: AppSpacing.sm),
          AppStates.skeleton(height: 44, borderRadius: AppRadius.mdAll),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width < 520 ? 2 : width < 820 ? 3 : 4;
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 256,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                  ),
                  itemCount: columns * 3,
                  itemBuilder: (_, __) =>
                      AppStates.skeleton(borderRadius: AppRadius.lgAll),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyCartBar extends ConsumerWidget {
  const _StickyCartBar();

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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: AppGradients.gold,
            borderRadius: AppRadius.lgAll,
            boxShadow: [AppShadows.goldGlow, AppShadows.goldGlowSm],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.lgAll,
            child: InkWell(
              borderRadius: AppRadius.lgAll,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.shopping_cart_rounded,
                            color: Color(0xFF1A1400), size: 20),
                        Positioned(
                          top: -7,
                          right: -8,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1A1400),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text(
                        'عرض السلة وإتمام الطلب',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: Color(0xFF1A1400),
                        ),
                      ),
                    ),
                    DzdPriceTag(
                      centimes: totalCentimes,
                      color: const Color(0xFF1A1400),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: Color(0xFF1A1400)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
