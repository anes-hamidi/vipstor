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
import 'services/pdf_invoice_service.dart';

final suppliersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return repo.getSuppliers();
});

class PurchaseReceivingScreen extends ConsumerStatefulWidget {
  const PurchaseReceivingScreen({super.key});

  @override
  ConsumerState<PurchaseReceivingScreen> createState() => _PurchaseReceivingScreenState();
}

class _PurchaseReceivingScreenState extends ConsumerState<PurchaseReceivingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Receiving Invoice Form
  final _invoiceNoController = TextEditingController(text: 'FAC-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 10000}');
  String? _selectedSupplierId;
  bool _isPosting = false;
  final List<Map<String, dynamic>> _invoiceItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _invoiceNoController.dispose();
    super.dispose();
  }

  Future<void> _showCreateSupplierDialog() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const CreateSupplierDialog(),
    );

    if (created != null && mounted) {
      ref.invalidate(suppliersProvider);
      setState(() {
        _selectedSupplierId = created['id'] as String;
      });
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

  void _addItemToInvoice(Product product) {
    final existingIndex = _invoiceItems.indexWhere((it) => it['product_id'] == product.id);
    if (existingIndex >= 0) {
      setState(() {
        _invoiceItems[existingIndex]['qty'] += 1;
      });
    } else {
      setState(() {
        _invoiceItems.add({
          'product_id': product.id,
          'product_name': product.nameAr,
          'unit': product.unit,
          'cost_centimes': product.costCentimes,
          'qty': 1,
        });
      });
    }
  }

  Future<void> _postInvoice() async {
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى اختيار المورد أولاً!'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }

    if (_invoiceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('الفاتورة فارغة! أضف منتجات للاستلام.'),
          backgroundColor: context.appColors.warning,
        ),
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      final repo = ref.read(purchaseRepositoryProvider);
      final authUser = ref.read(authStateProvider);
      final userId = authUser?.id ?? '11111111-1111-1111-1111-111111111111';
      final formattedItems = _invoiceItems.map((it) {
            final cost = (it['cost_centimes'] as num).toInt();
            return {
              'product_id': it['product_id'] as String,
              'quantity': (it['qty'] as num).toInt(),
              'unit_cost': cost,
              'selling_price': cost + 1000,
            };
          }).toList();

      final purchaseId = await repo.createDraftPurchase(
        supplierId: _selectedSupplierId!,
        invoiceNo: _invoiceNoController.text.trim(),
        invoiceDate: DateTime.now(),
        createdBy: userId,
        items: formattedItems,
      );

      await repo.postPurchase(
        purchaseId: purchaseId,
        userId: userId,
      );

      ref.invalidate(liveProductsProvider);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم استلام الفاتورة وترحيل السلع لدفتر المخزون بنجاح!'),
          backgroundColor: context.appColors.success,
        ),
      );

      setState(() {
        _invoiceItems.clear();
        _invoiceNoController.text = 'FAC-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 10000}';
      });
    } catch (e) {
      debugPrint('Error posting purchase invoice: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل ترحيل الفاتورة: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.inventory_rounded),
            const SizedBox(width: AppSpacing.sm),
            Text('إدارة المخزون والمشتريات - ${authUser?.name ?? "المسؤول"}'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(liveProductsProvider);
              ref.invalidate(suppliersProvider);
            },
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authStateProvider.notifier).state = null,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'طلبيات الزبائن وتعيين السائقين (Online Orders)'),
            Tab(icon: Icon(Icons.receipt_long), text: 'استلام فواتير المشتريات (Réception)'),
            Tab(icon: Icon(Icons.grid_view), text: 'كتالوج المنتجات والمخزون الحقيقي'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const OnlineOrdersPipelineView(),
          _buildReceivingTab(),
          _buildProductsCatalogTab(),
        ],
      ),
    );
  }

  Widget _buildReceivingTab() {
    final suppliersAsync = ref.watch(suppliersProvider);
    final productsAsync = ref.watch(liveProductsProvider);
    final theme = Theme.of(context);
    final isCompact = context.isCompact;

    final invoiceTotalCentimes = _invoiceItems.fold<int>(
      0,
      (sum, item) => sum + (item['cost_centimes'] as int) * (item['qty'] as int),
    );

    return ContentConstrainedBox.dashboard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: isCompact
          ? SingleChildScrollView(
              child: Column(
                children: [
                  _buildInvoiceFormHeader(suppliersAsync, theme),
                  AppSpacing.gapLg,
                  _buildInvoiceItemsCard(theme, invoiceTotalCentimes),
                  AppSpacing.gapLg,
                  _buildAvailableProductsSelector(productsAsync, isScrollable: false),
                ],
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildInvoiceFormHeader(suppliersAsync, theme),
                        AppSpacing.gapLg,
                        _buildInvoiceItemsCard(theme, invoiceTotalCentimes),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: _buildAvailableProductsSelector(productsAsync, isScrollable: false),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInvoiceFormHeader(AsyncValue<List<Map<String, dynamic>>> suppliersAsync, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'بيانات فاتورة الشراء الموردة',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            AppSpacing.gapMd,
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
                  child: TextField(
                    controller: _invoiceNoController,
                    decoration: const InputDecoration(
                      labelText: 'رقم الفاتورة (N° Facture) *',
                      prefixIcon: Icon(Icons.receipt_outlined),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
                  child: suppliersAsync.when(
                    data: (suppliers) {
                      return DropdownButtonFormField<String>(
                        initialValue: _selectedSupplierId,
                        decoration: const InputDecoration(
                          labelText: 'المورد (Fournisseur) *',
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                        items: suppliers.map((s) {
                          return DropdownMenuItem<String>(
                            value: s['id'] as String,
                            child: Text(s['name'] as String, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedSupplierId = val),
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('تعذر جلب الموردين'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showCreateSupplierDialog,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('مورد جديد'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceItemsCard(ThemeData theme, int invoiceTotalCentimes) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'السلع والكميات المستلمة:',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_invoiceItems.length} عناصر',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const Divider(),
            if (_invoiceItems.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
                child: Center(
                  child: Text(
                    'اختر السلع من القائمة بالجانب لإدراجها في الفاتورة',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _invoiceItems.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final it = _invoiceItems[index];
                  final lineTotal = (it['cost_centimes'] as int) * (it['qty'] as int);

                  return Padding(
                    padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it['product_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                '${DzdFormatter.formatCentimes(it['cost_centimes'] as int)} / ${it['unit']}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: () {
                                setState(() {
                                  if (it['qty'] > 1) {
                                    it['qty'] -= 1;
                                  } else {
                                    _invoiceItems.removeAt(index);
                                  }
                                });
                              },
                            ),
                            Text('${it['qty']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              onPressed: () {
                                setState(() {
                                  it['qty'] += 1;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(width: AppSpacing.md),
                        SizedBox(
                          width: 100,
                          child: DzdPriceTag(
                            centimes: lineTotal,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const Divider(),
            AppSpacing.gapSm,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('المجموع الإجمالي للفاتورة:', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                DzdPriceTag(
                  centimes: invoiceTotalCentimes,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            AppSpacing.gapLg,
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: _invoiceItems.isEmpty || _isPosting ? null : _postInvoice,
                    icon: _isPosting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                        : const Icon(Icons.check_circle),
                    label: Text(_isPosting ? 'جاري الترحيل لدفتر المخزون...' : 'ترحيل واستلام الفاتورة في المخزون'),
                  ),
                ),
                if (_invoiceItems.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
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
                          totalCentimes: invoiceTotalCentimes,
                          receivedByName: auth?.name ?? 'مسؤول المخزن',
                        );
                      },
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('طباعة الوصل'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableProductsSelector(AsyncValue<List<Product>> productsAsync, {bool isScrollable = false}) {
    final theme = Theme.of(context);

    final listContent = productsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return AppEmptyView(
            icon: Icons.inventory_2_outlined,
            title: 'لا توجد منتجات مسجلة',
            description: 'ابدأ بإضافة أول منتج إلى كتالوج المتجر.',
            actionLabel: 'إضافة منتج جديد',
            onAction: _showCreateProductDialog,
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final p = products[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.category, color: theme.colorScheme.onPrimaryContainer, size: 20),
              ),
              title: Text(p.nameAr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(
                'المخزون الحالي: ${p.availableQty} ${p.unit}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: IconButton(
                tooltip: 'إدراج في الفاتورة',
                icon: const Icon(Icons.add_shopping_cart, size: 20),
                onPressed: () => _addItemToInvoice(p),
              ),
            );
          },
        );
      },
      loading: () => const AppLoadingView(message: 'جاري جلب المنتجات...'),
      error: (err, _) => AppErrorView(
        message: 'تعذر تحميل المنتجات',
        onRetry: () => ref.invalidate(liveProductsProvider),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'قائمة السلع والمنتجات',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showCreateProductDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('منتج جديد'),
                ),
              ],
            ),
            const Divider(),
            listContent,
          ],
        ),
      ),
    );
  }

  Widget _buildProductsCatalogTab() {
    final productsAsync = ref.watch(liveProductsProvider);
    final theme = Theme.of(context);

    return ContentConstrainedBox.dashboard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'سجل كتالوج المنتجات والمخزون المباشر',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                onPressed: _showCreateProductDialog,
                icon: const Icon(Icons.add),
                label: const Text('إضافة منتج جديد للمتجر'),
              ),
            ],
          ),
          AppSpacing.gapMd,
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return AppEmptyView(
                    icon: Icons.inventory_2_outlined,
                    title: 'لا توجد منتجات مسجلة في المتجر بعد',
                    description: 'انقر على الزر أعلاه لإضافة منتج وتعيين أسعاره ومخزونه الافتتاحي.',
                    actionLabel: 'إضافة منتج الآن',
                    onAction: _showCreateProductDialog,
                  );
                }

                return Card(
                  child: ListView.separated(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final wholesalePrice = product.getPriceForQuantity(PriceTier.wholesale, 1);
                      final retailPrice = product.getPriceForQuantity(PriceTier.retail, 1);

                      return Padding(
                        padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Icon(Icons.inventory_2, color: theme.colorScheme.onPrimaryContainer, size: 22),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.nameAr,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  if (product.nameFr.isNotEmpty)
                                    Text(
                                      product.nameFr,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: AppSpacing.sm,
                                    children: [
                                      Text(
                                        'الفئة: ${product.category}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      if (product.barcodes.isNotEmpty)
                                        Text(
                                          'الباركود: ${product.barcodes.first}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            StockBadge(availableQty: product.availableQty, unitName: product.unit),
                            const SizedBox(width: AppSpacing.lg),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Text('الجملة: ', style: theme.textTheme.bodySmall),
                                    DzdPriceTag(centimes: wholesalePrice, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Text('التجزئة: ', style: theme.textTheme.bodySmall),
                                    DzdPriceTag(centimes: retailPrice, style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const AppLoadingView(message: 'جاري تحميل سجل الكتالوج...'),
              error: (err, _) => AppErrorView(
                message: 'تعذر الاتصال بالخادم لجلب المنتجات',
                onRetry: () => ref.invalidate(liveProductsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
