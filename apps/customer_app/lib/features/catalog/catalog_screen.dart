import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../providers/customer_providers.dart';
import '../cart/cart_screen.dart';
import '../orders/my_orders_screen.dart';
import '../profile/profile_form_screen.dart';
import '../common/widgets/app_update_dialog.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  final VoidCallback? onExit;
  const CatalogScreen({super.key, this.onExit});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _hasCheckedUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasCheckedUpdate) {
        _hasCheckedUpdate = true;
        _checkForUpdate();
      }
    });
  }

  Future<void> _checkForUpdate({bool manual = false}) async {
    try {
      final updateService = ref.read(customerAppUpdateServiceProvider);
      final res = await updateService.checkForUpdate();
      if (!mounted) return;

      if (res.hasUpdate) {
        await AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: updateService,
        );
      } else if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('أنت تستخدم أحدث إصدار من التطبيق.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[CatalogScreen] Update check failed: $e');
    }
  }

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
                const SizedBox(width: AppSpacing.sm),
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
                        size: 15, color: Color(0xFF1A1400)),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'متجر الجملة VIP',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.2),
                  ),
                ),
                IconButton(
                  tooltip: 'التحقق من التحديثات',
                  icon: const Icon(Icons.system_update_alt_rounded, size: 20),
                  onPressed: () => _checkForUpdate(manual: true),
                ),
                IconButton(
                  tooltip: 'الملف الشخصي',
                  icon: const Icon(Icons.person_pin_circle_outlined, size: 20),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const ProfileFormScreen(isSetup: false)),
                  ),
                ),
                IconButton(
                  tooltip: 'طلبياتي',
                  icon: const Icon(Icons.receipt_long_outlined, size: 20),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  icon: const Icon(Icons.refresh_rounded, size: 20),
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
            horizontal: 8, vertical: 6),
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
                const SizedBox(height: 6),

                // ── Search Bar ────────────────────────────────────────
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A1814)
                        : const Color(0xFFFFFDF8),
                    borderRadius: AppRadius.mdAll,
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
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن منتج...',
                      hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 5),

                // Count badge
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 10,
                      decoration: const BoxDecoration(
                        gradient: AppGradients.goldLuminous,
                        borderRadius: AppRadius.fullAll,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${filtered.length} منتج متوفر بالجملة',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontSize: 10.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 5),

                // ── 3-Column Compact Products Grid ───────────────────
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
                            // 3 cards per row on mobile screens, 4-6 on tablets/desktop
                            final int crossAxisCount = width < 550
                                ? 3
                                : width < 850
                                    ? 4
                                    : width < 1200
                                        ? 5
                                        : 6;
                            final double mainAxisExtent = width < 550 ? 178 : 190;

                            return GridView.builder(
                              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisExtent: mainAxisExtent,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _CompactProductCard(product: filtered[i]),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191612) : const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.20 : 0.16),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  'مرحباً، ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: isDark ? const Color(0xFFB8A882) : const Color(0xFF9A8A60),
                  ),
                ),
                Expanded(
                  child: Text(
                    profile.name.isNotEmpty ? profile.name : 'زبون جملة VIP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const GoldBadge(label: 'VIP', icon: Icons.diamond_outlined, small: true),
        ],
      ),
    );
  }
}

// ── Ultra-Compact Product Card (3 per row on mobile, no layout bugs) ──────────

class _CompactProductCard extends ConsumerWidget {
  final ProductEntity product;
  const _CompactProductCard({required this.product});

