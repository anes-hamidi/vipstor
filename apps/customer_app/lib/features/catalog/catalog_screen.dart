import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../providers/customer_providers.dart';
import '../cart/cart_screen.dart';
import '../orders/my_orders_screen.dart';
import '../profile/profile_form_screen.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  final VoidCallback? onExit;
  const CatalogScreen({super.key, this.onExit});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(customerLiveProductsProvider);
    final profile = ref.watch(customerProfileProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isCompact = context.isCompact;

    return Scaffold(
      // Premium obsidian/ivory AppBar with gold accents
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141210) : const Color(0xFFFFFDF8),
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.22 : 0.16),
                width: 1,
              ),
            ),
            boxShadow: isDark ? AppShadows.navDark : AppShadows.navLight,
          ),
          child: SafeArea(
            child: Row(
              children: [
                if (widget.onExit != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: widget.onExit,
                  ),
                const SizedBox(width: AppSpacing.md),
                // VIP logo chip
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.gold,
                    borderRadius: AppRadius.smAll,
                    boxShadow: [AppShadows.goldGlowSm],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.storefront_rounded,
                        size: 16, color: Color(0xFF1A1400)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'متجر الجملة VIP',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, letterSpacing: 0.2),
                  ),
                ),
                IconButton(
                  tooltip: 'الملف الشخصي',
                  icon: const Icon(Icons.person_pin_circle_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const ProfileFormScreen(isSetup: false)),
                  ),
                ),
                IconButton(
                  tooltip: 'طلبياتي',
                  icon: const Icon(Icons.receipt_long_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () =>
                      ref.invalidate(customerLiveProductsProvider),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const _StickyCartBar(),
      body: ContentConstrainedBox.dashboard(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: productsAsync.when(
          loading: () => _CatalogSkeleton(isCompact: isCompact),
          error: (err, _) => AppStates.error(
            'تعذر جلب المنتجات. ${err.toString().replaceFirst('Exception: ', '')}',
            onRetry: () => ref.invalidate(customerLiveProductsProvider),
          ),
          data: (products) {
            final q = _query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? products
                : products
                    .where((p) =>
                        p.nameAr.toLowerCase().contains(q) ||
                        p.nameFr.toLowerCase().contains(q))
                    .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Greeting banner ───────────────────────────────────
                _GreetingBanner(profile: profile, isDark: isDark, theme: theme),
                const SizedBox(height: AppSpacing.md),

                // ── Search ────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A1814)
                        : const Color(0xFFFFFDF8),
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(
                      color: const Color(0xFFD4AF37)
                          .withValues(alpha: isDark ? 0.22 : 0.18),
                      width: 1,
                    ),
                    boxShadow:
                        isDark ? AppShadows.cardSoftDark : AppShadows.cardSoftLight,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن منتج بالعربية أو الفرنسية...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsetsDirectional.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 12,
                      decoration: const BoxDecoration(
                        gradient: AppGradients.goldLuminous,
                        borderRadius: AppRadius.fullAll,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${filtered.length} منتج متوفر',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Grid / List ───────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? AppStates.empty(
                          icon: Icons.search_off_rounded,
                          title: 'لا نتائج لـ "$_query"',
                          description: 'جرّب كلمة أخرى أو امسح البحث.',
                          actionLabel: 'مسح البحث',
                          onAction: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : isCompact
                          ? ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: AppSpacing.md),
                              itemBuilder: (_, i) =>
                                  _ProductCard(product: filtered[i]),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 380,
                                mainAxisExtent: 300,
                                crossAxisSpacing: AppSpacing.md,
                                mainAxisSpacing: AppSpacing.md,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) =>
                                  _ProductCard(product: filtered[i]),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Greeting Banner ───────────────────────────────────────────────────────────

class _GreetingBanner extends StatelessWidget {
  final dynamic profile;
  final bool isDark;
  final ThemeData theme;

  const _GreetingBanner(
      {required this.profile, required this.isDark, required this.theme});

  @override
  Widget build(BuildContext context) {
    return LuxuryCard(
      goldAccent: true,
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => const ProfileFormScreen(isSetup: false)),
      ),
      child: Row(
        children: [
          // Avatar ring
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              gradient: AppGradients.gold,
              shape: BoxShape.circle,
              boxShadow: [AppShadows.goldGlowSm],
            ),
            child: const Icon(Icons.storefront_rounded,
                size: 20, color: Color(0xFF1A1400)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحباً بك',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? const Color(0xFFB8A882)
                        : const Color(0xFF9A8A60),
                  ),
                ),
                Text(
                  profile.name.isNotEmpty ? profile.name : 'زبون جملة VIP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const GoldBadge(label: 'VIP', icon: Icons.diamond_outlined, small: true),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.edit_location_alt_outlined,
            size: 16,
            color: isDark ? const Color(0xFFF3D278) : const Color(0xFFC59B27),
          ),
        ],
      ),
    );
  }
}

// ── Product Card ──────────────────────────────────────────────────────────────

class _ProductCard extends ConsumerWidget {
  final ProductEntity product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = ref.watch(customerCartProvider.select((items) {
      for (final it in items) {
        if (it.product.id == product.id) return it.quantity;
      }
      return 0;
    }));

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.appColors;
    final notifier = ref.read(customerCartProvider.notifier);

    final retail = product.getPriceForQuantity(PriceTier.retail, 1);
    final wholesale = product.getPriceForQuantity(PriceTier.wholesale, 1);
    final bulk = product.getPriceForQuantity(PriceTier.bulk, 1);
    final isAvailable = product.availableQty > 0;
    final canAddMore = qty < product.availableQty;
    final inCart = qty > 0;

