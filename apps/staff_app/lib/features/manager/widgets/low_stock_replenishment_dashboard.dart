import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../../common/widgets/headless_barcode_scanner_button.dart';

/// Low-stock intelligence and replenishment workspace.
///
/// Managers can filter urgent items, adjust the replenishment quantity per
/// product, select groups, and generate a draft purchase order that keeps the
/// edited quantities.
class LowStockReplenishmentDashboard extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToReceiving;
  final VoidCallback? onOpenPurchaseOrders;

  const LowStockReplenishmentDashboard({
    super.key,
    this.onNavigateToReceiving,
    this.onOpenPurchaseOrders,
  });

  @override
  ConsumerState<LowStockReplenishmentDashboard> createState() =>
      _LowStockReplenishmentDashboardState();
}

class _LowStockReplenishmentDashboardState
    extends ConsumerState<LowStockReplenishmentDashboard> {
  final _searchController = TextEditingController();
  String _search = '';
  final Set<String> _selectedProductIds = {};
  final Map<String, int> _quantities = {};
  bool _isGeneratingPO = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _qtyFor(ProductEntity product) =>
      _quantities[product.id] ?? product.suggestedReplenishmentQty;

  void _setQty(ProductEntity product, int value) {
    final minimum = product.isOutOfStock ? 1 : 0;
    final next = value.clamp(
        minimum, product.maxCapacity > 0 ? product.maxCapacity * 2 : 9999);
    setState(() {
      _quantities[product.id] = next;
      if (next > 0) {
        _selectedProductIds.add(product.id);
      }
    });
  }

  void _toggleSelection(ProductEntity product, bool selected) {
    setState(() {
      if (selected) {
        _selectedProductIds.add(product.id);
        _quantities.putIfAbsent(
          product.id,
          () => product.suggestedReplenishmentQty,
        );
      } else {
        _selectedProductIds.remove(product.id);
      }
    });
  }

  Future<void> _promptQuantity(ProductEntity product) async {
    final controller = TextEditingController(text: '${_qtyFor(product)}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          product.nameAr,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'كمية إعادة التزويد',
            helperText:
                'المقترح آلياً: ${product.suggestedReplenishmentQty} ${product.unit}',
            suffixText: product.unit,
          ),
          onSubmitted: (value) =>
              Navigator.of(ctx).pop(int.tryParse(value) ?? _qtyFor(product)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              int.tryParse(controller.text) ?? _qtyFor(product),
            ),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && mounted) {
      _setQty(product, result);
      if (result > 0) {
        setState(() => _selectedProductIds.add(product.id));
      }
    }
  }

  Future<void> _generateDraftPO(List<ProductEntity> visibleProducts) async {
    final suppliers = await ref.read(suppliersProvider.future);
    if (!mounted) return;
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إضافة مورد أولاً قبل إنشاء أمر الشراء'),
        ),
      );
      return;
    }

    final targetProducts = (_selectedProductIds.isEmpty
            ? visibleProducts
            : visibleProducts
                .where((p) => _selectedProductIds.contains(p.id))
                .toList())
        .where((p) => _qtyFor(p) > 0)
        .toList();
    if (targetProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أصناف محددة لإنشاء أمر الشراء.')),
      );
      return;
    }

    var selectedSupplierId = suppliers.first['id'] as String;
    var selectedSupplierName = suppliers.first['name'] as String;
    final estimatedTotal = targetProducts.fold<int>(
      0,
      (sum, p) => sum + (_qtyFor(p) * p.costCentimes),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            icon: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFD4AF37),
            ),
            title: const Text('توليد مسودة أمر شراء ذكي'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اختر المورد المراد إصدار مسودة الشراء إليه:'),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSupplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    items: suppliers.map((s) {
                      return DropdownMenuItem<String>(
                        value: s['id'] as String,
                        child: Text(s['name'] as String),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          selectedSupplierId = val;
                          selectedSupplierName = suppliers.firstWhere(
                              (s) => s['id'] == val)['name'] as String;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.10),
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: Color(0xFFB8860B),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${targetProducts.length} صنف بكميات إعادة تزويد قابلة للتعديل.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          DzdFormatter.formatCentimes(estimatedTotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              GoldButton(
                label: 'إنشاء المسودة',
                compact: true,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    final authUser = ref.read(authStateProvider);
    final repo = ref.read(inventoryRepositoryProvider);

    setState(() => _isGeneratingPO = true);
    try {
      final overrides = <String, int>{
        for (final product in targetProducts)
          if (_qtyFor(product) > 0) product.id: _qtyFor(product),
      };
      final po = await repo.generateDraftPOFromLowStock(
        supplierId: selectedSupplierId,
        supplierName: selectedSupplierName,
        createdById: authUser?.id ?? 'manager',
        createdByName: authUser?.name ?? 'مدير المخزون',
        selectedProductIds: targetProducts.map((p) => p.id).toList(),
        quantityOverrides: overrides,
      );

      ref.invalidate(purchaseOrdersListProvider);
      ref.invalidate(lowStockProductsProvider);

      if (!mounted) return;
      setState(() {
        _selectedProductIds.clear();
        _quantities.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنشاء مسودة أمر الشراء [${po.poNumber}] بنجاح.'),
          backgroundColor: context.appColors.success,
          action: widget.onOpenPurchaseOrders == null
              ? null
              : SnackBarAction(
                  label: 'عرض أوامر الشراء',
                  onPressed: widget.onOpenPurchaseOrders!,
                ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء أمر الشراء: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPO = false);
    }
  }

  void _toggleSelectAll(List<ProductEntity> visible) {
    final allSelected = visible.isNotEmpty &&
        visible.every((p) => _selectedProductIds.contains(p.id));
    setState(() {
      if (allSelected) {
        for (final p in visible) {
          _selectedProductIds.remove(p.id);
        }
      } else {
        for (final p in visible) {
          _selectedProductIds.add(p.id);
          _quantities.putIfAbsent(
            p.id,
            () => p.suggestedReplenishmentQty,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lowStockAsync = ref.watch(lowStockProductsProvider);
    final filter = ref.watch(stockFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المخزون المنخفض وإعادة التزويد'),
        actions: [
          if (widget.onOpenPurchaseOrders != null)
            TextButton.icon(
              onPressed: widget.onOpenPurchaseOrders,
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: const Text('أوامر الشراء'),
            ),
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(lowStockProductsProvider),
          ),
        ],
      ),
      body: lowStockAsync.when(
        skipLoadingOnRefresh: true,
        data: (products) {
          final visible = products.where((p) {
            if (!_matchesFilter(p, filter)) return false;
            if (_search.isNotEmpty) {
              final q = _search.toLowerCase();
              return p.nameAr.toLowerCase().contains(q) ||
                  p.nameFr.toLowerCase().contains(q) ||
                  p.category.toLowerCase().contains(q) ||
                  p.barcodes.any((b) => b.contains(q));
            }
            return true;
          }).toList();

          final criticalCount =
              products.where((p) => p.isCritical || p.isOutOfStock).length;
          final lowCount = products.where((p) => p.isLowStock).length;
          final selectedProducts = products
              .where((p) => _selectedProductIds.contains(p.id))
              .toList();
          final selectedCost = selectedProducts.fold<int>(
            0,
            (sum, p) => sum + (_qtyFor(p) * p.costCentimes),
          );
          final allVisibleSelected = visible.isNotEmpty &&
              visible.every((p) => _selectedProductIds.contains(p.id));

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(lowStockProductsProvider);
              await ref.read(lowStockProductsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                _hero(products, criticalCount, lowCount, theme),
                AppSpacing.gapMd,
                _toolbar(
                  theme,
                  products,
                  visible,
                  selectedProducts,
                  selectedCost,
                  allVisibleSelected,
                ),
                AppSpacing.gapMd,
                if (visible.isEmpty)
                  _emptyState(products, theme)
                else
                  ...visible.map(
                    (product) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _productCard(product, theme),
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () =>
            const AppLoadingView(message: 'جاري تحليل مستويات المخزون...'),
        error: (err, _) => AppErrorView(
          message: '$err',
          onRetry: () => ref.invalidate(lowStockProductsProvider),
        ),
      ),
    );
  }

  bool _matchesFilter(ProductEntity product, StockFilterOption filter) {
    return switch (filter) {
      StockFilterOption.all => true,
      StockFilterOption.lowStock =>
        product.healthStatus == StockHealthStatus.lowStock,
      StockFilterOption.critical =>
        product.healthStatus == StockHealthStatus.critical,
      StockFilterOption.outOfStock =>
        product.healthStatus == StockHealthStatus.outOfStock,
      StockFilterOption.overstocked =>
        product.healthStatus == StockHealthStatus.overstocked,
    };
  }

  Widget _hero(
    List<ProductEntity> products,
    int criticalCount,
    int lowCount,
    ThemeData theme,
  ) {
    final totalCost = products.fold<int>(
      0,
      (sum, p) => sum + (_qtyFor(p) * p.costCentimes),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (criticalCount > 0 ? Colors.red : const Color(0xFFD4AF37))
                .withValues(alpha: 0.12),
            theme.colorScheme.surfaceContainerLowest,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: (criticalCount > 0 ? Colors.red : const Color(0xFFD4AF37))
              .withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color:
                      (criticalCount > 0 ? Colors.red : const Color(0xFFD4AF37))
                          .withValues(alpha: 0.14),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(
                  Icons.inventory_2_rounded,
                  size: 24,
                  color:
                      criticalCount > 0 ? Colors.red : const Color(0xFFB8860B),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      criticalCount > 0
                          ? 'يوجد $criticalCount صنف يحتاج تدخلاً عاجلاً'
                          : 'مستويات المخزون تحت السيطرة',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$criticalCount حرج/نفد • $lowCount منخفض • تكلفة التزويد المقدرة ${DzdFormatter.formatCentimes(totalCost)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,
          ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              value: products.isEmpty
                  ? 1
                  : (products.length - criticalCount) / products.length,
              minHeight: 7,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                criticalCount > 0 ? Colors.red : const Color(0xFF27AE60),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(
    ThemeData theme,
    List<ProductEntity> products,
    List<ProductEntity> visible,
    List<ProductEntity> selectedProducts,
    int selectedCost,
    bool allVisibleSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث في الأصناف التي تحتاج تزويد...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HeadlessBarcodeScannerButton(
                        controller: _searchController,
                        onScanned: (code) =>
                            setState(() => _search = code.trim()),
                        tooltip: 'مسح باركود الصنف',
                      ),
                      if (_search.isNotEmpty)
                        IconButton(
                          tooltip: 'مسح البحث',
                          icon: const Icon(Icons.clear_rounded, size: 17),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                    ],
                  ),
                ),
                onChanged: (v) => setState(() => _search = v.trim()),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: allVisibleSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل',
              icon: Icon(
                allVisibleSelected
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              onPressed:
                  visible.isEmpty ? null : () => _toggleSelectAll(visible),
            ),
          ],
        ),
        AppSpacing.gapSm,
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: StockFilterOption.values
                .where((f) => f != StockFilterOption.overstocked)
                .map((option) {
              final selected = ref.watch(stockFilterProvider) == option;
              final count = switch (option) {
                StockFilterOption.all => products.length,
                StockFilterOption.lowStock => products
                    .where((p) => p.healthStatus == StockHealthStatus.lowStock)
                    .length,
                StockFilterOption.critical => products
                    .where((p) => p.healthStatus == StockHealthStatus.critical)
                    .length,
                StockFilterOption.outOfStock => products
                    .where(
                        (p) => p.healthStatus == StockHealthStatus.outOfStock)
                    .length,
                StockFilterOption.overstocked => 0,
              };
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  label: Text('${option.labelAr} ($count)'),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? const Color(0xFF1A1400) : null,
                  ),
                  selectedColor: const Color(0xFFD4AF37),
                  onSelected: (_) =>
                      ref.read(stockFilterProvider.notifier).state = option,
                ),
              );
            }).toList(),
          ),
        ),
        AppSpacing.gapMd,
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 540;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${selectedProducts.length} صنف محدد',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'القيمة التقديرية: ${DzdFormatter.formatCentimes(selectedCost)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final action = GoldButton.icon(
                icon: Icons.post_add_rounded,
                label: _isGeneratingPO
                    ? 'جاري الإنشاء...'
                    : 'توليد مسودة أمر شراء (${selectedProducts.isEmpty ? visible.length : selectedProducts.length})',
                compact: true,
                height: 40,
                onPressed: products.isEmpty || _isGeneratingPO
                    ? null
                    : () => _generateDraftPO(
                          _selectedProductIds.isEmpty ? visible : products,
                        ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    info,
                    AppSpacing.gapSm,
                    action,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: info),
                  action,
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _productCard(ProductEntity product, ThemeData theme) {
    final selected = _selectedProductIds.contains(product.id);
    final qty = _qtyFor(product);
    final lineCost = qty * product.costCentimes;
    final isCompact = MediaQuery.sizeOf(context).width < 640;
    final borderColor = product.isCritical || product.isOutOfStock
        ? Colors.red.withValues(alpha: 0.40)
        : product.isLowStock
            ? Colors.orange.withValues(alpha: 0.40)
            : theme.colorScheme.outlineVariant;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.nameAr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _healthBadge(product.healthStatus),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'رصيد: ${product.availableQty} ${product.unit} • ROP: ${product.reorderPoint} • السعة: ${product.maxCapacity}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: LinearProgressIndicator(
            value: product.maxCapacity == 0
                ? 0
                : (product.availableQty / product.maxCapacity).clamp(0, 1),
            minHeight: 5,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              product.isCritical || product.isOutOfStock
                  ? Colors.red
                  : product.isLowStock
                      ? Colors.orange
                      : const Color(0xFF27AE60),
            ),
          ),
        ),
      ],
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QtyButton(
          icon: Icons.remove_rounded,
          onPressed: qty <= 0 ? null : () => _setQty(product, qty - 1),
        ),
        InkWell(
          onTap: () => _promptQuantity(product),
          borderRadius: AppRadius.xsAll,
          child: Container(
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
              borderRadius: AppRadius.xsAll,
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.40),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  product.unit,
                  style: TextStyle(
                    fontSize: 8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        _QtyButton(
          icon: Icons.add_rounded,
          onPressed: () => _setQty(product, qty + 1),
        ),
      ],
    );

    final cost = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          DzdFormatter.formatCentimes(lineCost),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: Color(0xFFB8860B),
          ),
        ),
        Text(
          'المقترح آلياً: ${product.suggestedReplenishmentQty}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 9,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFD4AF37).withValues(alpha: 0.055)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: selected ? const Color(0xFFD4AF37) : borderColor,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => _toggleSelection(product, value ?? false),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      info,
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          controls,
                          const Spacer(),
                          cost,
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: AppSpacing.md),
                      controls,
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(width: 110, child: cost),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(List<ProductEntity> products, ThemeData theme) {
    final healthy = products.isEmpty && _search.isEmpty;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color:
                  (healthy ? const Color(0xFF27AE60) : const Color(0xFFD4AF37))
                      .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              healthy ? Icons.verified_rounded : Icons.filter_alt_off_rounded,
              size: 34,
              color:
                  healthy ? const Color(0xFF27AE60) : const Color(0xFFB8860B),
            ),
          ),
          AppSpacing.gapMd,
          Text(
            healthy ? 'المخزون في حالة ممتازة!' : 'لا توجد أصناف مطابقة',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          AppSpacing.gapXs,
          Text(
            healthy
                ? 'لا توجد منتجات دون نقطة إعادة الطلب حالياً.'
                : 'جرّب تغيير الفلتر أو كلمة البحث.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthBadge(StockHealthStatus status) {
    final (bg, fg) = switch (status) {
      StockHealthStatus.outOfStock || StockHealthStatus.critical => (
          Colors.red.withValues(alpha: 0.14),
          Colors.red
        ),
      StockHealthStatus.lowStock => (
          Colors.orange.withValues(alpha: 0.14),
          Colors.orange
        ),
      StockHealthStatus.overstocked => (
          Colors.blue.withValues(alpha: 0.14),
          Colors.blue
        ),
      StockHealthStatus.normal => (
          const Color(0xFF27AE60).withValues(alpha: 0.14),
          const Color(0xFF27AE60)
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.xsAll,
      ),
      child: Text(
        status.labelAr,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _QtyButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 36,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
      ),
    );
  }
}