  void _showProductDetails(BuildContext context, int displayPrice, bool isWholesale, bool isAvailable) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductDetailsSheet(
        product: product,
        displayPrice: displayPrice,
        isWholesale: isWholesale,
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

    // Isolate pricing tier visibility: unauthenticated anonymous users see retail
    final profile = ref.watch(customerProfileProvider);
    final isWholesaleEligible = profile.isComplete && profile.isSynced;
    final effectiveTier = isWholesaleEligible ? profile.priceTier : PriceTier.retail;
    final displayPrice = product.getPriceForQuantity(effectiveTier, 1);
    final isAvailable = product.availableQty > 0;
    final canAddMore = qty < product.availableQty;
    final inCart = qty > 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171512) : const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inCart
              ? const Color(0xFFD4AF37)
              : const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.22 : 0.16),
          width: inCart ? 1.5 : 1.0,
        ),
        boxShadow: inCart
            ? const [AppShadows.goldGlowSm]
            : (isDark ? AppShadows.cardSoftDark : AppShadows.cardSoftLight),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showProductDetails(context, displayPrice, isWholesaleEligible, isAvailable),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Image Container (80px height) ─────────────────
              SizedBox(
                height: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                      child: _ProductImage(product: product, cs: cs),
                    ),
                    // Vignette gradient
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.6],
                          ),
                        ),
                      ),
                    ),
                    // Availability Dot (Top-Start: NO numeric quantity)
                    PositionedDirectional(
                      top: 5,
                      start: 5,
                      child: _AvailabilityDot(isAvailable: isAvailable),
                    ),
                    // In-Cart Badge (Top-End)
                    if (inCart)
                      PositionedDirectional(
                        top: 5,
                        end: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: const BoxDecoration(
                            gradient: AppGradients.gold,
                            borderRadius: AppRadius.pillAll,
                            boxShadow: [BoxShadow(color: Color(0x30000000), blurRadius: 2)],
                          ),
                          child: Text(
                            'x$qty',
                            style: const TextStyle(
                              color: Color(0xFF1A1400),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Details & Action Section (Remaining explicit space) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Title (Fixed 30px height for 2 lines)
                    SizedBox(
                      height: 30,
                      child: Text(
                        product.nameAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 10.5,
                          height: 1.25,
                          color: isAvailable ? null : cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),

                    // Price Row (Wholesale for verified profile, retail for unauthenticated)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isWholesaleEligible ? 'جملة' : 'تجزئة',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFB8A882) : const Color(0xFF8A7A52),
                          ),
                        ),
                        DzdPriceTag.sm(
                          centimes: displayPrice,
                          gold: true,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Compact Action Button (26px height)
                    SizedBox(
                      height: 26,
                      child: !isAvailable
                          ? Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'نفذت الكمية',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                              ),
                            )
                          : qty == 0
                              ? InkWell(
                                  onTap: () => notifier.addProduct(product),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: AppGradients.gold,
                                      borderRadius: BorderRadius.all(Radius.circular(6)),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_shopping_cart_rounded, size: 12, color: Color(0xFF1A1400)),
                                        SizedBox(width: 4),
                                        Text(
                                          'أضف',
                                          style: TextStyle(
                                            color: Color(0xFF1A1400),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF221E14) : const Color(0xFFFBF4DC),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                        icon: Icon(
                                          qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                          size: 13,
                                          color: qty == 1 ? cs.error : const Color(0xFFD4AF37),
                                        ),
                                        onPressed: () => notifier.updateQuantity(product.id, qty - 1),
                                      ),
                                      Text(
                                        '$qty',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: isDark ? const Color(0xFFF3D278) : const Color(0xFFC59B27),
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                        icon: Icon(
                                          Icons.add_rounded,
                                          size: 13,
                                          color: canAddMore
                                              ? const Color(0xFFD4AF37)
                                              : cs.onSurfaceVariant.withValues(alpha: 0.3),
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
            ],
          ),
        ),
      ),
    );
  }
}

// ── Availability Dot / Chip (Compact, No Stock Numbers) ───────────────────────

class _AvailabilityDot extends StatelessWidget {
  final bool isAvailable;
  const _AvailabilityDot({required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    if (isAvailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: const Color(0xE60D5E36), // Rich emerald
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0x662ECC71),
            width: 0.6,
          ),
          boxShadow: const [BoxShadow(color: Color(0x35000000), blurRadius: 2)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFF2ECC71),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 3),
            const Text(
              'متوفر',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: const Color(0xE62A1414), // Dark crimson
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0x66E74C3C),
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFFE74C3C),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 3),
            const Text(
              'نفذ',
              style: TextStyle(
                color: Color(0xFFFF8A80),
                fontSize: 8,
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
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
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
      child: Icon(
        Icons.inventory_2_outlined,
        size: 24,
        color: const Color(0xFFD4AF37).withValues(alpha: 0.40),
      ),
    );
  }
}

// ── Full Product Details Bottom Sheet ─────────────────────────────────────────

class _ProductDetailsSheet extends ConsumerWidget {
  final ProductEntity product;
  final int displayPrice;
  final bool isWholesale;
  final bool isAvailable;

  const _ProductDetailsSheet({
    required this.product,
    required this.displayPrice,
    required this.isWholesale,
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
                _AvailabilityDot(isAvailable: isAvailable),
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
                        Text(isWholesale ? 'سعر الجملة' : 'سعر التجزئة',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark ? const Color(0xFFF3D278) : const Color(0xFFC59B27),
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(height: 2),
                        DzdPriceTag(centimes: displayPrice, gold: true),
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
        AppStates.skeleton(height: 38, borderRadius: BorderRadius.circular(10)),
        const SizedBox(height: 6),
        AppStates.skeleton(height: 42, borderRadius: AppRadius.mdAll),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final int crossAxisCount = width < 550
                  ? 3
                  : width < 850
                      ? 4
                      : width < 1200
                          ? 5
                          : 6;
              final double mainAxisExtent = width < 550 ? 178 : 190;

              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: mainAxisExtent,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 8,
                ),
                itemCount: crossAxisCount * 3,
                itemBuilder: (_, __) =>
                    AppStates.skeleton(borderRadius: BorderRadius.circular(12)),
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
