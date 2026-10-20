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
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: productsAsync.when(
          loading: () => const _CatalogSkeleton(),
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
                const SizedBox(height: AppSpacing.sm),

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
                      hintText: 'ابحث عن منتج في الكتالوج...',
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
                          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
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
                      '${filtered.length} منتج متوفر بالجملة',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                // ── Modern Responsive Products Grid ─────────────────────
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
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final int crossAxisCount = width < 480
                                ? 2
                                : width < 780
                                    ? 3
                                    : width < 1100
                                        ? 4
                                        : 5;
                            final double mainAxisExtent = width < 480 ? 295 : 315;

                            return GridView.builder(
                              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisExtent: mainAxisExtent,
                                crossAxisSpacing: width < 480 ? 10 : AppSpacing.md,
                                mainAxisSpacing: width < 480 ? 12 : AppSpacing.md,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _ProductCard(product: filtered[i]),
                            );
                          },
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
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191612) : const Color(0xFFFFFBF0),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.20 : 0.16),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أهلاً بك في متجر الجملة',
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

// ── Modern Product Card ───────────────────────────────────────────────────────

class _ProductCard extends ConsumerWidget {
  final ProductEntity product;
  const _ProductCard({required this.product});

  void _showProductDetails(BuildContext context, int wholesalePrice, bool isAvailable) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductDetailsSheet(
        product: product,
        wholesalePrice: wholesalePrice,
        isAvailable: isAvailable,
      ),
    );
  }

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
    final notifier = ref.read(customerCartProvider.notifier);

    // Only default Wholesale Price tier
    final wholesale = product.getPriceForQuantity(PriceTier.wholesale, 1);
    final isAvailable = product.availableQty > 0;
    final canAddMore = qty < product.availableQty;
    final inCart = qty > 0;

    return LuxuryCard(
      selected: inCart,
      padding: EdgeInsets.zero,
      onTap: () => _showProductDetails(context, wholesale, isAvailable),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Product Visual Section (Top ~44% of card) ─────────────────
          Expanded(
            flex: 12,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: _ProductImage(product: product, cs: cs),
                ),
                // Gradient vignette for high readability
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.20),
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
                // Availability Badge (Top Start - NO exact stock count)
                PositionedDirectional(
                  top: 7,
                  start: 7,
                  child: _AvailabilityBadge(isAvailable: isAvailable),
                ),
                // In-Cart Badge (Top End)
                if (inCart)
                  PositionedDirectional(
                    top: 7,
                    end: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: const BoxDecoration(
                        gradient: AppGradients.gold,
                        borderRadius: AppRadius.pillAll,
                        boxShadow: [AppShadows.goldGlowSm],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_bag_rounded, size: 10, color: Color(0xFF1A1400)),
                          const SizedBox(width: 3),
                          Text(
                            '$qty',
                            style: const TextStyle(
                              color: Color(0xFF1A1400),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Details & Action Section (Bottom ~56% of card) ─────────────
          Expanded(
            flex: 15,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Title + Pack size
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.nameAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          height: 1.25,
                          color: isAvailable ? null : cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (product.nameFr.isNotEmpty)
                        Text(
                          product.nameFr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      if (product.packSize > 1) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF26221A) : const Color(0xFFF4ECE0),
                            borderRadius: AppRadius.xsAll,
                            border: Border.all(
                              color: const Color(0xFFD4AF37).withValues(alpha: 0.28),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '${product.unit} · ${product.packSize} قطع في العلبة',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFF3D278) : const Color(0xFF9A7B1C),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Price Block: DEFAULT WHOLESALE PRICE ONLY
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'سعر الجملة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFB8A882) : const Color(0xFF8A7A52),
                        ),
                      ),
                      const SizedBox(height: 1),
                      DzdPriceTag(
                        centimes: wholesale,
                        gold: true,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),

                  // Bottom Action Button / Stepper
                  SizedBox(
                    height: 34,
                    child: !isAvailable
                        ? Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                              borderRadius: AppRadius.smAll,
                            ),
                            child: Text(
                              'نفذت الكمية',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.60),
                              ),
                            ),
                          )
                        : qty == 0
                            ? GoldButton.icon(
                                icon: Icons.add_shopping_cart_rounded,
                                label: 'أضف للطلبية',
                                compact: true,
                                width: double.infinity,
                                onPressed: () => notifier.addProduct(product),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF211D10) : const Color(0xFFFBF4DC),
                                  borderRadius: AppRadius.smAll,
                                  border: Border.all(
                                    color: const Color(0xFFD4AF37).withValues(alpha: 0.50),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      icon: Icon(
                                        qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                        size: 16,
                                        color: qty == 1 ? cs.error : const Color(0xFFD4AF37),
                                      ),
                                      onPressed: () => notifier.updateQuantity(product.id, qty - 1),
                                    ),
                                    Text(
                                      '$qty',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isDark ? const Color(0xFFF3D278) : const Color(0xFFC59B27),
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      icon: Icon(
                                        Icons.add_rounded,
                                        size: 16,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Availability Status Badge (No Quantity Numbers) ───────────────────────────

class _AvailabilityBadge extends StatelessWidget {
  final bool isAvailable;
  const _AvailabilityBadge({required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    if (isAvailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xE60D5E36), // Rich emerald
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: const Color(0x662ECC71),
            width: 0.8,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x35000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Color(0xFF2ECC71),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'متوفر',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xE62A1414), // Muted dark crimson
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: const Color(0x66E74C3C),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Color(0xFFE74C3C),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'نفذت الكمية',
              style: TextStyle(
                color: Color(0xFFFF8A80),
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
  }
}

// ── Product Image ─────────────────────────────────────────────────────────────

class _ProductImage extends StatelessWidget {
  final ProductEntity product;
  final ColorScheme cs;

  const _ProductImage({required this.product, required this.cs});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = product.photoUrl != null && product.photoUrl!.isNotEmpty;

    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.40),
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: product.photoUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => AppStates.skeleton(borderRadius: BorderRadius.zero),
              errorWidget: (_, __, ___) => _FallbackPlaceholder(cs: cs),
            )
          : _FallbackPlaceholder(cs: cs),
    );
  }
}

