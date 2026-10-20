import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'widgets/create_supplier_dialog.dart';
import 'widgets/create_product_dialog.dart';
import 'widgets/online_orders_pipeline_view.dart';
import 'widgets/purchases_history_view.dart';
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
  // Product search inside catalog tab
  String _catalogSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    HeadlessBarcodeScannerService.instance.stopScanning();
    _productSearchController.dispose();
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
    if (updated == true && mounted) {
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
          onPressed: () => _tabController.animateTo(2),
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0E0C0A) : const Color(0xFFF8F5EE),
      appBar: _buildAppBar(authUser, theme, isDark),
      body: TabBarView(
        controller: _tabController,
        children: [
          ManagerCommandCenterView(
            onNavigateTab: (targetIndex) => _tabController.animateTo(targetIndex),
          ),
          const OnlineOrdersPipelineView(),
          _buildReceivingTab(),
          PurchasesHistoryView(
            onNavigateToReceiving: () => _tabController.animateTo(2),
          ),
          _buildCatalogTab(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      dynamic authUser, ThemeData theme, bool isDark) {
    return AppBar(
      backgroundColor:
          isDark ? const Color(0xFF141210) : const Color(0xFFFBF8F0),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
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
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.storefront_rounded,
                      size: 18, color: Color(0xFF1A1400)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إدارة المخزون والمشتريات',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (authUser?.name != null)
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              authUser!.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_outlined,
                            size: 12,
                            color: theme.colorScheme.primary.withValues(alpha: 0.7),
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
        IconButton(
          tooltip: 'تعديل الملف الشخصي',
          icon: const Icon(Icons.manage_accounts_outlined),
          onPressed: _openEditProfile,
        ),
        IconButton(
          tooltip: 'تسوية وتعديل المخزون',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => const StockAdjustmentDialog(),
            );
          },
        ),
        IconButton(
          tooltip: 'المخزون المنخفض وإعادة التزويد',
          icon: const Icon(Icons.notification_important_outlined),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LowStockReplenishmentDashboard(),
              ),
            );
          },
        ),
        IconButton(
          tooltip: 'الجرد الدوري والمطابقة الحية',
          icon: const Icon(Icons.fact_check_outlined),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CycleCountAuditSheet(),
              ),
            );
          },
        ),
        IconButton(
          tooltip: 'نقل مخزون داخلي',
          icon: const Icon(Icons.swap_horiz_rounded),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => const StockTransferDialog(),
            );
          },
        ),
        IconButton(
          tooltip: 'تحديث البيانات',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () {
            ref.invalidate(liveProductsProvider);
            ref.invalidate(suppliersProvider);
            ref.invalidate(purchasesListProvider);
            ref.invalidate(managerOnlineOrdersProvider);
          },
        ),
        IconButton(
          tooltip: 'تسجيل الخروج',
          icon: const Icon(Icons.logout_rounded),
          onPressed: () => ref.read(authStateProvider.notifier).state = null,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight - 8),
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
            tabs: [
              const Tab(
                  icon: Icon(Icons.dashboard_rounded, size: 18),
                  text: 'لوحة القيادة'),
              Tab(
                  icon: Builder(builder: (context) {
                    final unverifiedCount = ref.watch(unverifiedOrdersCountProvider);
                    return Badge(
                      isLabelVisible: unverifiedCount > 0,
                      label: Text(
                        '$unverifiedCount',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFFD4AF37),
                      textColor: const Color(0xFF1A1400),
                      child: const Icon(Icons.shopping_bag_outlined, size: 18),
                    );
                  }),
                  text: 'طلبيات الزبائن'),
              const Tab(
                  icon: Icon(Icons.add_shopping_cart_rounded, size: 18),
                  text: 'استلام الفواتير'),
              const Tab(
                  icon: Icon(Icons.receipt_long_outlined, size: 18),
                  text: 'سجل المشتريات'),
              const Tab(
                  icon: Icon(Icons.grid_view_rounded, size: 18),
                  text: 'كتالوج المنتجات'),
            ],
          ),
        ),
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
      final hasSelectedId = suppliers.any((s) => s['id'] == _selectedSupplierId);
      
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
        onChanged: (val) => setState(() => _selectedSupplierId = val),
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
                      onSelected: (_) => setState(() =>
                          _receivingCategory = _receivingCategory == c ? null : c),
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
    final isDark = theme.brightness == Brightness.dark;

    // TabBarView provides bounded height, so Column + Expanded fits cleanly.
    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row ─────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'كتالوج المنتجات والمخزون الفعلي',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              GoldButton.icon(
                icon: Icons.add_rounded,
                label: 'منتج جديد',
                onPressed: _showCreateProductDialog,
                compact: true,
              ),
            ],
          ),
          AppSpacing.gapMd,

          // ── Search bar ──────────────────────────────────────
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'بحث في الكتالوج (اسم، باركود، فئة)...',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
            ),
            onChanged: (v) => setState(() => _catalogSearch = v),
          ),
          AppSpacing.gapMd,

          // ── List ───────────────────────────────────────────
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final filtered = _catalogSearch.isEmpty
                    ? products
                    : products
                        .where((p) =>
                            p.nameAr.contains(_catalogSearch) ||
                            p.nameFr
                                .toLowerCase()
                                .contains(_catalogSearch.toLowerCase()) ||
                            p.category.contains(_catalogSearch) ||
                            p.barcodes.any((b) => b.contains(_catalogSearch)))
                        .toList();

                if (products.isEmpty) {
                  return AppEmptyView(
                    icon: Icons.inventory_2_outlined,
                    title: 'الكتالوج فارغ',
                    description: 'أضف أول منتج لبدء إدارة المخزون.',
                    actionLabel: 'إضافة منتج الآن',
                    onAction: _showCreateProductDialog,
                  );
                }

                if (filtered.isEmpty) {
                  return AppEmptyView(
                    icon: Icons.search_off_rounded,
                    title: 'لا نتائج مطابقة',
                    description: 'جرّب كلمة بحث أخرى.',
                    actionLabel: 'مسح البحث',
                    onAction: () => setState(() => _catalogSearch = ''),
                  );
                }

                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A1814)
                        : const Color(0xFFFFFDF8),
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(
                      color: isDark
                          ? const Color(0x38D4AF37)
                          : const Color(0x28C59B27),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.lgAll,
                    child: ListView.separated(
                      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) => _CatalogProductRow(
                        product: filtered[i],
                        onEdit: () => _showEditProductDialog(filtered[i]),
                      ),
                    ),
                  ),
                );
              },
              loading: () =>
                  const AppLoadingView(message: 'جاري تحميل الكتالوج...'),
              error: (err, _) => AppErrorView(
                message: 'تعذر الاتصال بالخادم',
                onRetry: () => ref.invalidate(liveProductsProvider),
              ),
            ),
          ),
        ],
      ),
    );
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

/// Single invoice line with inline qty stepper and editable cost.
class _InvoiceLineItem extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<int> onEditCost;

  const _InvoiceLineItem({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEditCost,
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
              ],
            ),
          ),

          // Qty stepper
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: widget.onDecrement,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              Text(
                '${widget.item['qty']}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: widget.onIncrement,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
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

  const _CatalogProductRow({required this.product, this.onEdit});

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
                  if (isInactive) _inactiveBadge(cs),
                  // Edit button inline on narrow
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      tooltip: 'تعديل',
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: onEdit,
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        foregroundColor: const Color(0xFFD4AF37),
                        minimumSize: const Size(32, 32),
                      ),
                    ),
                  ),
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

        // Edit button
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
