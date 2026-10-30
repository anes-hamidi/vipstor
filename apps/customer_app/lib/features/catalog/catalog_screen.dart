import 'dart:async';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../core/catalog_ranking.dart';
import '../../models/customer_models.dart';
import '../../providers/customer_providers.dart';
import '../../services/customer_image_cache.dart';
import 'widgets/catalog_filter_sheet.dart';
import 'widgets/catalog_header.dart';
import 'widgets/catalog_offline_banner.dart';
import 'widgets/catalog_search_row.dart';
import 'widgets/catalog_skeleton.dart';
import 'widgets/category_strip.dart';
import 'widgets/product_card.dart';
import 'widgets/quick_reorder_strip.dart';
import 'widgets/sticky_cart_bar.dart';

/// Customer storefront.
///
/// The screen deliberately keeps one entry point per job: one header, one
/// search field, one filter sheet, one category row, one product grid, and one
/// cart bar. Everything else is progressive disclosure.
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

  Future<void> _openFilters() async {
    final selection = await showCatalogFilterSheet(
      context,
      sort: _sort,
      onlyAvailable: _onlyAvailable,
    );
    if (!mounted || selection == null) return;
    setState(() {
      _sort = selection.sort;
      _onlyAvailable = selection.onlyAvailable;
    });
  }

  void _warmImages(List<ProductEntity> products) {
    final pending = products
        .where(
          (product) =>
              product.photoUrl != null &&
              product.photoUrl!.isNotEmpty &&
              !_warmedPhotoIds.contains(product.id),
        )
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
          loading: () => const CatalogSkeleton(),
          error: (error, _) => ContentConstrainedBox.dashboard(
            padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: AppStates.error(
                    error.toString().replaceFirst('Exception: ', ''),
                    title: 'تعذر فتح المتجر',
                    onRetry: _refresh,
                  ),
                ),
              ),
            ),
          ),
          data: (snapshot) => _buildCatalog(snapshot, online),
        ),
      ),
      bottomNavigationBar: const CatalogStickyCartBar(),
    );
  }

  Widget _buildCatalog(CatalogSnapshot snapshot, bool online) {
    final profile = ref.watch(customerProfileProvider);
    final orders = ref.watch(customerOrdersProvider).valueOrNull;
    final theme = Theme.of(context);

    if (snapshot.products.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _warmImages(snapshot.products);
      });
    }

    final counts = categoryCounts(
      snapshot.products,
      onlyAvailable: _onlyAvailable,
    );
    final categories = counts.keys.toList(growable: false);
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

    final quickProducts = _quickReorderProducts(
      snapshot.products,
      orders?.orders ?? const [],
    );
    final showQuickReorder = _query.trim().isEmpty &&
        effectiveCategory == null &&
        quickProducts.isNotEmpty;

    final offline = !online || snapshot.isOffline;
    final showBanner = offline || snapshot.lastError != null;
    final activeFilterCount =
        (_sort != CatalogSort.recommended ? 1 : 0) + (_onlyAvailable ? 1 : 0);

    return RefreshIndicator(
      color: theme.colorScheme.secondary,
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      onRefresh: _refresh,
      child: ContentConstrainedBox.dashboard(
        maxWidth: 1200,
        child: CustomScrollView(
          key: const PageStorageKey<String>('customer-catalog-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: CatalogHeader(
                  profile: profile,
                  productCount: snapshot.products.length,
                  online: online,
                  onExit: widget.onExit,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: CatalogSearchRow(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                  onFilter: _openFilters,
                  activeFilterCount: activeFilterCount,
                ),
              ),
            ),
            if (showBanner)
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: CatalogOfflineBanner(
                    offline: offline,
                    message: snapshot.lastError,
                    syncedAt: snapshot.syncedAt,
                    onRetry: _refresh,
                  ),
                ),
              ),
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: CategoryStrip(
                  categories: categories,
                  selected: effectiveCategory,
                  onSelected: (value) => setState(() => _category = value),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: CatalogResultsBar(
                  count: ranked.length,
                  category: effectiveCategory,
                  sort: _sort,
                  onlyAvailable: _onlyAvailable,
                ),
              ),
            ),
            if (showQuickReorder)
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: QuickReorderStrip(products: quickProducts),
                ),
              ),
            if (ranked.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyCatalog(
                  query: _query.trim(),
                  onlyAvailable: _onlyAvailable,
                  onClearSearch: _clearSearch,
                  onShowAll: () => setState(() => _onlyAvailable = false),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xxxl,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 200,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => CatalogProductCard(product: ranked[index]),
                    childCount: ranked.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Products from the customer's most recent orders that are still available.
  List<ProductEntity> _quickReorderProducts(
    List<ProductEntity> catalog,
    List<OrderEntity> orders,
  ) {
    if (orders.isEmpty) return const [];
    final byId = {for (final product in catalog) product.id: product};
    final result = <ProductEntity>[];
    final seen = <String>{};
    for (final order in orders) {
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

class _EmptyCatalog extends StatelessWidget {
  final String query;
  final bool onlyAvailable;
  final VoidCallback onClearSearch;
  final VoidCallback onShowAll;

  const _EmptyCatalog({
    required this.query,
    required this.onlyAvailable,
    required this.onClearSearch,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.isNotEmpty;
    return AppStates.empty(
      icon: Icons.search_off_rounded,
      title: hasQuery ? 'لا نتائج لـ "$query"' : 'لا توجد منتجات مطابقة',
      description: hasQuery
          ? 'جرّب كلمة أخرى أو امسح البحث.'
          : onlyAvailable
              ? 'لا توجد منتجات متوفرة حالياً.'
              : 'جرّب فئة أخرى أو أعد المحاولة لاحقاً.',
      actionLabel:
          hasQuery ? 'مسح البحث' : (onlyAvailable ? 'إظهار الكل' : null),
      onAction: hasQuery
          ? onClearSearch
          : onlyAvailable
              ? onShowAll
              : null,
    );
  }
}
