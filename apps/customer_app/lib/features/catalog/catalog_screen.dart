import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  int _qtyOf(List<CustomerCartItem> cart, String id) {
    for (final it in cart) {
      if (it.product.id == id) return it.quantity;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(customerLiveProductsProvider);
    final cart = ref.watch(customerCartProvider);
    final profile = ref.watch(customerProfileProvider);
    final theme = Theme.of(context);
    final isCompact = context.isCompact;
    final cartTotal = cart.fold<int>(0, (s, it) => s + it.lineTotal);
    final cartCount = cart.fold<int>(0, (s, it) => s + it.quantity);

    return Scaffold(
      appBar: AppBar(
        leading: widget.onExit != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'العودة إلى البوابة',
                onPressed: widget.onExit,
              )
            : null,
        title: const Text('متجر الجملة'),
        actions: [
          IconButton(
            tooltip: 'بيانات المحل / التوصيل',
            icon: const Icon(Icons.person_pin_circle_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileFormScreen(isSetup: false)),
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
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(customerLiveProductsProvider),
          ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CartBar(
              count: cartCount,
              totalCentimes: cartTotal,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ),
            ),
      body: ContentConstrainedBox.dashboard(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: productsAsync.when(
          loading: () => const AppLoadingView(message: 'جاري جلب المنتجات...'),
          error: (err, _) => AppErrorView(
            message: 'تعذر جلب المنتجات. تحقق من الاتصال وحاول مجدداً.',
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
                // Greeting Banner with clickable edit profile shortcut
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.mdAll,
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
                  ),
                  child: InkWell(
                    borderRadius: AppRadius.mdAll,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileFormScreen(isSetup: false)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Icon(Icons.storefront_rounded,
                                size: 20, color: theme.colorScheme.onPrimaryContainer),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('مرحباً بك',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant)),
                                Text(profile.name.isNotEmpty ? profile.name : 'زبون جملة',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Icon(Icons.edit_location_alt_outlined,
                              size: 18, color: theme.colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
                AppSpacing.gapMd,

                // Search
                SearchBar(
                  controller: _searchCtrl,
                  hintText: 'ابحث عن منتج بالعربية أو الفرنسية',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(
                      theme.colorScheme.surfaceContainerHighest),
                  trailing: [
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                  ],
                  onChanged: (v) => setState(() => _query = v),
                ),
                AppSpacing.gapSm,
                Text('${filtered.length} منتج متوفر',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                AppSpacing.gapSm,

                Expanded(
                  child: filtered.isEmpty
                      ? AppEmptyView(
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
                              separatorBuilder: (_, __) => AppSpacing.gapMd,
                              itemBuilder: (_, i) => _ProductCard(
                                product: filtered[i],
                                qty: _qtyOf(cart, filtered[i].id),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 380,
                                mainAxisExtent: 270,
                                crossAxisSpacing: AppSpacing.md,
                                mainAxisSpacing: AppSpacing.md,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _ProductCard(
                                product: filtered[i],
                                qty: _qtyOf(cart, filtered[i].id),
                              ),
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

/// Sticky bar: always shows how much is in the cart and one tap to review it.
class _CartBar extends StatelessWidget {
  final int count;
  final int totalCentimes;
  final VoidCallback onTap;

  const _CartBar({
    required this.count,
    required this.totalCentimes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
        child: Material(
          color: theme.colorScheme.primary,
          borderRadius: AppRadius.mdAll,
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: Row(
                children: [
                  Badge(
                    label: Text('$count'),
                    backgroundColor: theme.colorScheme.onPrimary,
                    textColor: theme.colorScheme.primary,
                    child: Icon(Icons.shopping_cart_rounded,
                        color: theme.colorScheme.onPrimary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text('عرض السلة وإتمام الطلب',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold)),
                  ),
                  DzdPriceTag(
                    centimes: totalCentimes,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold),
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

class _ProductCard extends ConsumerWidget {
  final ProductEntity product;
  final int qty;

  const _ProductCard({required this.product, required this.qty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final notifier = ref.read(customerCartProvider.notifier);
    final retail = product.getPriceForQuantity(PriceTier.retail, 1);
    final wholesale = product.getPriceForQuantity(PriceTier.wholesale, 1);
    final bulk = product.getPriceForQuantity(PriceTier.bulk, 1);
    final isAvailable = product.availableQty > 0;
    final canAddMore = qty < product.availableQty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Name + stock
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.nameAr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      if (product.nameFr.isNotEmpty)
                        Text(product.nameFr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StockBadge(
                    availableQty: product.availableQty, unitName: product.unit),
              ],
            ),

            // Pack info
            Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${product.unit} · ${product.packSize} قطع في الشحنة',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),

            // Prices: wholesale is the hero, others are secondary
            Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withAlpha(90),
                borderRadius: AppRadius.mdAll,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('سعر الجملة',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                            if (retail > wholesale) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade700,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'وفر ${((retail - wholesale) / 100).toStringAsFixed(0)} دج',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        DzdPriceTag(
                          centimes: wholesale,
                          style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold, color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _smallPrice(theme, 'تجزئة', retail),
                      const SizedBox(height: 2),
                      _smallPrice(theme, 'كميات', bulk),
                    ],
                  ),
                ],
              ),
            ),

            // Action: add button turns into a quantity stepper
            SizedBox(
              width: double.infinity,
              child: qty == 0
                  ? FilledButton.icon(
                      onPressed: isAvailable
                          ? () {
                              notifier.addProduct(product);
                            }
                          : null,
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: Text(isAvailable ? 'أضف للطلبية' : 'نفذت الكمية'),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () =>
                              notifier.updateQuantity(product.id, qty - 1),
                          icon: Icon(
                              qty == 1 ? Icons.delete_outline : Icons.remove),
                        ),
                        Column(
                          children: [
                            Text('$qty',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            Text('في السلة',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                        IconButton.filled(
                          onPressed: canAddMore
                              ? () =>
                                  notifier.updateQuantity(product.id, qty + 1)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallPrice(ThemeData theme, String label, int centimes) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        DzdPriceTag(
          centimes: centimes,
          style: theme.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}