import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../../providers/inventory_providers.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'widgets/create_supplier_dialog.dart';
import 'widgets/create_product_dialog.dart';
import 'widgets/online_orders_pipeline_view.dart';
import 'widgets/purchases_history_view.dart';
import 'widgets/purchase_orders_view.dart';
import 'widgets/stock_operations_view.dart';
import 'widgets/stock_adjustment_dialog.dart';
import 'widgets/cycle_count_audit_sheet.dart';
import 'widgets/low_stock_replenishment_dashboard.dart';
import 'widgets/stock_transfer_dialog.dart';
import 'widgets/manager_command_center_view.dart';
import 'services/pdf_invoice_service.dart';
import '../common/widgets/headless_barcode_scanner_button.dart';
import '../common/services/headless_barcode_scanner_service.dart';
import '../moderator/widgets/staff_profile_edit_sheet.dart';

class PurchaseReceivingScreen extends ConsumerStatefulWidget {
  const PurchaseReceivingScreen({super.key});

  @override
  ConsumerState<PurchaseReceivingScreen> createState() =>
      _PurchaseReceivingScreenState();
}

class _PurchaseReceivingScreenState
    extends ConsumerState<PurchaseReceivingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const int _tabOverview = 0;
  static const int _tabOrders = 1;
  static const int _tabReceiving = 2;
  static const int _tabPurchases = 3;
  static const int _tabPurchaseOrders = 4;
  static const int _tabStockOps = 5;
  static const int _tabCatalog = 6;

  final _invoiceNoController = TextEditingController(
      text:
          'FAC-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 10000}');
  String? _selectedSupplierId;
  bool _isPosting = false;
  final List<Map<String, dynamic>> _invoiceItems = [];

  // Product search inside invoice selector
  final _productSearchController = TextEditingController();
  String _productSearch = '';
  String? _receivingCategory;
  // Product search & filters inside catalog tab
  final _catalogSearchController = TextEditingController();
  String _catalogSearch = '';
  String _catalogHealthFilter = 'all';
  String? _catalogCategory;

  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAppUpdates();
    });
  }

  void _handleTabChange() {
    if (_tabIndex != _tabController.index) {
      setState(() => _tabIndex = _tabController.index);
    }
  }

  void _goToTab(int index) {
    if (index < 0 || index >= _tabController.length) return;
    _tabController.animateTo(index);
    if (_tabIndex != index) setState(() => _tabIndex = index);
  }

  Future<void> _checkAppUpdates() async {
    try {
      final res = await ref.read(appUpdateServiceProvider).checkForUpdate();
      if (res.hasUpdate && mounted && res.newRelease != null) {
        final service = ref.read(appUpdateServiceProvider);
        AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: service,
          force: res.isForceUpdate,
        );
      }
    } catch (e) {
      debugPrint('[Manager] Error checking updates: $e');
    }
  }

  Future<void> _checkUpdatesManually() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جاري التحقق من التحديثات...'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final res = await ref.read(appUpdateServiceProvider).checkForUpdate();
      if (!mounted) return;
      if (res.hasUpdate && res.newRelease != null) {
        final service = ref.read(appUpdateServiceProvider);
        AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: service,
          force: res.isForceUpdate,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'أنت تستخدم أحدث إصدار متوفر (v${res.currentVersion} #${res.currentBuild})'),
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
    HeadlessBarcodeScannerService.instance.stopScanning();
    _productSearchController.dispose();
    _catalogSearchController.dispose();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _invoiceNoController.dispose();
    super.dispose();
  }

  // ─── Profile ──────────────────────────────────────────────────────────────

  Future<void> _openEditProfile() async {
    final user = ref.read(authStateProvider);
    if (user == null) return;
    final updated = await StaffProfileEditSheet.show(
      context,
      ref,
      userId: user.id,
      name: user.name,
      phone: user.phone,
      role: user.role.name,
      active: user.active,
      language: user.language,
    );
    if (updated == StaffProfileEditOutcome.updated && mounted) {
      setState(() {});
    }
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  Future<void> _showCreateSupplierDialog() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const CreateSupplierDialog(),
    );
    if (created != null && mounted) {
      ref.invalidate(suppliersProvider);
      setState(() => _selectedSupplierId = created['id'] as String);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت إضافة المورد "${created['name']}" بنجاح!'),
          backgroundColor: context.appColors.success,
        ),
      );
    }
  }

  Future<void> _showCreateProductDialog() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (ctx) => const CreateProductDialog(),
    );
    if (product != null && mounted) {
      ref.invalidate(liveProductsProvider);
      ref.invalidate(lowStockProductsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت إضافة المنتج "${product.nameAr}" بنجاح!'),
          backgroundColor: context.appColors.success,
        ),
      );
    }
  }

  // ─── Invoice logic ────────────────────────────────────────────────────────

  void _addItemToInvoice(Product product) {
    final idx =
        _invoiceItems.indexWhere((it) => it['product_id'] == product.id);
    setState(() {
      if (idx >= 0) {
        _invoiceItems[idx]['qty'] += 1;
      } else {
        _invoiceItems.add({
          'product_id': product.id,
          'product_name': product.nameAr,
          'unit': product.unit,
          'cost_centimes': product.costCentimes,
          // Store actual retail price so the repository sets selling_price correctly.
          'selling_price': product.getPriceForQuantity(PriceTier.retail, 1),
          'qty': 1,
          'old_on_hand': product.onHandQty,
          'old_weighted_cost': product.weightedAverageCostCentimes,
        });
      }
    });
  }

  Future<void> _postInvoice() async {
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('يرجى اختيار المورد أولاً!'),
        backgroundColor: context.appColors.warning,
      ));
      return;
    }
    if (_invoiceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('الفاتورة فارغة! أضف منتجات للاستلام.'),
        backgroundColor: context.appColors.warning,
      ));
      return;
    }

    setState(() => _isPosting = true);
    try {
      final repo = ref.read(purchaseRepositoryProvider);
      final authUser = ref.read(authStateProvider);
      final userId = authUser?.id;
      if (userId == null) return;

      final formattedItems = _invoiceItems.map((it) {
        final cost = (it['cost_centimes'] as num).toInt();
        final retail = it['selling_price'] != null
            ? (it['selling_price'] as num).toInt()
            : cost; // fallback: selling == cost if somehow missing
        return {
          'product_id': it['product_id'] as String,
          'quantity': (it['qty'] as num).toInt(),
          'unit_cost': cost,
          'selling_price': retail >= cost ? retail : cost,
        };
      }).toList();

      final purchaseId = await repo.createDraftPurchase(
        supplierId: _selectedSupplierId!,
        invoiceNo: _invoiceNoController.text.trim(),
        invoiceDate: DateTime.now(),
        createdBy: userId,
        items: formattedItems,
      );
      await repo.postPurchase(purchaseId: purchaseId, userId: userId);
      ref.invalidate(liveProductsProvider);
      ref.invalidate(purchasesListProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('تم استلام الفاتورة وترحيل السلع للمخزون بنجاح!'),
        backgroundColor: context.appColors.success,
        action: SnackBarAction(
          label: 'عرض في السجل',
          textColor: Colors.white,
          onPressed: () => _goToTab(_tabPurchases),
        ),
      ));
      setState(() {
        _invoiceItems.clear();
        _invoiceNoController.text =
            'FAC-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 10000}';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('فشل ترحيل الفاتورة: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  // ─── Shell ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWide = MediaQuery.sizeOf(context).width >= 1000;

    final tabViews = <Widget>[
      ManagerCommandCenterView(onNavigateTab: _goToTab),
      const OnlineOrdersPipelineView(),
      _buildReceivingTab(),
      PurchasesHistoryView(
        onNavigateToReceiving: () => _goToTab(_tabReceiving),
      ),
      const PurchaseOrdersView(),
      const StockOperationsView(),
      _buildCatalogTab(),
    ];

    final mainScaffold = Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0E0C0A) : const Color(0xFFF8F5EE),
      appBar: _buildAppBar(authUser, theme, isDark, isWide),
      body: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRail(authUser, theme, isDark),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: tabViews,
                  ),
                ),
              ],
            )
          : TabBarView(
              controller: _tabController,
              children: tabViews,
            ),
    );

    void focusSearch() {
      if (_tabIndex == _tabReceiving) {
        _productSearchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _productSearchController.text.length,
        );
      } else if (_tabIndex == _tabCatalog) {
        _catalogSearchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _catalogSearchController.text.length,
        );
      }
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          focusSearch,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): focusSearch,
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
        _resetInvoice();
        _goToTab(_tabReceiving);
      },
      const SingleActivator(LogicalKeyboardKey.escape): () {
        setState(() {
          _productSearch = '';
          _productSearchController.clear();
          _catalogSearch = '';
          _catalogSearchController.clear();
        });
      },
      for (var i = 0; i < 7; i++)
        SingleActivator(
          [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4,
            LogicalKeyboardKey.digit5,
            LogicalKeyboardKey.digit6,
            LogicalKeyboardKey.digit7,
          ][i],
          control: true,
        ): () => _goToTab(i),
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: mainScaffold,
      ),
    );
  }

  void _resetInvoice() {
    setState(() {
      _invoiceNoController.text =
          'FAC-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 10000}';
      _invoiceItems.clear();
    });
  }

  PreferredSizeWidget _buildAppBar(
    UserEntity? authUser,
    ThemeData theme,
    bool isDark,
    bool isWide,
  ) {
    final lowStockCount =
        ref.watch(lowStockProductsProvider).value?.length ?? 0;
    final unverified = ref.watch(unverifiedOrdersCountProvider);
    final pendingOps = ref.watch(pendingOpsCountProvider).value ?? 0;
    final isOnline = ref.watch(connectivityProvider).value ?? true;

    return AppBar(
      backgroundColor:
          isDark ? const Color(0xFF141210) : const Color(0xFFFBF8F0),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: isWide ? AppSpacing.md : 0,
      title: InkWell(
        onTap: _openEditProfile,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppGradients.gold,
                  borderRadius: AppRadius.smAll,
                  boxShadow: [AppShadows.goldGlowSm],
                ),
                child: Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(
                    Icons.storefront_rounded,
                    size: 18,
                    color: Color(0xFF1A1400),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مركز إدارة المخزون',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            authUser?.name ?? 'مدير المخزون',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color:
                                isOnline ? const Color(0xFF27AE60) : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            !isOnline
                                ? 'غير متصل${pendingOps > 0 ? ' • $pendingOps معلّق' : ''}'
                                : pendingOps > 0
                                    ? '$pendingOps بانتظار المزامنة'
                                    : 'متصل',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 9.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isWide) ...[
          GoldButton.icon(
            icon: Icons.add_shopping_cart_rounded,
            label: 'استلام فاتورة',
            compact: true,
            height: 38,
            onPressed: () => _goToTab(_tabReceiving),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        IconButton(
          tooltip: 'المخزون المنخفض ($lowStockCount)',
          icon: Badge(
            isLabelVisible: lowStockCount > 0,
            label: Text(
              '$lowStockCount',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: lowStockCount > 0
                ? const Color(0xFFF2994A)
                : const Color(0xFF27AE60),
            child: const Icon(Icons.notification_important_outlined),
          ),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LowStockReplenishmentDashboard(
                  onOpenPurchaseOrders: () {
                    Navigator.of(context).pop();
                    _goToTab(_tabPurchaseOrders);
                  },
                ),
              ),
            );
          },
        ),
        if (!context.isCompact)
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshAll,
          ),
        PopupMenuButton<String>(
          tooltip: 'المزيد',
          icon: Badge(
            isLabelVisible: unverified > 0,
            smallSize: 7,
            backgroundColor: const Color(0xFFD4AF37),
            child: const Icon(Icons.more_vert_rounded),
          ),
          onSelected: (value) async {
            switch (value) {
              case 'refresh':
                _refreshAll();
                break;
              case 'updates':
                await _checkUpdatesManually();
                break;
              case 'profile':
                await _openEditProfile();
                break;
              case 'supplier':
                await _showCreateSupplierDialog();
                break;
              case 'product':
                await _showCreateProductDialog();
                break;
              case 'adjustment':
                await showDialog<void>(
                  context: context,
                  builder: (_) => const StockAdjustmentDialog(),
                );
                ref.invalidate(stockAdjustmentHistoryProvider);
                ref.invalidate(liveProductsProvider);
                ref.invalidate(lowStockProductsProvider);
                break;
              case 'transfer':
                await showDialog<void>(
                  context: context,
                  builder: (_) => const StockTransferDialog(),
                );
                ref.invalidate(stockTransfersProvider);
                break;
              case 'cycle':
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.94,
                  ),
                  builder: (_) => const CycleCountAuditSheet(),
                );
                ref.invalidate(auditHistoryProvider);
                ref.invalidate(activeCycleCountProvider);
                ref.invalidate(liveProductsProvider);
                ref.invalidate(lowStockProductsProvider);
                break;
              case 'low-stock':
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LowStockReplenishmentDashboard(
                      onOpenPurchaseOrders: () {
                        Navigator.of(context).pop();
                        _goToTab(_tabPurchaseOrders);
                      },
                    ),
                  ),
                );
                break;
              case 'logout':
                ref.read(authStateProvider.notifier).state = null;
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.refresh_rounded, size: 19),
                title: Text('تحديث البيانات'),
              ),
            ),
            const PopupMenuItem(
              value: 'updates',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.system_update_rounded, size: 19),
                title: Text('التحقق من التحديثات'),
              ),
            ),
            const PopupMenuItem(
              value: 'profile',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.manage_accounts_outlined, size: 19),
                title: Text('الملف الشخصي'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'supplier',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.person_add_alt_1_rounded, size: 19),
                title: Text('مورد جديد'),
              ),
            ),
            const PopupMenuItem(
              value: 'product',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.add_box_outlined, size: 19),
                title: Text('منتج جديد'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'adjustment',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.tune_rounded, size: 19),
                title: Text('تسوية مخزون'),
              ),
            ),
            const PopupMenuItem(
              value: 'transfer',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.swap_horiz_rounded, size: 19),
                title: Text('نقل داخلي'),
              ),
            ),
            const PopupMenuItem(
              value: 'cycle',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.fact_check_outlined, size: 19),
                title: Text('جرد دوري'),
              ),
            ),
            const PopupMenuItem(
              value: 'low-stock',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.inventory_2_outlined, size: 19),
                title: Text('إعادة التزويد'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'logout',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.logout_rounded, size: 19),
                title: Text('تسجيل الخروج'),
              ),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      bottom: isWide
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
                    ),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: const Color(0xFFD4AF37),
                  indicatorWeight: 2.5,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    const Tab(
                      height: 58,
                      icon: Icon(Icons.dashboard_rounded, size: 18),
                      text: 'نظرة عامة',
                    ),
                    Tab(
                      height: 58,
                      icon: Builder(builder: (context) {
                        final count = ref.watch(unverifiedOrdersCountProvider);
                        return Badge(
                          isLabelVisible: count > 0,
                          label: Text(
                            '$count',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                          backgroundColor: const Color(0xFFD4AF37),
                          textColor: const Color(0xFF1A1400),
                          child: const Icon(
                            Icons.shopping_bag_outlined,
                            size: 18,
                          ),
                        );
                      }),
                      text: 'الطلبيات',
                    ),
                    const Tab(
                      height: 58,
                      icon: Icon(Icons.add_shopping_cart_rounded, size: 18),
                      text: 'الاستلام',
                    ),
                    const Tab(
                      height: 58,
                      icon: Icon(Icons.receipt_long_outlined, size: 18),
                      text: 'المشتريات',
                    ),
                    const Tab(
                      height: 58,
                      icon: Icon(Icons.post_add_rounded, size: 18),
                      text: 'أوامر الشراء',
                    ),
                    const Tab(
                      height: 58,
                      icon: Icon(Icons.warehouse_outlined, size: 18),
                      text: 'العمليات',
                    ),
                    const Tab(
                      height: 58,
                      icon: Icon(Icons.grid_view_rounded, size: 18),
                      text: 'الكتالوج',
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRail(UserEntity? authUser, ThemeData theme, bool isDark) {
    final displayName = (authUser?.name ?? '').trim();
    final userInitial =
        displayName.isEmpty ? 'M' : displayName.characters.first.toUpperCase();
    final unverified = ref.watch(unverifiedOrdersCountProvider);
    final lowStockCount =
        ref.watch(lowStockProductsProvider).value?.length ?? 0;
    final openPos = ref
            .watch(purchaseOrdersListProvider)
            .value
            ?.where((po) => po.isOrdered || po.isPartiallyReceived)
            .length ??
        0;
    final activeTransfers = ref
            .watch(stockTransfersProvider)
            .value
            ?.where((t) => t.isPending || t.isInTransit)
            .length ??
        0;

    final items = [
      _RailItem(
        icon: Icons.dashboard_rounded,
        label: 'نظرة عامة',
        selected: _tabIndex == _tabOverview,
        onTap: () => _goToTab(_tabOverview),
      ),
      _RailItem(
        icon: Icons.shopping_bag_outlined,
        label: 'طلبيات الزبائن',
        selected: _tabIndex == _tabOrders,
        badge: unverified,
        onTap: () => _goToTab(_tabOrders),
      ),
      _RailItem(
        icon: Icons.add_shopping_cart_rounded,
        label: 'استلام الفواتير',
        selected: _tabIndex == _tabReceiving,
        onTap: () => _goToTab(_tabReceiving),
      ),
      _RailItem(
        icon: Icons.receipt_long_outlined,
        label: 'سجل المشتريات',
        selected: _tabIndex == _tabPurchases,
        onTap: () => _goToTab(_tabPurchases),
      ),
      _RailItem(
        icon: Icons.post_add_rounded,
        label: 'أوامر الشراء',
        selected: _tabIndex == _tabPurchaseOrders,
        badge: openPos,
        onTap: () => _goToTab(_tabPurchaseOrders),
      ),
      _RailItem(
        icon: Icons.warehouse_outlined,
        label: 'العمليات المخزنية',
        selected: _tabIndex == _tabStockOps,
        badge: activeTransfers,
        onTap: () => _goToTab(_tabStockOps),
      ),
      _RailItem(
        icon: Icons.grid_view_rounded,
        label: 'كتالوج المنتجات',
        selected: _tabIndex == _tabCatalog,
        onTap: () => _goToTab(_tabCatalog),
      ),
    ];

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141210) : const Color(0xFFFBF8F0),
        border: BorderDirectional(
          end: BorderSide(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.16),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFD4AF37).withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.diamond_outlined,
                    size: 19,
                    color: Color(0xFFB8860B),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VIP STOCK',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: const Color(0xFFB8860B),
                          ),
                        ),
                        Text(
                          'Inventory Workspace',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 8.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              children: [
                ...items,
                if (lowStockCount > 0) ...[
                  const Divider(height: AppSpacing.lg),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LowStockReplenishmentDashboard(
                            onOpenPurchaseOrders: () {
                              Navigator.of(context).pop();
                              _goToTab(_tabPurchaseOrders);
                            },
                          ),
                        ),
                      );
                    },
                    borderRadius: AppRadius.mdAll,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2994A).withValues(alpha: 0.10),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color:
                              const Color(0xFFF2994A).withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.notification_important_outlined,
                            size: 16,
                            color: Color(0xFFF2994A),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$lowStockCount صنف يحتاج تزويداً',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF2994A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      const Color(0xFFD4AF37).withValues(alpha: 0.16),
                  child: Text(
                    userInitial,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB8860B),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authUser?.name ?? 'مدير المخزون',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'مدير المخزون',
                        style: TextStyle(
                          fontSize: 8.5,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل الملف الشخصي',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.manage_accounts_outlined, size: 17),
                  onPressed: _openEditProfile,
                ),
                IconButton(
                  tooltip: 'تسجيل الخروج',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  onPressed: () =>
                      ref.read(authStateProvider.notifier).state = null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _refreshAll() {
    ref.invalidate(liveProductsProvider);
    ref.invalidate(suppliersProvider);
    ref.invalidate(purchasesListProvider);
    ref.invalidate(managerOnlineOrdersProvider);
    ref.invalidate(lowStockProductsProvider);
    ref.invalidate(purchaseOrdersListProvider);
    ref.invalidate(stockAdjustmentHistoryProvider);
    ref.invalidate(stockTransfersProvider);
    ref.invalidate(auditHistoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تحديث بيانات مساحة العمل.'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ─── Receiving Tab ────────────────────────────────────────────────────────

  Widget _buildReceivingTab() {
    final suppliersAsync = ref.watch(suppliersProvider);
    final productsAsync = ref.watch(liveProductsProvider);
    final isCompact = context.isCompact;

    final invoiceTotal = _invoiceItems.fold<int>(
        0, (s, it) => s + (it['cost_centimes'] as int) * (it['qty'] as int));

    // On compact: scrollable column stacked vertically.
    // On wide: Row needs BOUNDED height so Expanded inside _buildProductSelector works.
    // SizedBox.expand() fills the TabBarView cell (bounded by the Scaffold body).
    if (isCompact) {
      return SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          children: [
            _buildInvoiceHeader(suppliersAsync),
            AppSpacing.gapLg,
            _buildInvoiceLines(invoiceTotal),
            AppSpacing.gapLg,
            _buildProductSelector(productsAsync),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildInvoiceHeader(suppliersAsync),
                  AppSpacing.gapLg,
                  _buildInvoiceLines(invoiceTotal),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 2,
            child: _buildProductSelector(productsAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceHeader(
      AsyncValue<List<Map<String, dynamic>>> suppliersAsync) {
    return LuxuryCard(
      goldAccent: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'بيانات فاتورة الشراء'),
          AppSpacing.gapMd,
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
                child: TextField(
                  controller: _invoiceNoController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الفاتورة *',
                    prefixIcon: Icon(Icons.receipt_outlined),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
                child: suppliersAsync.when(
                  // skipLoadingOnRefresh allows the dropdown to stay alive with previous items while updating
                  skipLoadingOnRefresh: true,
                  data: (suppliers) {
                    // Safety check: if the selected ID is not in the fetched list, default to null
                    final hasSelectedId =
                        suppliers.any((s) => s['id'] == _selectedSupplierId);

                    return DropdownButtonFormField<String>(
                      initialValue: hasSelectedId ? _selectedSupplierId : null,
                      decoration: const InputDecoration(
                        labelText: 'المورد *',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      items: suppliers
                          .map((s) => DropdownMenuItem<String>(
                                value: s['id'] as String,
                                child: Text(s['name'] as String,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedSupplierId = val),
                    );
                  },
                  // This loading only shows up on the VERY FIRST load of the screen
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('تعذر جلب الموردين'),
                ),
              ),
              GoldIconButton(
                icon: Icons.person_add_alt_1_rounded,
                tooltip: 'مورد جديد',
                onPressed: _showCreateSupplierDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceLines(int invoiceTotal) {
    final theme = Theme.of(context);
    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'السلع المستلمة',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_invoiceItems.length} عناصر',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (_invoiceItems.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('مسح عناصر الفاتورة؟'),
                          content: const Text(
                              'هل أنت متأكد من رغبتك في حذف جميع السلع المحددة من الفاتورة؟'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('إلغاء'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('مسح الكل'),
                            ),
                          ],
                        ),
                      ).then((confirmed) {
                        if (confirmed == true && mounted) {
                          setState(() => _invoiceItems.clear());
                        }
                      });
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('مسح', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
          const GoldDivider(
              margin: EdgeInsets.symmetric(vertical: AppSpacing.sm)),

          if (_invoiceItems.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  vertical: AppSpacing.xl),
              child: Column(
                children: [
                  Icon(Icons.add_shopping_cart_outlined,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.40)),
                  AppSpacing.gapSm,
                  Text(
                    'اضغط على + بجانب المنتج لإضافته',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _invoiceItems.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) => _InvoiceLineItem(
                item: _invoiceItems[idx],
                onIncrement: () =>
                    setState(() => _invoiceItems[idx]['qty'] += 1),
                onDecrement: () => setState(() {
                  if (_invoiceItems[idx]['qty'] > 1) {
                    _invoiceItems[idx]['qty'] -= 1;
                  } else {
                    _invoiceItems.removeAt(idx);
                  }
                }),
                onEditCost: (newCost) => setState(
                    () => _invoiceItems[idx]['cost_centimes'] = newCost),
                onSetQty: (newQty) => setState(
                    () => _invoiceItems[idx]['qty'] = newQty > 0 ? newQty : 1),
              ),
            ),

          const GoldDivider(
              margin: EdgeInsets.symmetric(vertical: AppSpacing.sm)),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المجموع الإجمالي:',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              DzdPriceTag.lg(centimes: invoiceTotal, gold: true),
            ],
          ),
          AppSpacing.gapLg,

          // Action buttons
          Row(
            children: [
              Expanded(
                flex: 3,
                child: GoldButton.icon(
                  onPressed:
                      _invoiceItems.isEmpty || _isPosting ? null : _postInvoice,
                  loading: _isPosting,
                  icon: Icons.check_circle_rounded,
                  label:
                      _isPosting ? 'جاري الترحيل...' : 'استلام وترحيل للمخزون',
                ),
              ),
              if (_invoiceItems.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final auth = ref.read(authStateProvider);
                      final suppliers = ref.read(suppliersProvider).value ?? [];
                      final sup = suppliers.firstWhere(
                        (s) => s['id'] == _selectedSupplierId,
                        orElse: () => {'name': 'مورد'},
                      );
                      PdfInvoiceService.printPurchaseReceivingVoucher(
                        invoiceNo: _invoiceNoController.text.trim(),
                        supplierName: sup['name'] as String,
                        items: _invoiceItems,
                        totalCentimes: invoiceTotal,
                        receivedByName: auth?.name ?? 'مسؤول المخزن',
                      );
                    },
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('طباعة'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductSelector(AsyncValue<List<Product>> productsAsync) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isCompact = context.isCompact;

    // Card decoration shared between compact and wide paths.
    BoxDecoration cardDeco() => BoxDecoration(
          color: isDark ? const Color(0xFF1A1814) : const Color(0xFFFFFDF8),
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: isDark ? const Color(0x38D4AF37) : const Color(0x28C59B27),
          ),
        );

    // Shared header + search column children (no list yet).
    List<Widget> header() => [
          SectionHeader(
            title: 'قائمة المنتجات',
            trailing: GoldIconButton(
              icon: Icons.add_rounded,
              tooltip: 'منتج جديد',
              onPressed: _showCreateProductDialog,
              size: 32,
            ),
          ),
          AppSpacing.gapSm,
          TextField(
            controller: _productSearchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'بحث سريع (اسم، باركود)...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HeadlessBarcodeScannerButton(
                    controller: _productSearchController,
                    onScanned: (barcode) {
                      setState(() => _productSearch = barcode);
                    },
                    tooltip: 'مسح باركود المنتج بالكاميرا',
                  ),
                  if (_productSearch.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        _productSearchController.clear();
                        setState(() => _productSearch = '');
                      },
                    ),
                ],
              ),
            ),
            onChanged: (v) => setState(() => _productSearch = v),
          ),
          AppSpacing.gapSm,
        ];

    if (isCompact) {
      // Compact: lives inside SingleChildScrollView — shrinkWrap is fine.
      return DecoratedBox(
        decoration: cardDeco(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...header(),
              productsAsync.when(
                data: (products) => _productList(products, theme, shrink: true),
                loading: () =>
                    const AppLoadingView(message: 'جاري جلب المنتجات...'),
                error: (err, _) => AppErrorView(
                  message: 'تعذر تحميل المنتجات',
                  onRetry: () => ref.invalidate(liveProductsProvider),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Wide: fills the height allocated by the outer Row's crossAxisAlignment.stretch.
    return DecoratedBox(
      decoration: cardDeco(),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...header(),
            Expanded(
              child: productsAsync.when(
                data: (products) =>
                    _productList(products, theme, shrink: false),
                loading: () =>
                    const AppLoadingView(message: 'جاري جلب المنتجات...'),
                error: (err, _) => AppErrorView(
                  message: 'تعذر تحميل المنتجات',
                  onRetry: () => ref.invalidate(liveProductsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productList(List<Product> products, ThemeData theme,
      {required bool shrink}) {
    final categories = products
        .map((p) => p.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final filtered = products.where((p) {
      if (_receivingCategory != null &&
          p.category.trim() != _receivingCategory) {
        return false;
      }
      if (_productSearch.trim().isNotEmpty) {
        final q = _productSearch.trim().toLowerCase();
        final matchAr = p.nameAr.toLowerCase().contains(q);
        final matchFr = p.nameFr.toLowerCase().contains(q);
        final matchBarcode = p.barcodes.any((b) => b.contains(q));
        return matchAr || matchFr || matchBarcode;
      }
      return true;
    }).toList();

    Widget categoryBar() {
      if (categories.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('الكل', style: TextStyle(fontSize: 11)),
                selected: _receivingCategory == null,
                onSelected: (_) => setState(() => _receivingCategory = null),
                visualDensity: VisualDensity.compact,
              ),
              ...categories.map((c) => Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: ChoiceChip(
                      label: Text(c, style: const TextStyle(fontSize: 11)),
                      selected: _receivingCategory == c,
                      onSelected: (_) => setState(() => _receivingCategory =
                          _receivingCategory == c ? null : c),
                      visualDensity: VisualDensity.compact,
                    ),
                  )),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          categoryBar(),
          Padding(
            padding:
                const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.xl),
            child: AppEmptyView(
              icon: Icons.inventory_2_outlined,
              title: 'لا منتجات مطابقة',
              description: 'جرّب فئة أخرى أو أضف منتجاً جديداً للكتالوج.',
              actionLabel: 'إضافة منتج',
              onAction: _showCreateProductDialog,
            ),
          ),
        ],
      );
    }

    final listView = ListView.separated(
      shrinkWrap: shrink,
      physics: shrink
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = filtered[i];
        return ListTile(
          contentPadding:
              const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
          leading: ClipRRect(
            borderRadius: AppRadius.xsAll,
            child: p.photoUrl != null
                ? Image.network(
                    p.photoUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _productPlaceholder(theme, 40),
                  )
                : _productPlaceholder(theme, 40),
          ),
          title: Text(p.nameAr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'المخزون: ${p.availableQty} ${p.unit}  •  ${DzdFormatter.formatCentimes(p.costCentimes)}',
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'إضافة للفاتورة',
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            onPressed: () => _addItemToInvoice(p),
          ),
        );
      },
    );

    if (shrink) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          categoryBar(),
          listView,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        categoryBar(),
        Expanded(child: listView),
      ],
    );
  }

  Widget _productPlaceholder(ThemeData theme, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.xsAll,
      ),
      child: Icon(Icons.inventory_2_outlined,
          size: size * 0.50, color: theme.colorScheme.onSurfaceVariant),
    );
  }

  // ─── Catalog Tab ──────────────────────────────────────────────────────────

  Widget _buildCatalogTab() {
    final productsAsync = ref.watch(liveProductsProvider);
    final theme = Theme.of(context);

    return productsAsync.when(
      skipLoadingOnRefresh: true,
      loading: () => const AppLoadingView(message: 'جاري تحميل الكتالوج...'),
      error: (err, _) => AppErrorView(
        message: 'تعذر تحميل كتالوج المنتجات: $err',
        onRetry: () => ref.invalidate(liveProductsProvider),
      ),
      data: (products) {
        final categories = products
            .map((p) => p.category.trim())
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final effectiveCategory =
            categories.contains(_catalogCategory) ? _catalogCategory : null;

        final filtered = products.where((p) {
          if (effectiveCategory != null &&
              p.category.trim() != effectiveCategory) {
            return false;
          }
          final matchesHealth = switch (_catalogHealthFilter) {
            'low' => p.healthStatus == StockHealthStatus.lowStock ||
                p.healthStatus == StockHealthStatus.critical,
            'out' => p.healthStatus == StockHealthStatus.outOfStock,
            'overstocked' => p.healthStatus == StockHealthStatus.overstocked,
            'inactive' => !p.active,
            _ => true,
          };
          if (!matchesHealth) return false;
          if (_catalogSearch.trim().isNotEmpty) {
            final q = _catalogSearch.trim().toLowerCase();
            return p.nameAr.toLowerCase().contains(q) ||
                p.nameFr.toLowerCase().contains(q) ||
                p.category.toLowerCase().contains(q) ||
                p.barcodes.any((b) => b.contains(q));
          }
          return true;
        }).toList()
          ..sort((a, b) => a.nameAr.compareTo(b.nameAr));

        final inventoryValue = products.fold<int>(
          0,
          (sum, p) => sum + (p.availableQty * p.costCentimes),
        );
        final lowCount = products
            .where(
              (p) =>
                  p.healthStatus == StockHealthStatus.lowStock ||
                  p.healthStatus == StockHealthStatus.critical,
            )
            .length;
        final outCount = products
            .where((p) => p.healthStatus == StockHealthStatus.outOfStock)
            .length;
        final inactiveCount = products.where((p) => !p.active).length;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(liveProductsProvider);
            await ref.read(liveProductsProvider.future);
          },
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _catalogHeader(theme, products.length),
                      AppSpacing.gapMd,
                      _catalogStats(
                        theme,
                        inventoryValue,
                        lowCount,
                        outCount,
                        inactiveCount,
                      ),
                      AppSpacing.gapMd,
                      TextField(
                        controller: _catalogSearchController,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'بحث في الكتالوج (اسم، باركود، فئة)...',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HeadlessBarcodeScannerButton(
                                controller: _catalogSearchController,
                                onScanned: (code) => setState(
                                  () => _catalogSearch = code.trim(),
                                ),
                                tooltip: 'مسح باركود المنتج',
                              ),
                              if (_catalogSearch.isNotEmpty)
                                IconButton(
                                  tooltip: 'مسح البحث',
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 17,
                                  ),
                                  onPressed: () {
                                    _catalogSearchController.clear();
                                    setState(() => _catalogSearch = '');
                                  },
                                ),
                            ],
                          ),
                        ),
                        onChanged: (v) =>
                            setState(() => _catalogSearch = v.trim()),
                      ),
                      AppSpacing.gapSm,
                      _catalogFilters(theme, categories, effectiveCategory),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: products.isEmpty
                      ? AppEmptyView(
                          icon: Icons.inventory_2_outlined,
                          title: 'الكتالوج فارغ',
                          description: 'أضف أول منتج لبدء إدارة المخزون.',
                          actionLabel: 'إضافة منتج الآن',
                          onAction: _showCreateProductDialog,
                        )
                      : AppEmptyView(
                          icon: Icons.search_off_rounded,
                          title: 'لا نتائج مطابقة',
                          description:
                              'جرّب تغيير كلمة البحث أو الفلاتر المحددة.',
                          actionLabel: 'مسح الفلاتر',
                          onAction: () => setState(() {
                            _catalogSearch = '';
                            _catalogSearchController.clear();
                            _catalogHealthFilter = 'all';
                            _catalogCategory = null;
                          }),
                        ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        if (i.isOdd) {
                          return const Divider(height: 1);
                        }
                        final product = filtered[i ~/ 2];
                        return _CatalogProductRow(
                          product: product,
                          onEdit: () => _showEditProductDialog(product),
                          onAdjustStock: () => _showAdjustmentFor(product),
                        );
                      },
                      childCount:
                          filtered.isEmpty ? 0 : filtered.length * 2 - 1,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _catalogHeader(ThemeData theme, int totalProducts) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFD4AF37).withValues(alpha: 0.12),
            theme.colorScheme.surfaceContainerLowest,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: const BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: AppRadius.mdAll,
              boxShadow: [AppShadows.goldGlowSm],
            ),
            child: const Icon(
              Icons.grid_view_rounded,
              size: 23,
              color: Color(0xFF1A1400),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'كتالوج المنتجات والمخزون',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$totalProducts منتج • إدارة الأسعار ومستويات المخزون والتسويات السريعة.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GoldButton.icon(
            icon: Icons.add_rounded,
            label: 'منتج جديد',
            onPressed: _showCreateProductDialog,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _catalogStats(
    ThemeData theme,
    int inventoryValue,
    int lowCount,
    int outCount,
    int inactiveCount,
  ) {
    final stats = [
      _CatalogStat(
        label: 'قيمة المخزون',
        value: DzdFormatter.formatCentimes(inventoryValue),
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFFD4AF37),
      ),
      _CatalogStat(
        label: 'منخفض / حرج',
        value: '$lowCount',
        icon: Icons.trending_down_rounded,
        color: const Color(0xFFF2994A),
      ),
      _CatalogStat(
        label: 'نفد من المخزون',
        value: '$outCount',
        icon: Icons.remove_shopping_cart_outlined,
        color: Colors.red,
      ),
      _CatalogStat(
        label: 'منتجات معطلة',
        value: '$inactiveCount',
        icon: Icons.visibility_off_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        const spacing = AppSpacing.sm;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              stats.map((stat) => SizedBox(width: width, child: stat)).toList(),
        );
      },
    );
  }

  Widget _catalogFilters(
    ThemeData theme,
    List<String> categories,
    String? effectiveCategory,
  ) {
    final filters = [
      ('all', 'الكل', Icons.apps_rounded),
      ('low', 'منخفض / حرج', Icons.trending_down_rounded),
      ('out', 'نفد', Icons.remove_shopping_cart_outlined),
      ('overstocked', 'فائض', Icons.trending_up_rounded),
      ('inactive', 'معطل', Icons.visibility_off_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters.map((filter) {
              final selected = _catalogHealthFilter == filter.$1;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  avatar: Icon(
                    filter.$3,
                    size: 14,
                    color: selected
                        ? const Color(0xFF1A1400)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(filter.$2),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? const Color(0xFF1A1400) : null,
                  ),
                  selectedColor: const Color(0xFFD4AF37),
                  onSelected: (_) =>
                      setState(() => _catalogHealthFilter = filter.$1),
                ),
              );
            }).toList(),
          ),
        ),
        if (categories.isNotEmpty) ...[
          AppSpacing.gapXs,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: ChoiceChip(
                    selected: effectiveCategory == null,
                    label: const Text('كل الفئات'),
                    labelStyle: const TextStyle(fontSize: 10.5),
                    onSelected: (_) => setState(() => _catalogCategory = null),
                  ),
                ),
                ...categories.map(
                  (category) => Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: AppSpacing.xs,
                    ),
                    child: ChoiceChip(
                      selected: effectiveCategory == category,
                      label: Text(category),
                      labelStyle: const TextStyle(fontSize: 10.5),
                      onSelected: (_) => setState(
                        () => _catalogCategory =
                            effectiveCategory == category ? null : category,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showAdjustmentFor(Product product) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StockAdjustmentDialog(initialProduct: product),
    );
    if (!mounted) return;
    ref.invalidate(stockAdjustmentHistoryProvider);
    ref.invalidate(liveProductsProvider);
    ref.invalidate(lowStockProductsProvider);
  }

  Future<void> _showEditProductDialog(Product product) async {
    final updated = await showDialog<Product>(
      context: context,
      builder: (ctx) => CreateProductDialog(existing: product),
    );
    if (updated != null && mounted) {
      ref.invalidate(liveProductsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم تحديث "${updated.nameAr}" بنجاح'),
        backgroundColor: context.appColors.success,
      ));
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

/// Single invoice line with inline qty stepper, quick keypad, and editable cost.
class _InvoiceLineItem extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<int> onEditCost;
  final ValueChanged<int>? onSetQty;

  const _InvoiceLineItem({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEditCost,
    this.onSetQty,
  });

  @override
  State<_InvoiceLineItem> createState() => _InvoiceLineItemState();
}

class _InvoiceLineItemState extends State<_InvoiceLineItem> {
  bool _editingCost = false;
  late TextEditingController _costCtrl;

  @override
  void initState() {
    super.initState();
    _costCtrl = TextEditingController(
        text: ((widget.item['cost_centimes'] as int) / 100).toStringAsFixed(0));
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    super.dispose();
  }

  void _showQuickKeypad(BuildContext context) {
    if (widget.onSetQty == null) return;
    int currentQty = (widget.item['qty'] as num).toInt();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'تعديل كمية الاستلام: ${widget.item['product_name']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 24),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.smAll,
                      border: Border.all(color: const Color(0xFFD4AF37)),
                    ),
                    child: Text(
                      '$currentQty',
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD4AF37)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final delta in [1, 5, 10, 20, 50, 100])
                        ActionChip(
                          label: Text('+$delta'),
                          onPressed: () {
                            setModalState(() => currentQty += delta);
                            widget.onSetQty!(currentQty);
                          },
                        ),
                      ActionChip(
                        label: const Text('إعادة للواحد (1)'),
                        onPressed: () {
                          setModalState(() => currentQty = 1);
                          widget.onSetQty!(1);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  GoldButton(
                    label: 'تأكيد الكمية ($currentQty)',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cost = widget.item['cost_centimes'] as int;
    final qty = widget.item['qty'] as int;
    final lineTotal = cost * qty;
    final selling = widget.item['selling_price'] as int?;
    final unit = widget.item['unit']?.toString();
    final margin =
        (selling != null && cost > 0) ? ((selling - cost) / cost) * 100 : 0.0;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          // Product name + unit
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.item['product_name'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unit != null && unit.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '($unit)',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_editingCost)
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _costCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'التكلفة (دج)',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        suffixText: 'دج',
                      ),
                      onSubmitted: (v) {
                        final dzd = double.tryParse(v) ?? 0;
                        widget.onEditCost((dzd * 100).round());
                        setState(() => _editingCost = false);
                      },
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => setState(() => _editingCost = true),
                    child: Row(
                      children: [
                        Text(
                          DzdFormatter.formatCentimes(cost),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.edit_outlined,
                            size: 11,
                            color: theme.colorScheme.onSurfaceVariant),
                        if (selling != null && selling > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: AppRadius.xsAll,
                            ),
                            child: Text(
                              'هامش +${margin.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 2),
                Builder(
                  builder: (_) {
                    final oldOnHand = widget.item['old_on_hand'] as int? ?? 0;
                    final oldAvgCost =
                        widget.item['old_weighted_cost'] as int? ?? cost;
                    final totalQty = oldOnHand + qty;
                    final newAvg = totalQty > 0
                        ? (((oldOnHand * oldAvgCost) + (qty * cost)) / totalQty)
                            .round()
                        : cost;
                    return Text(
                      'المتوسط المرجح بالدفتر: ${DzdFormatter.formatCentimes(newAvg)}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFD4AF37),
                          fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ],
            ),
          ),

          // Qty stepper with min 48x48 tap targets (Tablet Operational Hub requirement)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 22),
                onPressed: widget.onDecrement,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                tooltip: 'إنقاص الكمية',
              ),
              InkWell(
                onTap: widget.onSetQty != null
                    ? () => _showQuickKeypad(context)
                    : null,
                borderRadius: AppRadius.xsAll,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 36),
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.xsAll,
                    border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${widget.item['qty']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 22),
                onPressed: widget.onIncrement,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                tooltip: 'زيادة الكمية',
              ),
            ],
          ),

          // Line total
          SizedBox(
            width: 90,
            child: Text(
              DzdFormatter.formatCentimes(lineTotal),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Catalog tab product row — shows full pricing, stock, and an edit button.
class _CatalogProductRow extends StatelessWidget {
  final Product product;
  final VoidCallback? onEdit;
  final VoidCallback? onAdjustStock;

  const _CatalogProductRow({
    required this.product,
    this.onEdit,
    this.onAdjustStock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final wholesalePrice = product.getPriceForQuantity(PriceTier.wholesale, 1);
    final retailPrice = product.getPriceForQuantity(PriceTier.retail, 1);
    final bulkPrice =
        product.getPriceForQuantity(PriceTier.bulk, product.packSize * 5);
    final isInactive = !product.active;

    return Opacity(
      opacity: isInactive ? 0.55 : 1.0,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
            vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Compact: stacked card layout. Wide: single-row layout.
            final isNarrow = constraints.maxWidth < 480;
            return isNarrow
                ? _buildNarrow(context, theme, cs, retailPrice, wholesalePrice,
                    bulkPrice, isInactive)
                : _buildWide(context, theme, cs, retailPrice, wholesalePrice,
                    bulkPrice, isInactive);
          },
        ),
      ),
    );
  }

  // ── Narrow (phone) layout ─────────────────────────────────────────────────
  Widget _buildNarrow(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    int retailPrice,
    int wholesalePrice,
    int bulkPrice,
    bool isInactive,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail
        ClipRRect(
          borderRadius: AppRadius.xsAll,
          child: product.photoUrl != null
              ? Image.network(
                  product.photoUrl!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(theme, 44),
                )
              : _placeholder(theme, 44),
        ),
        const SizedBox(width: AppSpacing.sm),

        // All text info, expands to fill remaining width
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name row + inactive badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.nameAr,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _healthBadge(theme),
                  if (isInactive) _inactiveBadge(cs),
                  _menuButton(compact: true),
                ],
              ),
              if (product.nameFr.isNotEmpty)
                Text(product.nameFr,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis),

              // Stock badge + cost on same line
              Row(
                children: [
                  StockBadge(
                    availableQty: product.availableQty,
                    unitName: product.unit,
                    minAlert: product.reorderPoint,
                    compact: true,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'تكلفة: ${DzdFormatter.formatCentimes(product.costCentimes)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),

              // Prices on one line, wrapping
              Wrap(
                spacing: AppSpacing.md,
                children: [
                  _priceChip(theme, 'جملة', wholesalePrice, bold: true),
                  _priceChip(theme, 'تجزئة', retailPrice),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Wide (tablet/desktop) layout ──────────────────────────────────────────
  Widget _buildWide(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    int retailPrice,
    int wholesalePrice,
    int bulkPrice,
    bool isInactive,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Thumbnail
        ClipRRect(
          borderRadius: AppRadius.xsAll,
          child: product.photoUrl != null
              ? Image.network(
                  product.photoUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(theme, 48),
                )
              : _placeholder(theme, 48),
        ),
        const SizedBox(width: AppSpacing.md),

        // Name + fr name + category/barcode — takes remaining space
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.nameAr,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _healthBadge(theme),
                  if (isInactive) _inactiveBadge(cs),
                ],
              ),
              if (product.nameFr.isNotEmpty)
                Text(product.nameFr,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  Text(product.category, style: theme.textTheme.bodySmall),
                  if (product.packSize > 1)
                    Text(
                      'حزمة: ${product.packSize} ${product.unit}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF9A7319),
                          fontWeight: FontWeight.w600),
                    ),
                  if (product.barcodes.isNotEmpty)
                    Text(
                      product.barcodes.first,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.primary),
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(width: AppSpacing.md),

        // Stock + cost — fixed width
        SizedBox(
          width: 125,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StockBadge(
                availableQty: product.availableQty,
                unitName: product.unit,
                minAlert: product.reorderPoint,
                compact: true,
              ),
              const SizedBox(height: 4),
              Text(
                'تكلفة: ${DzdFormatter.formatCentimes(product.costCentimes)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
              if (product.reorderPoint > 0)
                Text(
                  'ROP: ${product.reorderPoint}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                  textAlign: TextAlign.end,
                ),
            ],
          ),
        ),

        const SizedBox(width: AppSpacing.sm),

        // Prices — fixed width
        SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _priceRow(theme, 'تجزئة', retailPrice),
              const SizedBox(height: 2),
              _priceRow(theme, 'جملة', wholesalePrice, bold: true),
              const SizedBox(height: 2),
              _priceRow(theme, 'Bulk', bulkPrice,
                  color: const Color(0xFF7B6B1A)),
            ],
          ),
        ),

        const SizedBox(width: AppSpacing.xs),

        // Quick stock actions
        IconButton(
          tooltip: 'تسوية مخزون',
          icon: const Icon(Icons.tune_rounded, size: 18),
          onPressed: onAdjustStock,
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF2F80ED),
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
          ),
        ),
        IconButton(
          tooltip: 'تعديل المنتج',
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: onEdit,
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFFD4AF37),
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
          ),
        ),
      ],
    );
  }

  Widget _menuButton({required bool compact}) {
    return PopupMenuButton<String>(
      tooltip: 'خيارات المنتج',
      padding: EdgeInsets.zero,
      icon: Icon(
        compact ? Icons.more_horiz_rounded : Icons.more_vert_rounded,
        size: 18,
        color: const Color(0xFFD4AF37),
      ),
      onSelected: (value) {
        if (value == 'edit') onEdit?.call();
        if (value == 'adjust') onAdjustStock?.call();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.edit_outlined, size: 18),
            title: Text('تعديل المنتج'),
          ),
        ),
        if (onAdjustStock != null)
          const PopupMenuItem(
            value: 'adjust',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.tune_rounded, size: 18),
              title: Text('تسوية المخزون'),
            ),
          ),
      ],
    );
  }

  Widget _healthBadge(ThemeData theme) {
    final status = product.healthStatus;
    final (color, label) = switch (status) {
      StockHealthStatus.outOfStock => (Colors.red, 'نفد'),
      StockHealthStatus.critical => (const Color(0xFFEB5757), 'حرج'),
      StockHealthStatus.lowStock => (const Color(0xFFF2994A), 'منخفض'),
      StockHealthStatus.overstocked => (const Color(0xFF2F80ED), 'فائض'),
      StockHealthStatus.normal => (const Color(0xFF27AE60), 'جيد'),
    };
    return Container(
      margin: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _inactiveBadge(ColorScheme cs) => Container(
        margin: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: AppRadius.pillAll,
        ),
        child: Text(
          'معطل',
          style: TextStyle(
              fontSize: 10,
              color: cs.onErrorContainer,
              fontWeight: FontWeight.bold),
        ),
      );

  // Compact price chip for narrow layout
  Widget _priceChip(ThemeData theme, String label, int centimes,
      {bool bold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        DzdPriceTag(
          centimes: centimes,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
            color: bold ? const Color(0xFFD4AF37) : null,
          ),
        ),
      ],
    );
  }

  Widget _priceRow(ThemeData theme, String label, int centimes,
      {bool bold = false, Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: theme.textTheme.bodySmall),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: DzdPriceTag(
              centimes: centimes,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontSize: bold ? 13 : 12,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder(ThemeData theme, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.xsAll,
      ),
      child: Icon(Icons.inventory_2_outlined,
          size: size * 0.5, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _CatalogStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _CatalogStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? const Color(0xFFB8860B) : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected
            ? const Color(0xFFD4AF37).withValues(alpha: 0.13)
            : Colors.transparent,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: BorderDirectional(
                start: BorderSide(
                  color:
                      selected ? const Color(0xFFD4AF37) : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: selected
                          ? const Color(0xFFB8860B)
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFD4AF37)
                          : const Color(0xFFF2994A),
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color:
                            selected ? const Color(0xFF1A1400) : Colors.white,
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
