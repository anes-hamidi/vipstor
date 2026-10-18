import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:uuid/uuid.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

class StockAdjustmentDialog extends ConsumerStatefulWidget {
  final Product? initialProduct;

  const StockAdjustmentDialog({super.key, this.initialProduct});

  @override
  ConsumerState<StockAdjustmentDialog> createState() =>
      _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends ConsumerState<StockAdjustmentDialog> {
  String? _selectedProductId;
  StockAdjustmentReason _reason = StockAdjustmentReason.damaged;
  AdjustmentDirection _direction = AdjustmentDirection.decrease;
  final _qtyController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  final _batchController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProduct?.id;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  int get _quantity => int.tryParse(_qtyController.text) ?? 1;

  int get _qtyChange =>
      _direction == AdjustmentDirection.increase ? _quantity : -_quantity;

  Product? _resolveProduct(List<Product> products) {
    if (_selectedProductId == null) return null;
    return products.where((p) => p.id == _selectedProductId).firstOrNull;
  }

  int _getImpactCostCentimes(Product? product) {
    if (product == null) return 0;
    return _quantity * product.costCentimes;
  }

  Future<void> _submitAdjustment(Product? selectedProduct) async {
    if (selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار منتج للتسوية')),
      );
      return;
    }

    if (_quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إدخال كمية صالحة أكبر من الصفر')),
      );
      return;
    }

    final authUser = ref.read(authStateProvider);
    final userId = authUser?.id ?? 'manager';
    final userName = authUser?.name ?? 'مدير المخزون';

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(inventoryRepositoryProvider);
      const uuid = Uuid();
      final adjustment = StockAdjustmentEntity(
        id: uuid.v4(),
        referenceNumber:
            'ADJ-${DateTime.now().millisecondsSinceEpoch % 100000}',
        reason: _reason,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        locationId: 'loc_main',
        locationName: 'المستودع الرئيسي',
        adjustedByUserId: userId,
        adjustedByName: userName,
        createdAt: DateTime.now(),
        items: [
          StockAdjustmentItemEntity(
            id: uuid.v4(),
            productId: selectedProduct.id,
            productName: selectedProduct.nameAr,
            unit: selectedProduct.unit,
            oldStock: selectedProduct.availableQty,
            newStock:
                (selectedProduct.availableQty + _qtyChange).clamp(0, 9999999),
            qtyChange: _qtyChange,
            unitCostCentimes: selectedProduct.costCentimes,
            batchNumber: _batchController.text.trim().isNotEmpty
                ? _batchController.text.trim()
                : null,
            itemNotes: _notesController.text.trim().isNotEmpty
                ? _notesController.text.trim()
                : null,
          ),
        ],
      );

      await repo.executeStockAdjustment(adjustment: adjustment);

      // Invalidate relevant providers
      ref.invalidate(liveProductsProvider);
      ref.invalidate(lowStockProductsProvider);
      ref.invalidate(stockAdjustmentHistoryProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل تسوية المخزون (${_reason.labelAr}) بنجاح!',
            ),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل التسوية: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final productsAsync = ref.watch(liveProductsProvider);
    final products = productsAsync.value ?? [];
    final selectedProduct = _resolveProduct(products);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1A16) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.gold,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.tune_rounded,
                          size: 20, color: Color(0xFF1A1400)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تسوية وتعديل المخزون المباشر',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'تحديث فوري مع سجل تدقيق إلزامي للأسباب والتكاليف',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Product Picker (if not fixed)
              Text(
                'المنتج المستهدف',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xs),
              productsAsync.when(
                data: (products) {
                  // Safety: Deduplicate products by id to prevent multiple items with same value
                  final seenIds = <String>{};
                  final uniqueProducts =
                      products.where((p) => seenIds.add(p.id)).toList();

                  final hasValidSelection = _selectedProductId != null &&
                      uniqueProducts.any((p) => p.id == _selectedProductId);
                  final effectiveSelectedId =
                      hasValidSelection ? _selectedProductId : null;

                  return DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: effectiveSelectedId,
                    hint: const Text('اختر المنتج...'),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                    ),
                    items: uniqueProducts.map((p) {
                      return DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(
                          '${p.nameAr} (متاح: ${p.availableQty} ${p.unit})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (id) => setState(() => _selectedProductId = id),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر تحميل المنتجات'),
              ),
              const SizedBox(height: AppSpacing.md),

              // Direction Toggle (Stock In / Stock Out)
              Text(
                'نوع حركة المخزون',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<AdjustmentDirection>(
                segments: const [
                  ButtonSegment(
                    value: AdjustmentDirection.decrease,
                    label: Text('خصم / إخراج (-)'),
                    icon: Icon(Icons.remove_circle_outline, color: Colors.red),
                  ),
                  ButtonSegment(
                    value: AdjustmentDirection.increase,
                    label: Text('إضافة / إدخال (+)'),
                    icon: Icon(Icons.add_circle_outline, color: Colors.green),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (set) {
                  setState(() => _direction = set.first);
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Reason dropdown (Mandatory tags)
              Text(
                'السبب الإلزامي للتسوية',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<StockAdjustmentReason>(
                isExpanded: true,
                initialValue: _reason,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.flag_outlined, size: 20),
                ),
                items: StockAdjustmentReason.values.map((r) {
                  return DropdownMenuItem(
                    value: r,
                    child: Text(r.labelAr),
                  );
                }).toList(),
                onChanged: (r) {
                  if (r != null) setState(() => _reason = r);
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Quantity + Batch input row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الكمية المعدلة',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        TextField(
                          controller: _qtyController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '1',
                            suffixText: selectedProduct?.unit ?? 'وحدة',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'رقم الدفعة / التشغيلة (اختياري)',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        TextField(
                          controller: _batchController,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'LOT-XXXXX',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Notes
              Text(
                'ملاحظات إضافية / مبررات',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'مثال: علبة متضررة أثناء النقل الداخلي...',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Financial & Balance Impact Card
              if (selectedProduct != null)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF141210)
                        : const Color(0xFFFBF8F0),
                    borderRadius: AppRadius.smAll,
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الرصيد بعد العملية',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(selectedProduct.availableQty + _qtyChange).clamp(0, 9999999)} ${selectedProduct.unit}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'الأثر المالي المقدر',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          DzdPriceTag(
                            centimes: _getImpactCostCentimes(selectedProduct),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _direction == AdjustmentDirection.increase
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GoldButton.icon(
                    icon: Icons.check_circle_outline_rounded,
                    label: _isSubmitting
                        ? 'جاري المعالجة...'
                        : 'تأكيد وحفظ التسوية',
                    onPressed: _isSubmitting
                        ? null
                        : () => _submitAdjustment(selectedProduct),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
