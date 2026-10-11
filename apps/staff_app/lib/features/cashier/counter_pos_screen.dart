import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'services/pos_thermal_printer.dart';
import 'widgets/pos_keyboard_dispatcher.dart';
import 'widgets/pos_header_status_bar.dart';
import 'widgets/pos_category_filter_bar.dart';
import 'widgets/pos_product_card.dart';
import 'widgets/pos_cart_line_item_tile.dart';
import 'widgets/pos_checkout_dialog.dart';
import 'widgets/customer_select_dialog.dart';
import 'widgets/custom_item_dialog.dart';
import 'widgets/item_discount_dialog.dart';
import 'widgets/held_tickets_sheet.dart';
import 'widgets/sales_history_dialog.dart';
import 'widgets/sales_return_dialog.dart';
import 'widgets/shift_audit_dialog.dart';
import 'widgets/customer_debt_dialog.dart';
import 'widgets/cashier_pin_dialog.dart';
import 'widgets/printer_settings_dialog.dart';

class CounterPosScreen extends ConsumerStatefulWidget {
  const CounterPosScreen({super.key});

  @override
  ConsumerState<CounterPosScreen> createState() => _CounterPosScreenState();
}

class _CounterPosScreenState extends ConsumerState<CounterPosScreen> {
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  String _selectedCategory = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shift = ref.read(posActiveShiftProvider);
      if (shift == null) {
        _openShiftAudit();
      } else {
        _ensureBarcodeFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  void _ensureBarcodeFocus() {
    if (mounted && !_barcodeFocusNode.hasFocus) {
      _barcodeFocusNode.requestFocus();
    }
  }

  void _onBarcodeSubmitted(String barcode) async {
    final cleanCode = barcode.trim();
    if (cleanCode.isEmpty) {
      _ensureBarcodeFocus();
      return;
    }

    final shift = ref.read(posActiveShiftProvider);
    if (shift == null) {
      _barcodeController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('الوردية مغلقة! يرجى فتح الوردية وتحديد الرصيد الافتتاحي أولاً لبدء البيع.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: SnackBarAction(
            label: 'فتح وردية [F10]',
            textColor: Colors.white,
            onPressed: _openShiftAudit,
          ),
        ),
      );
      _openShiftAudit();
      return;
    }

    final repo = ref.read(productRepositoryProvider);
    try {
      final product = await repo.getProductByBarcode(cleanCode);
      if (product != null) {
        if (product.availableQty <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('المنتج "${product.nameAr}" نفذ تمامًا من المخزون!'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          _barcodeController.clear();
          _ensureBarcodeFocus();
          return;
        }

        ref.read(posCartProvider.notifier).addProduct(product);
        _barcodeController.clear();
        _ensureBarcodeFocus();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ أضيف: ${product.nameAr}'),
              duration: const Duration(milliseconds: 700),
              backgroundColor: context.appColors.success,
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم يتم العثور على منتج بالباركود: $cleanCode'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        _barcodeController.clear();
        _ensureBarcodeFocus();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تعذر فحص الباركود، تحقق من الاتصال.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      _barcodeController.clear();
      _ensureBarcodeFocus();
    }
  }

  // Modals & Dialog Openers
  void _openCustomerSearch() async {
    final customer = await showDialog<CustomerProfileEntity?>(
      context: context,
      builder: (_) => const CustomerSelectDialog(),
    );
    ref.read(posActiveCustomerProvider.notifier).state = customer;
    _ensureBarcodeFocus();
  }

  void _openCustomerDebtModal([CustomerProfileEntity? targetCustomer]) async {
    var customer = targetCustomer ?? ref.read(posActiveCustomerProvider);
    if (customer == null) {
      customer = await showDialog<CustomerProfileEntity?>(
        context: context,
        builder: (_) => const CustomerSelectDialog(),
      );
      if (customer != null) {
        ref.read(posActiveCustomerProvider.notifier).state = customer;
      }
    }

    if (customer == null || !mounted) {
      _ensureBarcodeFocus();
      return;
    }

    final user = ref.read(authStateProvider);
    final cashierId = user?.id ?? '11111111-1111-1111-1111-111111111111';
    final cashierName = user?.name ?? 'الكاشير';

    final paid = await showDialog<bool>(
      context: context,
      builder: (_) => CustomerDebtDialog(
        customer: customer!,
        cashierId: cashierId,
        cashierName: cashierName,
      ),
    );

    if (paid == true && mounted) {
      final updated = await ref.read(customerRepositoryProvider).getCustomerById(customer.id);
      if (updated != null) {
        ref.read(posActiveCustomerProvider.notifier).state = updated;
      }
    }

    _ensureBarcodeFocus();
  }

  void _openCustomItemModal() async {
    final shift = ref.read(posActiveShiftProvider);
    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('الوردية مغلقة! يرجى فتح الوردية أولاً لإضافة منتج مخصص.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: SnackBarAction(label: 'فتح وردية [F10]', textColor: Colors.white, onPressed: _openShiftAudit),
        ),
      );
      _openShiftAudit();
      return;
    }