class _FallbackPlaceholder extends StatelessWidget {
  final ColorScheme cs;
  const _FallbackPlaceholder({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 34,
            color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
          ),
          const SizedBox(height: 3),
          Text(
            'VIP STORE',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Product Details Bottom Sheet ──────────────────────────────────────────────

class _ProductDetailsSheet extends ConsumerWidget {
  final ProductEntity product;
  final int wholesalePrice;
  final bool isAvailable;

  const _ProductDetailsSheet({
    required this.product,
    required this.wholesalePrice,
    required this.isAvailable,
  });

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
    final notifier = ref.read(customerCartProvider.notifier);
    final canAddMore = qty < product.availableQty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191714) : const Color(0xFFFFFDF8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: AppShadows.dialogLuxury,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: AppRadius.fullAll,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Top row: Category + Availability Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: Text(
                    product.category.isNotEmpty ? product.category : 'عام',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _AvailabilityBadge(isAvailable: isAvailable),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Product Name
            Text(
              product.nameAr,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (product.nameFr.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                product.nameFr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),

            // Info Grid: Unit, Pack Size, Wholesale Price
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF221F1A) : const Color(0xFFF9F5EC),
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الوحدة',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(product.unit.isNotEmpty ? product.unit : 'قطعة',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  if (product.packSize > 1)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('العبوة / الشحنة',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text('${product.packSize} قطع',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('سعر الجملة',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark ? const Color(0xFFF3D278) : const Color(0xFFC59B27),
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(height: 2),
                        DzdPriceTag(centimes: wholesalePrice, gold: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Cart Actions
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
                      color: isDark ? const Color(0xFF211D10) : const Color(0xFFFBF4DC),
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.50),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                            color: qty == 1 ? cs.error : const Color(0xFFD4AF37),
                          ),
                          onPressed: () => notifier.updateQuantity(product.id, qty - 1),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '$qty',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

// ── Catalog Skeleton ──────────────────────────────────────────────────────────

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppStates.skeleton(height: 52, borderRadius: AppRadius.lgAll),
        const SizedBox(height: AppSpacing.sm),
        AppStates.skeleton(height: 44, borderRadius: AppRadius.lgAll),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final int crossAxisCount = width < 480
                  ? 2
                  : width < 780
                      ? 3
                      : width < 1100
                          ? 4
                          : 5;
              final double mainAxisExtent = width < 480 ? 295 : 315;

              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: mainAxisExtent,
                  crossAxisSpacing: width < 480 ? 10 : AppSpacing.md,
                  mainAxisSpacing: width < 480 ? 12 : AppSpacing.md,
                ),
                itemCount: crossAxisCount * 3,
                itemBuilder: (_, __) =>
                    AppStates.skeleton(borderRadius: AppRadius.lgAll),
              );
            },
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
              splashColor: const Color(0x20FFFFFF),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
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
