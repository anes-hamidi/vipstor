import 'package:customer_app/features/profile/profile_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../../providers/customer_providers.dart';
import '../orders/my_orders_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _isSubmitting = false;

     void _editProfile() => Navigator.of(context).push(
         MaterialPageRoute(builder: (_) => const ProfileFormScreen()));

// In cart_screen.dart: replace ONLY the `build` method with this one.
// _showEditProfileDialog and the imports stay exactly as they are.

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(customerCartProvider);
    final cartNotifier = ref.read(customerCartProvider.notifier);
    final profile = ref.watch(customerProfileProvider);
    final totalCentimes = cartNotifier.totalCentimes;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Check if customer profile is incomplete
    final needsProfile = !profile.isComplete;

    Future<void> submit() async {
      if (needsProfile) {
        _editProfile();
        return;
      }
      setState(() => _isSubmitting = true);
      try {
        final orderId = await cartNotifier.checkout(profile: profile);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تم إرسال طلبيتك! رقم الطلب: ${orderId.length > 8 ? orderId.substring(0, 8) : orderId}'),
            backgroundColor: context.appColors.success,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إرسال الطلبية: $e'),
            backgroundColor: cs.error,
          ),
        );
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(cart.isEmpty ? 'سلة الطلب' : 'سلة الطلب (${cart.length})'),
        actions: [
          if (cart.isNotEmpty)
            IconButton(
              tooltip: 'تفريغ السلة',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => cartNotifier.clear(),
            ),
        ],
      ),
      // Sticky total + checkout, always visible
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المجموع',
                            style: theme.textTheme.titleMedium),
                        DzdPriceTag(
                          centimes: totalCentimes,
                          style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold, color: cs.primary),
                        ),
                      ],
                    ),
                    AppSpacing.gapSm,
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _isSubmitting ? null : submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2))
                            : Icon(needsProfile
                                ? Icons.person_pin_circle_outlined
                                : Icons.check_circle),
                        label: Text(_isSubmitting
                            ? 'جاري الإرسال...'
                            : needsProfile
                                ? 'أكمل بيانات التوصيل أولاً'
                                : 'تأكيد وإرسال الطلبية'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: ContentConstrainedBox.dashboard(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: cart.isEmpty
            ? AppEmptyView(
                icon: Icons.shopping_cart_outlined,
                title: 'سلتك فارغة',
                description: 'اختر منتجات من المتجر لتبدأ طلبيتك.',
                actionLabel: 'تصفح المنتجات',
                onAction: () => Navigator.pop(context),
              )
            : ListView(
                children: [
                  // Delivery info first: it's what blocks checkout
                  Card(
                    color: needsProfile ? cs.tertiaryContainer : null,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            needsProfile
                                ? Icons.info_outline
                                : Icons.local_shipping_outlined,
                            color: needsProfile ? cs.onTertiaryContainer : cs.primary,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  needsProfile
                                      ? 'تأكد من بيانات التوصيل'
                                      : 'التوصيل إلى',
                                  style: theme.textTheme.labelLarge,
                                ),
                                const SizedBox(height: 2),
                                Text(profile.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(profile.phone,
                                    style: theme.textTheme.bodySmall),
                                Text(
                                    '${profile.wilaya} - ${profile.commune}، ${profile.addressText}',
                                    style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _editProfile(),
                            child: Text(needsProfile ? 'أكمل' : 'تعديل'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AppSpacing.gapMd,

                  // Items: swipe to remove, stepper to change quantity
                  ...cart.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Dismissible(
                        key: ValueKey(item.product.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: AlignmentDirectional.centerEnd,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: AppRadius.mdAll,
                          ),
                          child: Icon(Icons.delete_outline,
                              color: cs.onErrorContainer),
                        ),
                        onDismissed: (_) =>
                            cartNotifier.removeProduct(item.product.id),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding:
                                const EdgeInsetsDirectional.all(AppSpacing.md),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.product.nameAr,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${DzdFormatter.formatCentimes(item.unitPrice)} للوحدة',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: cs.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                      item.quantity == 1
                                          ? Icons.delete_outline
                                          : Icons.remove,
                                      size: 18),
                                  onPressed: () => cartNotifier.updateQuantity(
                                      item.product.id, item.quantity - 1),
                                ),
                                SizedBox(
                                  width: 32,
                                  child: Text('${item.quantity}',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold)),
                                ),
                                IconButton.filled(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add, size: 18),
                                  onPressed: () => cartNotifier.updateQuantity(
                                      item.product.id, item.quantity + 1),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                SizedBox(
                                  width: 84,
                                  child: DzdPriceTag(
                                    centimes: item.lineTotal,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }}
