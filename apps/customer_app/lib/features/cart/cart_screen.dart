import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../../providers/customer_providers.dart';
import '../orders/my_orders_screen.dart';
import '../profile/profile_form_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _isSubmitting = false;

  void _editProfile() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileFormScreen()));

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(customerCartProvider);
    final cartNotifier = ref.read(customerCartProvider.notifier);
    final profile = ref.watch(customerProfileProvider);
    final totalCentimes = cartNotifier.totalCentimes;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final needsProfile = !profile.isComplete;

    Future<void> submit() async {
      if (needsProfile) {
        _editProfile();
        return;
      }
      setState(() => _isSubmitting = true);
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final colors = context.appColors;
      try {
        final orderId = await cartNotifier.checkout(profile: profile);
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text(
              'تم إرسال طلبيتك! رقم الطلب: ${orderId.length > 8 ? orderId.substring(0, 8) : orderId}'),
          backgroundColor: colors.success,
        ));
        navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const MyOrdersScreen()));
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text('تعذر إرسال الطلبية: $e'),
          backgroundColor: cs.error,
        ));
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            cart.isEmpty ? 'سلة الطلب' : 'سلة الطلب (${cart.length})'),
        actions: [
          if (cart.isNotEmpty)
            IconButton(
              tooltip: 'تفريغ السلة',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => cartNotifier.clear(),
            ),
        ],
      ),

      // ── Sticky checkout bar ────────────────────────────────────────────
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A1814)
                      : const Color(0xFFFFFDF8),
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFFD4AF37)
                          .withValues(alpha: isDark ? 0.22 : 0.16),
                      width: 1,
                    ),
                  ),
                  boxShadow: isDark
                      ? [const BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, -4))]
                      : [const BoxShadow(color: Color(0x0C000000), blurRadius: 8, offset: Offset(0, -2))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Total row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المجموع الكلي',
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.onSurfaceVariant)),
                        DzdPriceTag.hero(
                          centimes: totalCentimes,
                          gold: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Checkout button
                    GoldButton.icon(
                      icon: needsProfile
                          ? Icons.person_pin_circle_outlined
                          : Icons.check_circle_rounded,
                      label: _isSubmitting
                          ? 'جاري الإرسال...'
                          : needsProfile
                              ? 'أكمل بيانات التوصيل'
                              : 'تأكيد وإرسال الطلبية',
                      onPressed: _isSubmitting ? null : submit,
                      loading: _isSubmitting,
                      width: double.infinity,
                      height: 50,
                    ),
                  ],
                ),
              ),
            ),

      body: ContentConstrainedBox.dashboard(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: cart.isEmpty
            ? AppStates.empty(
                icon: Icons.shopping_cart_outlined,
                title: 'سلتك فارغة',
                description: 'اختر منتجات من المتجر لتبدأ طلبيتك.',
                actionLabel: 'تصفح المنتجات',
                onAction: () => Navigator.pop(context),
              )
            : ListView(
                children: [
                  // ── Delivery info card ────────────────────────────────
                  _DeliveryCard(
                    profile: profile,
                    needsProfile: needsProfile,
                    onEdit: _editProfile,
                    isDark: isDark,
                    theme: theme,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionHeader(title: 'المنتجات (${cart.length})'),
                  const SizedBox(height: AppSpacing.sm),

                  // ── Cart items ────────────────────────────────────────
                  ...cart.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Dismissible(
                          key: ValueKey(item.product.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: AlignmentDirectional.centerEnd,
                            padding: const EdgeInsetsDirectional.only(
                                end: AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: cs.errorContainer,
                              borderRadius: AppRadius.lgAll,
                            ),
                            child: Icon(Icons.delete_outline,
                                color: cs.onErrorContainer),
                          ),
                          onDismissed: (_) =>
                              cartNotifier.removeProduct(item.product.id),
                          child: LuxuryCard(
                            padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm),
                            child: Row(
                              children: [
                                // Product icon
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: isDark
                                        ? AppGradients.darkGlass
                                        : AppGradients.goldSubtleLight,
                                    borderRadius: AppRadius.smAll,
                                    border: Border.all(
                                      color: const Color(0xFFD4AF37)
                                          .withValues(alpha: 0.18),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.inventory_2_outlined,
                                    size: 18,
                                    color: isDark
                                        ? const Color(0xFFF3D278)
                                        : const Color(0xFFC59B27),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.product.nameAr,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                      Text(
                                        '${DzdFormatter.formatCentimes(item.unitPrice)} للوحدة',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: cs.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                // Quantity stepper
                                Row(
                                  children: [
                                    GoldIconButton(
                                      icon: item.quantity == 1
                                          ? Icons.delete_outline
                                          : Icons.remove_rounded,
                                      size: 32,
                                      onPressed: () =>
                                          cartNotifier.updateQuantity(
                                              item.product.id,
                                              item.quantity - 1),
                                    ),
                                    SizedBox(
                                      width: 32,
                                      child: Text(
                                        '${item.quantity}',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    GoldIconButton(
                                      icon: Icons.add_rounded,
                                      size: 32,
                                      filled: true,
                                      onPressed: () =>
                                          cartNotifier.updateQuantity(
                                              item.product.id,
                                              item.quantity + 1),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: AppSpacing.md),
                                SizedBox(
                                  width: 90,
                                  child: DzdPriceTag(
                                    centimes: item.lineTotal,
                                    gold: true,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )),
                ],
              ),
      ),
    );
  }
}

// ── Delivery Card ─────────────────────────────────────────────────────────────

class _DeliveryCard extends StatelessWidget {
  final dynamic profile;
  final bool needsProfile;
  final VoidCallback onEdit;
  final bool isDark;
  final ThemeData theme;

  const _DeliveryCard({
    required this.profile,
    required this.needsProfile,
    required this.onEdit,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return LuxuryCard(
      goldAccent: !needsProfile,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: needsProfile ? null : AppGradients.gold,
                color: needsProfile ? cs.tertiaryContainer : null,
                borderRadius: AppRadius.smAll,
                boxShadow: needsProfile ? null : [AppShadows.goldGlowSm],
              ),
              child: Icon(
                needsProfile
                    ? Icons.info_outline_rounded
                    : Icons.local_shipping_outlined,
                size: 18,
                color: needsProfile
                    ? cs.onTertiaryContainer
                    : const Color(0xFF1A1400),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    needsProfile ? 'أكمل بيانات التوصيل' : 'التوصيل إلى',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: needsProfile
                          ? cs.tertiary
                          : (isDark
                              ? const Color(0xFFF3D278)
                              : const Color(0xFFC59B27)),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(profile.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(profile.phone,
                      style: theme.textTheme.bodySmall),
                  Text(
                    '${profile.wilaya} - ${profile.commune}، ${profile.addressText}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onEdit,
              child: Text(needsProfile ? 'أكمل' : 'تعديل'),
            ),
          ],
        ),
      ),
    );
  }
}
