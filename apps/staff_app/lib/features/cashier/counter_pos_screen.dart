import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import '../moderator/widgets/staff_profile_edit_sheet.dart';
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
import 'widgets/supplier_payment_dialog.dart';
import 'widgets/driver_settlement_dialog.dart';
import 'widgets/cashier_pin_dialog.dart';
import 'widgets/printer_settings_dialog.dart';
import 'package:flutter/services.dart';
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
      _checkAppUpdates();
    });
  }

  Future<void> _checkAppUpdates() async {
    try {
      final res = await ref.read(appUpdateServiceProvider).checkForUpdate();
      if (res.hasUpdate && mounted) {
        final service = ref.read(appUpdateServiceProvider);
        AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: service,
        );
      }
    } catch (e) {
      debugPrint('[POS] Error checking updates: $e');
    }
  }

  Future<void> _checkAppUpdatesManually() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جاري التحقق من التحديثات...'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final res = await ref.read(appUpdateServiceProvider).checkForUpdate();
      if (!mounted) return;
      if (res.hasUpdate) {
        final service = ref.read(appUpdateServiceProvider);
        AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: service,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('أنت تستخدم أحدث إصدار متوفر (v${res.currentVersion} #${res.currentBuild})'),
            backgroundColor: const Color(0xFF1E3A2F),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر التحقق من التحديثات: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
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
    final cashierId = user?.id;
    if (cashierId == null) return; // router guard prevents reaching here unauthenticated
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

  void _openSupplierPaymentModal() {
    final authUser = ref.read(authStateProvider);
    final shift = ref.read(posActiveShiftProvider);

    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('الوردية مغلقة! يرجى فتح وردية الكاشير أولاً لصرف مستحقات المورد من الدرج.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: SnackBarAction(label: 'فتح وردية [F10]', textColor: Colors.white, onPressed: _openShiftAudit),
        ),
      );
      _openShiftAudit();
      return;
    }

    SupplierPaymentDialog.show(
      context,
      payerId: authUser?.id ?? shift.cashierId,
      payerName: authUser?.name ?? shift.cashierName,
      payerRole: 'Cashier (أمين الصندوق)',
    ).then((_) => _ensureBarcodeFocus());
  }

  void _openDriverSettlementModal() {
    final authUser = ref.read(authStateProvider);
    final shift = ref.read(posActiveShiftProvider);

    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('الوردية مغلقة! يرجى فتح وردية الكاشير أولاً لتسوية عهدة السائق وإيداع الكاش بالدرج.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: SnackBarAction(label: 'فتح وردية [F10]', textColor: Colors.white, onPressed: _openShiftAudit),
        ),
      );
      _openShiftAudit();
      return;
    }

    DriverSettlementDialog.show(
      context,
      receiverId: authUser?.id ?? shift.cashierId,
      receiverName: authUser?.name ?? shift.cashierName,
      receiverRole: 'cashier',
    ).then((_) => _ensureBarcodeFocus());
  }

  void _openPrinterSettings() {
    showDialog(
      context: context,
      builder: (_) => const PrinterSettingsDialog(),
    ).then((_) => _ensureBarcodeFocus());
  }

  void _openEditProfile() async {
    final user = ref.read(authStateProvider);
    if (user == null) return;
    await StaffProfileEditSheet.show(
      context, ref,
      userId:   user.id,
      name:     user.name,
      phone:    user.phone,
      role:     user.role.name,
      active:   user.active,
      language: user.language,
    );
    _ensureBarcodeFocus();
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
            cashierId: user!.id,
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
            cashierName: user.name,
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
      builder: (ctx) => Consumer(
        builder: (context, sheetRef, _) => DraggableScrollableSheet(
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
                  child: _buildCartPanel(
                    isMobileSheet: true,
                    scrollController: scrollController,
                    customRef: sheetRef,
                  ),
                ),
              ],
            ),
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
final topInset = MediaQuery.paddingOf(context).top;
final bottomInset = MediaQuery.paddingOf(context).bottom;
final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
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
        appBar:  PreferredSize(
  preferredSize: Size.fromHeight(kToolbarHeight + 42 + topInset), 
   child: AnnotatedRegion<SystemUiOverlayStyle>(
    value: isDarkTheme
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: ColoredBox(
      color: isDarkTheme ? const Color(0xFF141210) : const Color(0xFFFFFDF8),
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: PosHeaderStatusBar(
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
          onPaySupplier: _openSupplierPaymentModal,
          onSettleDriver: _openDriverSettlementModal,
          onFastSwitchCashier: () => _openPinDialog(mode: CashierPinMode.switchCashier),
          onLockScreen: () => _openPinDialog(mode: CashierPinMode.unlockTerminal),
          onRefreshStock: () => ref.invalidate(liveProductsProvider),
          onLogout: () => ref.read(authStateProvider.notifier).state = null,
          onEditProfile: _openEditProfile,
          onCheckUpdates: _checkAppUpdatesManually,
        ),

      ),
    ),
  ),
),
        bottomNavigationBar: isCompact && cart.isNotEmpty
            ? Container(
                padding: EdgeInsetsDirectional.fromSTEB(
    AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm + bottomInset),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF141210)
                      : const Color(0xFFFFFDF8),
                  border: Border(
                    top: BorderSide(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
                  ),
                  boxShadow: AppShadows.navDark,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${cart.length} منتج في السلة',
                              style: Theme.of(context).textTheme.bodySmall),
                          DzdPriceTag.lg(
                              centimes: totalCentimes, gold: true),
                        ],
                      ),
                    ),
                    GoldButton.icon(
                      icon: Icons.shopping_cart_checkout_rounded,
                      label: 'الدفع',
                      onPressed: () => _openMobileCartSheet(totalCentimes),
                      height: 48,
                    ),
                  ],
                ),
              )
            : null,
        body: isCompact
            ? _buildCatalogPane()
            : Row(
                children: [
                  Expanded(
                    flex: context.isLarge || context.isExtraLarge ? 7 : 6,
                    child: _buildCatalogPane(),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.20),
                  ),
                  SizedBox(
                    width: context.isLarge || context.isExtraLarge ? 460 : 380,
                    child: _buildCartPanel(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCatalogPane() {
    final productsAsync = ref.watch(liveProductsProvider);
    final cart          = ref.watch(posCartProvider);
    final cartNotifier  = ref.read(posCartProvider.notifier);
    final theme   = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;
    final wc      = context.windowClass;
    final isPhone = wc == WindowClass.compact;
    final showKeys = wc != WindowClass.compact && wc != WindowClass.medium;

    // Responsive product grid max tile width
    // On medium the cart panel is 380 px fixed, leaving ~220 px for the catalog.
    // maxCrossAxisExtent must be > half that so Flutter picks 1 column (~180 px+).
    final maxTileWidth = switch (wc) {
      WindowClass.compact    => 180.0,
      WindowClass.medium     => 220.0, // was 200 → forced 2 cols at ~94 px → overflow
      WindowClass.expanded   => 200.0,
      WindowClass.large      => 220.0,
      WindowClass.extraLarge => 240.0,
    };

    return Padding(
      padding: EdgeInsetsDirectional.all(isPhone ? AppSpacing.sm : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Search + barcode + custom item island ─────────────────
          Container(
            padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A1814)
                  : const Color(0xFFFAF7F0),
              borderRadius: AppRadius.lgAll,
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
              ),
            ),
            child: isPhone
                // Phone: stacked vertically
                ? Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'ابحث بالاسم أو الفئة...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    ref.read(productsSearchQueryProvider.notifier).state = '';
                                  },
                                )
                              : null,
                        ),
                        onChanged: (v) =>
                            ref.read(productsSearchQueryProvider.notifier).state = v,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              // dont open the clavier on mobile, as barcode scanners usually act as keyboard input
                              readOnly: true,
                              controller: _barcodeController,
                              focusNode: _barcodeFocusNode,
                              
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'مسح الباركود...',
                                prefixIcon: Icon(Icons.qr_code_scanner_rounded, size: 18),
                              ),
                              onSubmitted: _onBarcodeSubmitted,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          GoldButton.icon(
                            icon: Icons.add_box_rounded,
                            label: 'مخصص',
                            onPressed: _openCustomItemModal,
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  )
                // Desktop/Tablet: single row
                : Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 200, maxWidth: 340),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: showKeys ? 'ابحث بالاسم أو الفئة [F1]...' : 'ابحث بالاسم أو الفئة...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      ref.read(productsSearchQueryProvider.notifier).state = '';
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (v) =>
                              ref.read(productsSearchQueryProvider.notifier).state = v,
                        ),
                      ),
                      ConstrainedBox(
                        constraints:  const BoxConstraints(minWidth: 160, maxWidth: 240),
                        child: TextField(
                          controller: _barcodeController,
                          focusNode: _barcodeFocusNode,
                          decoration:  InputDecoration(
                            isDense: true,
                            hintText: showKeys ? 'مسح الباركود [F1]...' : 'مسح الباركود...',
                            prefixIcon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                          ),
                          onSubmitted: _onBarcodeSubmitted,
                        ),
                      ),
                      GoldButton.icon(
                        icon: Icons.add_box_rounded,
                        label: showKeys ? 'منتج مخصص [F3]' : 'منتج مخصص',
                        onPressed: _openCustomItemModal,
                        compact: true,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Category filter bar ───────────────────────────────────
          ref.watch(posCategoryListProvider).when(
            data: (cats) => PosCategoryFilterBar(
              selectedCategory: _selectedCategory,
              onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
              categories: cats,
            ),
            loading: () => PosCategoryFilterBar(
              selectedCategory: _selectedCategory,
              onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
              categories: const [],
            ),
            error: (_, __) => PosCategoryFilterBar(
              selectedCategory: _selectedCategory,
              onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
              categories: const [],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Product grid ──────────────────────────────────────────
          Expanded(
            child: productsAsync.when(
              data: (products) {
                var filtered = products;
                if (_selectedCategory.isNotEmpty) {
                  filtered = filtered
                      .where((p) =>
                          p.category.trim().toLowerCase() ==
                          _selectedCategory.trim().toLowerCase())
                      .toList();
                }

                if (filtered.isEmpty) {
                  return AppEmptyView(
                    icon: Icons.inventory_2_outlined,
                    title: 'لا توجد منتجات مطابقة',
                    description: 'لم يتم العثور على منتج يطابق خيارات البحث.',
                    actionLabel: 'إعادة ضبط الفلاتر',
                    onAction: () {
                      _searchController.clear();
                      setState(() => _selectedCategory = '');
                      ref.read(productsSearchQueryProvider.notifier).state = '';
                    },
                  );
                }

                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxTileWidth,
                    mainAxisExtent: isPhone ? 165.0 : 175.0,
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
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text('الوردية مغلقة! افتح وردية أولاً.'),
                            backgroundColor: Theme.of(context).colorScheme.error,
                            action: SnackBarAction(
                                label: 'فتح [F10]',
                                textColor: Colors.white,
                                onPressed: _openShiftAudit),
                          ));
                          _openShiftAudit();
                          return;
                        }
                        cartNotifier.addProduct(product);
                      },
                    );
                  },
                );
              },
              loading: () =>
                  const AppLoadingView(message: 'جاري جلب المنتجات...'),
              error: (err, _) => AppErrorView(
                message: 'تعذر جلب المنتجات.',
                onRetry: () => ref.invalidate(liveProductsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPanel({bool isMobileSheet = false, ScrollController? scrollController, WidgetRef? customRef}) {
    final effectiveRef = customRef ?? ref;
    final cart = effectiveRef.watch(posCartProvider);
    final cartNotifier = effectiveRef.read(posCartProvider.notifier);
    final totalCentimes = cartNotifier.totalCentimes;
    final shift = effectiveRef.watch(posActiveShiftProvider);
    final theme = Theme.of(context);
    final colors = context.appColors;
    final isDark = theme.brightness == Brightness.dark;
    final wcCart = context.windowClass;
    final showKeys = wcCart != WindowClass.compact && wcCart != WindowClass.medium;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E0C0A) : const Color(0xFFFAF7F2),
        border: BorderDirectional(
          start: BorderSide(
            color: const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.18 : 0.12),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ── Shift-closed banner ─────────────────────────────────────
          if (shift == null)
            Container(
              margin: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.10),
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: colors.error.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: colors.error, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الوردية مغلقة',
                            style: TextStyle(
                                color: colors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        Text('افتح وردية لبدء البيع',
                            style: TextStyle(
                                color: colors.error.withValues(alpha: 0.75),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                  GoldButton.icon(
                    icon: Icons.lock_open_rounded,
                    label: showKeys ? 'فتح [F10]' : 'فتح',
                    onPressed: _openShiftAudit,
                    compact: true,
                  ),
                ],
              ),
            ),

          // ── Cart header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.md, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    gradient: AppGradients.gold,
                    borderRadius: AppRadius.smAll,
                    boxShadow: [AppShadows.goldGlowSm],
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      size: 16, color: Color(0xFF1A1400)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'وصل البيع',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (cart.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      '${cart.length}',
                      style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const Spacer(),
                if (cart.isNotEmpty) ...[
                  GoldIconButton(
                    icon: Icons.pause_circle_outline_rounded,
                    tooltip: showKeys ? 'تعليق السلة [F4]' : 'تعليق السلة',
                    onPressed: () {
                      cartNotifier.holdCurrentCart();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('تم تعليق السلة'),
                        backgroundColor: colors.info,
                        duration: const Duration(milliseconds: 800),
                      ));
                    },
                    size: 32,
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: showKeys ? 'تفريغ السلة [Esc]' : 'تفريغ السلة',
                    icon: Icon(Icons.delete_sweep_rounded,
                        color: colors.error, size: 20),
                    onPressed: () => cartNotifier.clear(),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.sm),
          Divider(
            height: 1,
            color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
          ),

          // ── Item list ────────────────────────────────────────────────
          if (cart.isEmpty)
            Expanded(
              child: _EmptyCartState(onOpenCustomItem: _openCustomItemModal),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                itemCount: cart.length,
                itemBuilder: (context, index) {
                  final item = cart[index];
                  return PosCartLineItemTile(
                    item: item,
                    onQuantityChanged: (newQty) {
                      final res = cartNotifier.updateQuantity(item.id, newQty);
                      if (res.isFailure) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(res.failure?.message ?? 'تجاوز المخزون'),
                          duration: const Duration(milliseconds: 900),
                          backgroundColor: colors.warning,
                        ));
                      }
                    },
                    onUnitChanged: (newUnit) =>
                        cartNotifier.setItemUnit(item.id, newUnit),
                    onTierChanged: (newTier) =>
                        cartNotifier.setItemTier(item.id, newTier),
                    onEditDiscount: () => _openItemDiscount(item),
                    onRemove: () => cartNotifier.removeProduct(item.id),
                  );
                },
              ),
            ),

          // ── Gold total + checkout ────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141210) : const Color(0xFFFFFDF8),
              border: Border(
                top: BorderSide(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
                ),
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Item count + total row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${cart.length} صنف',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Row(
                      children: [
                        Text('المجموع: ',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        DzdPriceTag.lg(
                          centimes: totalCentimes,
                          gold: true,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Gold checkout button
                GoldButton.icon(
                  icon: Icons.check_circle_rounded,
                  label: showKeys ? 'دفع وإتمام الوصل [F12]' : 'دفع وإتمام الوصل',
                  onPressed: cart.isEmpty ? null : () => _openCheckoutDialog(totalCentimes),
                  width: double.infinity,
                  height: 52,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ── Empty Cart State — creative animated placeholder ──────────────────────────

class _EmptyCartState extends StatefulWidget {
  final VoidCallback onOpenCustomItem;
  const _EmptyCartState({required this.onOpenCustomItem});

  @override
  State<_EmptyCartState> createState() => _EmptyCartStateState();
}

class _EmptyCartStateState extends State<_EmptyCartState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _float;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _float = Tween<double>(begin: -6, end: 6).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _glow = Tween<double>(begin: 0.3, end: 0.75).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final wc = context.windowClass;
    final showShortcuts = wc != WindowClass.compact && wc != WindowClass.medium;

    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
           const SizedBox(height: 25),
            // Animated floating basket
            AnimatedBuilder(
              animation: _controller,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, _float.value),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: AppGradients.obsidian,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: _glow.value),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withValues(alpha: _glow.value * 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shopping_basket_rounded,
                    size: 36,
                    color: Color(0xFFD4AF37),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'السلة فارغة',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'امسح الباركود أو انقر على منتج\nلإضافته إلى وصل البيع',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (showShortcuts) ...[
              const SizedBox(height: AppSpacing.lg),
              // Shortcut hint chips (desktop only)
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  _HintChip(label: 'F3 منتج مخصص', onTap: widget.onOpenCustomItem, isDark: isDark),
                  _HintChip(label: 'F2 بحث زبون', onTap: null, isDark: isDark),
                  _HintChip(label: 'F5 تذاكر معلقة', onTap: null, isDark: isDark),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isDark;
  const _HintChip({required this.label, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1A14) : const Color(0xFFF3E8C8),
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF9A7319),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}