    final customData = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const CustomItemDialog(),
    );
    if (customData != null) {
      ref.read(posCartProvider.notifier).addCustomItem(
            customData['name'] as String,
            customData['priceCentimes'] as int,
            qty: customData['qty'] as int,
            unit: customData['unit'] as PosItemUnit,
          );
    }
    _ensureBarcodeFocus();
  }

  void _openHeldTicketsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const HeldTicketsSheet(),
    ).then((_) => _ensureBarcodeFocus());
  }

  void _openSalesHistory() {
    showDialog(
      context: context,
      builder: (_) => const SalesHistoryDialog(),
    ).then((_) => _ensureBarcodeFocus());
  }

  void _openSalesReturns() {
    showDialog(
      context: context,
      builder: (_) => const SalesReturnDialog(),
    ).then((_) => _ensureBarcodeFocus());
  }

  void _openShiftAudit() {
    showDialog(
      context: context,
      builder: (_) => const ShiftAuditDialog(),
    ).then((_) => _ensureBarcodeFocus());
  }

  void _openPrinterSettings() {
    showDialog(
      context: context,
      builder: (_) => const PrinterSettingsDialog(),
    ).then((_) => _ensureBarcodeFocus());
  }

  void _openPinDialog({CashierPinMode mode = CashierPinMode.switchCashier}) async {
    final user = ref.read(authStateProvider);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: mode == CashierPinMode.switchCashier,
      builder: (_) => CashierPinDialog(
        mode: mode,
        lockedUser: user,
      ),
    );

    if (result == true && mounted) {
      if (mode == CashierPinMode.switchCashier) {
        final newUser = ref.read(authStateProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تبديل الكاشير إلى: ${newUser?.name ?? "الكاشير"}'),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    }
    _ensureBarcodeFocus();
  }

  void _openItemDiscount(PosCartItem item) async {
    final discount = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ItemDiscountDialog(item: item),
    );
    if (discount != null) {
      ref.read(posCartProvider.notifier).setItemDiscount(
            item.id,
            percent: (discount['percent'] as num).toDouble(),
            fixedCentimes: (discount['fixed'] as num).toInt(),
          );
    }
    _ensureBarcodeFocus();
  }

  Future<void> _openCheckoutDialog(int totalCentimes) async {
    final shift = ref.read(posActiveShiftProvider);
    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('الوردية مغلقة. يرجى فتح وردية جديدة أولاً لإتمام البيع.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: SnackBarAction(label: 'فتح وردية [F10]', textColor: Colors.white, onPressed: _openShiftAudit),
        ),
      );
      _openShiftAudit();
      return;
    }

    final cart = ref.read(posCartProvider);
    if (cart.isEmpty) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => PosCheckoutDialog(totalCentimes: totalCentimes),
    );

    if (result != null && mounted) {
      final user = ref.read(authStateProvider);
      final customer = ref.read(posActiveCustomerProvider);

      final checkoutRes = await ref.read(posCartProvider.notifier).checkout(
            cashierId: user?.id ?? '11111111-1111-1111-1111-111111111111',
            customerId: customer?.id,
            paidCashCentimes: result['paidCash'] as int,
            onAccountCentimes: result['onAccount'] as int,
          );

      if (checkoutRes.isSuccess) {
        final orderId = checkoutRes.data!;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تسجيل عملية البيع بنجاح! رقم الوصل: #${orderId.substring(0, 8)}'),
            backgroundColor: context.appColors.success,
          ),
        );

        if (result['autoPrint'] == true) {
          PosThermalPrinterService.printSalesReceipt(
            orderId: orderId,
            cashierName: user?.name ?? 'أمين الصندوق',
            customer: customer,
            items: cart,
            totalCentimes: totalCentimes,
            paidCashCentimes: result['paidCash'] as int,
            onAccountCentimes: result['onAccount'] as int,
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(checkoutRes.failure?.message ?? 'فشلت عملية تسجيل البيع'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
    _ensureBarcodeFocus();
  }

  void _openMobileCartSheet(int totalCentimes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: AppRadius.pillAll,
                ),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: _buildCartPanel(isMobileSheet: true, scrollController: scrollController),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _ensureBarcodeFocus());
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider);
    final activeCustomer = ref.watch(posActiveCustomerProvider);
    final shift = ref.watch(posActiveShiftProvider);
    final heldTickets = ref.watch(posHeldTicketsProvider);
    final isCompact = context.isCompact;
    final totalCentimes = ref.watch(posCartProvider.notifier).totalCentimes;
    final cart = ref.watch(posCartProvider);

    return PosKeyboardDispatcher(
      onF1Search: () => _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length),
      onF2Customer: _openCustomerSearch,
      onF3CustomItem: _openCustomItemModal,
      onF4HoldCart: () {
        if (cart.isNotEmpty) {
          ref.read(posCartProvider.notifier).holdCurrentCart();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم تعليق السلة بنجاح [Hold Ticket]'),
              duration: const Duration(milliseconds: 900),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      },
      onF5ResumeCart: () {
        if (heldTickets.isNotEmpty) {
          _openHeldTicketsSheet();
        }
      },
      onF6PrinterSettings: _openPrinterSettings,
      onF7CollectDebt: _openCustomerDebtModal,
      onF8SalesHistory: _openSalesHistory,
      onF9Returns: _openSalesReturns,
      onF10ZReport: _openShiftAudit,
      onF11LockScreen: () => _openPinDialog(mode: CashierPinMode.unlockTerminal),
      onF12Checkout: () => _openCheckoutDialog(totalCentimes),
      onEscapeClear: () => ref.read(posCartProvider.notifier).clear(),
      child: Scaffold(
        appBar: PosHeaderStatusBar(
          cashierUser: authUser,
          activeShift: shift,
          activeCustomer: activeCustomer,
          heldTicketsCount: heldTickets.length,
          onOpenShift: _openShiftAudit,
          onOpenCustomerSearch: _openCustomerSearch,
          onClearCustomer: () => ref.read(posActiveCustomerProvider.notifier).state = null,
          onCollectDebt: _openCustomerDebtModal,
          onOpenHeldTickets: _openHeldTicketsSheet,
          onOpenSalesHistory: _openSalesHistory,
          onOpenReturns: _openSalesReturns,
          onOpenShiftAudit: _openShiftAudit,
          onOpenPrinterSettings: _openPrinterSettings,
          onFastSwitchCashier: () => _openPinDialog(mode: CashierPinMode.switchCashier),
          onLockScreen: () => _openPinDialog(mode: CashierPinMode.unlockTerminal),
          onRefreshStock: () => ref.invalidate(liveProductsProvider),
          onLogout: () => ref.read(authStateProvider.notifier).state = null,
        ),
        bottomNavigationBar: isCompact && cart.isNotEmpty
            ? Container(
                padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${cart.length} منتجات في السلة', style: Theme.of(context).textTheme.bodySmall),
                          DzdPriceTag(centimes: totalCentimes, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openMobileCartSheet(totalCentimes),
                      icon: const Icon(Icons.shopping_cart_checkout),
                      label: const Text('إتمام الدفع [F12]'),
                    ),
                  ],
                ),
              )
            : null,
        body: isCompact
            ? _buildCatalogPane()
            : Row(
                children: [
                  Expanded(flex: 3, child: _buildCatalogPane()),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: context.isLarge || context.isExtraLarge ? 440 : 380,
                    child: _buildCartPanel(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCatalogPane() {
    final productsAsync = ref.watch(liveProductsProvider);
    final cart = ref.watch(posCartProvider);
    final cartNotifier = ref.read(posCartProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search, Scanner, Custom Item Island
          Container(
            padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'ابحث بالاسم أو الفئة [F1]...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(productsSearchQueryProvider.notifier).state = '';
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      ref.read(productsSearchQueryProvider.notifier).state = val;
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
                  child: TextField(
                    controller: _barcodeController,
                    focusNode: _barcodeFocusNode,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'مسح الباركود المباشر...',
                      prefixIcon: Icon(Icons.qr_code_scanner, size: 18),
                    ),
                    onSubmitted: _onBarcodeSubmitted,
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _openCustomItemModal,
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  label: const Text('منتج غير مسجل [F3]', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          AppSpacing.gapSm,
          // Category Filter Bar
          PosCategoryFilterBar(
            selectedCategory: _selectedCategory,
            onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
          ),
          AppSpacing.gapSm,
          // Product Virtual Grid
          Expanded(
            child: productsAsync.when(
              data: (products) {
                var filtered = products;
                if (_selectedCategory.isNotEmpty) {
                  filtered = filtered.where((p) {
                    return p.category.toLowerCase().contains(_selectedCategory.toLowerCase());
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return AppEmptyView(
                    icon: Icons.inventory_2_outlined,
                    title: 'لا توجد منتجات مطابقة',
                    description: 'لم يتم العثور على أي منتج يطابق خيارات البحث الحالية.',
                    actionLabel: 'إعادة ضبط الفلاتر',
                    onAction: () {
                      _searchController.clear();
                      setState(() => _selectedCategory = '');
                      ref.read(productsSearchQueryProvider.notifier).state = '';
                    },
                  );
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 0.90,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final product = filtered[index];
                    final inCartQty = cart
                        .where((it) => it.productId == product.id)
                        .fold(0, (sum, it) => sum + it.quantity);

                    return PosProductCard(
                      product: product,
                      cartQuantity: inCartQty,
                      onAddToCart: () {
                        final shift = ref.read(posActiveShiftProvider);
                        if (shift == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('الوردية مغلقة! يرجى فتح الوردية وتحديد الرصيد الافتتاحي لبدء البيع.'),
                              backgroundColor: Theme.of(context).colorScheme.error,
                              action: SnackBarAction(label: 'فتح وردية [F10]', textColor: Colors.white, onPressed: _openShiftAudit),
                            ),
                          );
                          _openShiftAudit();
                          return;
                        }
                        cartNotifier.addProduct(product);
                      },
                    );
                  },
                );
              },
              loading: () => const AppLoadingView(message: 'جاري جلب المنتجات والمخزون المباشر...'),
              error: (err, _) => AppErrorView(
                message: 'تعذر الاتصال بقاعدة البيانات لجلب المنتجات.',
                onRetry: () => ref.invalidate(liveProductsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPanel({bool isMobileSheet = false, ScrollController? scrollController}) {
    final cart = ref.watch(posCartProvider);
    final cartNotifier = ref.read(posCartProvider.notifier);
    final totalCentimes = cartNotifier.totalCentimes;
    final shift = ref.watch(posActiveShiftProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mandatory Shift Closed Notice Banner
          if (shift == null)
            Container(
              margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_clock, size: 20, color: colorScheme.onErrorContainer),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'الوردية مغلقة حالياً',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'يجب فتح وردية جديدة وتسجيل العهدة الافتتاحية للصندوق لبدء البيع والتحصيل.',
                    style: TextStyle(fontSize: 11, color: colorScheme.onErrorContainer),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _openShiftAudit,
                    icon: const Icon(Icons.lock_open, size: 16),
                    label: const Text('فتح وردية جديدة [F10]', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Cart Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'وصل المبيعات (${cart.length})',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (cart.isNotEmpty)
                Row(
                  children: [
                    IconButton(
                      tooltip: 'تعليق السلة [F4]',
                      icon: const Icon(Icons.pause_circle_filled_outlined, size: 20),
                      onPressed: () {
                        cartNotifier.holdCurrentCart();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('تم تعليق السلة بنجاح [Hold Ticket]'),
                            backgroundColor: colorScheme.primary,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'تفريغ السلة [Esc]',
                      icon: Icon(Icons.delete_sweep_outlined, color: colorScheme.error, size: 20),
                      onPressed: () => cartNotifier.clear(),
                    ),
                  ],
                ),
            ],
          ),
          const Divider(height: 12),
          // Items List
          if (cart.isEmpty)
            const Expanded(
              child: AppEmptyView(
                icon: Icons.shopping_basket_outlined,
                title: 'السلة فارغة',
                description: 'انقر على المنتجات أو امسح الباركود لإضافتها إلى وصل البيع.',
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: cart.length,
                itemBuilder: (context, index) {
                  final item = cart[index];
                  return PosCartLineItemTile(
                    item: item,
                    onQuantityChanged: (newQty) {
                      final res = cartNotifier.updateQuantity(item.id, newQty);
                      if (res.isFailure) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res.failure?.message ?? 'تجاوز المخزون'),
                            duration: const Duration(milliseconds: 900),
                            backgroundColor: context.appColors.warning,
                          ),
                        );
                      }
                    },
                    onUnitChanged: (newUnit) => cartNotifier.setItemUnit(item.id, newUnit),
                    onEditDiscount: () => _openItemDiscount(item),
                    onRemove: () => cartNotifier.removeProduct(item.id),
                  );
                },
              ),
            ),
          const Divider(height: 12),
          // Financial Summary Card
          Container(
            padding: const EdgeInsetsDirectional.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('عدد الأصناف في الوصل:', style: theme.textTheme.bodySmall),
                    Text('${cart.length} أصناف', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('المجموع الإجمالي:', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    DzdPriceTag(
                      centimes: totalCentimes,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AppSpacing.gapMd,
          // Checkout CTA
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            ),
            onPressed: cart.isEmpty ? null : () => _openCheckoutDialog(totalCentimes),
            icon: const Icon(Icons.check_circle_rounded, size: 20),
            label: const Text(
              'دفع وإتمام الوصل [F12]',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