    return LuxuryCard(
      selected: inCart,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Header: image + name + stock ──────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product image
                _ProductImage(product: product, cs: cs),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.nameAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isAvailable
                              ? null
                              : cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                      if (product.nameFr.isNotEmpty)
                        Text(
                          product.nameFr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                StockBadge(
                  availableQty: product.availableQty,
                  unitName: product.unit,
                  compact: true,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xs),

            // Pack size
            if (product.packSize > 1)
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(
                    '${product.unit} · ${product.packSize} قطع في الشحنة',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ),

            const SizedBox(height: AppSpacing.sm),

            // ── Price block ────────────────────────────────────────────
            Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                gradient: isDark
                    ? AppGradients.darkGlass
                    : AppGradients.goldSubtleLight,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: const Color(0xFFD4AF37)
                      .withValues(alpha: isDark ? 0.18 : 0.14),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'سعر الجملة',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? const Color(0xFFF3D278)
                                    : const Color(0xFFC59B27),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            if (retail > wholesale) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colors.success,
                                  borderRadius: AppRadius.pillAll,
                                ),
                                child: Text(
                                  'وفر ${((retail - wholesale) / 100).toStringAsFixed(0)} دج',
                                  style: TextStyle(
                                    color: colors.onSuccess,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        DzdPriceTag.lg(
                          centimes: wholesale,
                          gold: true,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _SmallPrice(label: 'تجزئة', centimes: retail),
                      const SizedBox(height: 2),
                      _SmallPrice(label: 'كميات', centimes: bulk),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Add / stepper ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: qty == 0
                  ? GoldButton.icon(
                      icon: Icons.add_shopping_cart_rounded,
                      label: isAvailable ? 'أضف للطلبية' : 'نفذت الكمية',
                      onPressed: isAvailable
                          ? () => notifier.addProduct(product)
                          : null,
                      width: double.infinity,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF211D10)
                            : const Color(0xFFFBF4DC),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color: const Color(0xFFD4AF37)
                              .withValues(alpha: 0.40),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => notifier.updateQuantity(
                                product.id, qty - 1),
                            icon: Icon(
                              qty == 1
                                  ? Icons.delete_outline
                                  : Icons.remove_rounded,
                              size: 18,
                              color: qty == 1
                                  ? cs.error
                                  : const Color(0xFFD4AF37),
                            ),
                          ),
                          Column(
                            children: [
                              Text(
                                '$qty',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? const Color(0xFFF3D278)
                                      : const Color(0xFFC59B27),
                                ),
                              ),
                              Text(
                                'في السلة',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: canAddMore
                                ? () => notifier.updateQuantity(
                                    product.id, qty + 1)
                                : null,
                            icon: Icon(
                              Icons.add_rounded,
                              size: 18,
                              color: canAddMore
                                  ? const Color(0xFFD4AF37)
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Product Image ─────────────────────────────────────────────────────────────

class _ProductImage extends StatelessWidget {
  final ProductEntity product;
  final ColorScheme cs;

  const _ProductImage({required this.product, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.20), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: product.photoUrl!,
              fit: BoxFit.cover,
              memCacheWidth:
                  (56 * MediaQuery.devicePixelRatioOf(context)).round(),
              placeholder: (_, __) => AppStates.skeleton(
                  width: 56, height: 56, borderRadius: AppRadius.mdAll),
              errorWidget: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                size: 22,
                color: cs.onSurfaceVariant.withValues(alpha: 0.50),
              ),
            )
          : Icon(Icons.inventory_2_outlined,
              size: 26, color: cs.onSurfaceVariant.withValues(alpha: 0.50)),
    );
  }
}

// ── Small Price Row ───────────────────────────────────────────────────────────

class _SmallPrice extends StatelessWidget {
  final String label;
  final int centimes;
  const _SmallPrice({required this.label, required this.centimes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: TextStyle(
                fontSize: 10,
                color: cs.onSurfaceVariant.withValues(alpha: 0.80))),
        DzdPriceTag.sm(
          centimes: centimes,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        ),
      ],
    );
  }
}

// ── Catalog Skeleton ──────────────────────────────────────────────────────────

class _CatalogSkeleton extends StatelessWidget {
  final bool isCompact;
  const _CatalogSkeleton({required this.isCompact});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppStates.skeleton(height: 52, borderRadius: AppRadius.lgAll),
        const SizedBox(height: AppSpacing.md),
        AppStates.skeleton(height: 48, borderRadius: AppRadius.lgAll),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: isCompact
              ? ListView.separated(
                  itemCount: 4,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, __) => AppStates.skeleton(
                      height: 180, borderRadius: AppRadius.lgAll),
                )
              : GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 300,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                  ),
                  itemCount: 6,
                  itemBuilder: (_, __) => AppStates.skeleton(
                      height: 300, borderRadius: AppRadius.lgAll),
                ),
        ),
      ],
    );
  }
}

// ── Sticky Cart Bar ───────────────────────────────────────────────────────────

class _StickyCartBar extends ConsumerWidget {
  const _StickyCartBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(customerCartProvider.select(
        (items) => items.fold<int>(0, (s, it) => s + it.quantity)));
    final totalCentimes = ref.watch(customerCartProvider.select(
        (items) => items.fold<int>(0, (s, it) => s + it.lineTotal)));

    if (count == 0) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
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
              splashColor: const Color(0x20FFFFFF),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
                    // Cart icon with badge
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.shopping_cart_rounded,
                            color: Color(0xFF1A1400), size: 22),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1A1400),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 9,
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
                          fontSize: 14,
                          color: Color(0xFF1A1400),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    DzdPriceTag(
                      centimes: totalCentimes,
                      color: const Color(0xFF1A1400),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 13, color: Color(0xFF1A1400)),
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
