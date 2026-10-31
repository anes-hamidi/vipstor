import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:uuid/uuid.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../../common/widgets/headless_barcode_scanner_button.dart';

/// Manual purchase-order composer used by the inventory manager.
///
/// Lines start from the product's last landed cost and can be adjusted before
/// the order is saved as a draft or sent to the supplier.
class CreatePurchaseOrderDialog extends ConsumerStatefulWidget {
  final String? initialSupplierId;

  const CreatePurchaseOrderDialog({super.key, this.initialSupplierId});

  @override
  ConsumerState<CreatePurchaseOrderDialog> createState() =>
      _CreatePurchaseOrderDialogState();
}

class _CreatePurchaseOrderDialogState
    extends ConsumerState<CreatePurchaseOrderDialog> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_PoDraftLine> _lines = [];

  String? _supplierId;
  String _search = '';
  DateTime? _expectedDeliveryDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _supplierId = widget.initialSupplierId;
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _addProduct(ProductEntity product) {
    final existing =
        _lines.where((l) => l.product.id == product.id).firstOrNull;
    setState(() {
      if (existing != null) {
        existing.qty += 1;
        existing.qtyController.text = '${existing.qty}';
      } else {
        _lines.add(_PoDraftLine(product: product));
      }
      _searchController.clear();
      _search = '';
    });
  }

  void _removeLine(_PoDraftLine line) {
    setState(() {
      _lines.remove(line);
      line.dispose();
    });
  }

  int get _totalCentimes => _lines.fold<int>(
        0,
        (sum, line) => sum + line.qty * line.unitCostCentimes,
      );

  Future<void> _pickExpectedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _expectedDeliveryDate ?? now.add(const Duration(days: 7)),
      helpText: 'تاريخ التسليم المتوقع',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
    );
    if (picked != null) {
      setState(() => _expectedDeliveryDate = picked);
    }
  }

  Future<void> _save(PurchaseOrderStatus status) async {
    if (_supplierId == null) {
      _showError('يرجى اختيار المورد أولاً.');
      return;
    }
    final validLines = _lines.where((l) => l.qty > 0).toList();
    if (validLines.isEmpty) {
      _showError('أضف صنفاً واحداً على الأقل إلى أمر الشراء.');
      return;
    }

    final suppliers = ref.read(suppliersProvider).value ?? const [];
    final supplier = suppliers.where((s) => s['id'] == _supplierId).firstOrNull;
    if (supplier == null) {
      _showError('تعذر العثور على بيانات المورد المحدد.');
      return;
    }

    final user = ref.read(authStateProvider);
    if (user == null) {
      _showError('انتهت الجلسة. يرجى تسجيل الدخول من جديد.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      const uuid = Uuid();
      final now = DateTime.now();
      final po = PurchaseOrderEntity(
        id: uuid.v4(),
        poNumber: 'PO-${now.year}-${now.millisecondsSinceEpoch % 100000}',
        supplierId: _supplierId!,
        supplierName: supplier['name'] as String? ?? 'مورد',
        supplierPhone: supplier['phone'] as String?,
        status: status,
        orderDate: now,
        expectedDeliveryDate: _expectedDeliveryDate,
        createdByUserId: user.id,
        createdByName: user.name,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        items: validLines.map((line) {
          return PurchaseOrderItemEntity(
            id: uuid.v4(),
            productId: line.product.id,
            productName: line.product.nameAr,
            unit: line.product.unit,
            orderedQty: line.qty,
            receivedQty: 0,
            unitCostCentimes: line.unitCostCentimes,
            sellingPriceCentimes:
                line.product.getPriceForQuantity(PriceTier.retail, line.qty),
            notes: line.unitCostCentimes != line.product.costCentimes
                ? 'تكلفة معدلة يدوياً (آخر تكلفة: ${DzdFormatter.formatCentimes(line.product.costCentimes)})'
                : null,
          );
        }).toList(),
      );

      await ref.read(inventoryRepositoryProvider).createPurchaseOrder(
            purchaseOrder: po,
          );
      ref.invalidate(purchaseOrdersListProvider);
      ref.invalidate(lowStockProductsProvider);

      if (mounted) Navigator.of(context).pop(po);
    } catch (e) {
      _showError('فشل إنشاء أمر الشراء: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(liveProductsProvider);
    final suppliersAsync = ref.watch(suppliersProvider);
    final isCompact = context.isCompact;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? AppSpacing.md : AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 860),
        child: Column(
          children: [
            _header(theme),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _supplierSection(suppliersAsync, theme),
                    AppSpacing.gapLg,
                    _productPicker(productsAsync, theme),
                    AppSpacing.gapLg,
                    _linesSection(theme),
                    AppSpacing.gapLg,
                    _notesSection(theme),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _footer(theme),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: AppRadius.mdAll,
              boxShadow: [AppShadows.goldGlowSm],
            ),
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.post_add_rounded,
                size: 22,
                color: Color(0xFF1A1400),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أمر شراء جديد',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'أنشئ مسودة أو أرسل الطلب مباشرة إلى المورد',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إغلاق',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _supplierSection(
    AsyncValue<List<Map<String, dynamic>>> suppliersAsync,
    ThemeData theme,
  ) {
    return LuxuryCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'بيانات التوريد', dense: true),
          AppSpacing.gapSm,
          suppliersAsync.when(
            skipLoadingOnRefresh: true,
            data: (suppliers) {
              final ids = suppliers.map((s) => s['id'] as String).toSet();
              final effective = ids.contains(_supplierId) ? _supplierId : null;
              return Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: effective,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'المورد *',
                        prefixIcon: Icon(Icons.storefront_outlined),
                        isDense: true,
                      ),
                      hint: const Text('اختر المورد...'),
                      items: suppliers.map((s) {
                        return DropdownMenuItem<String>(
                          value: s['id'] as String,
                          child: Text(
                            s['name'] as String? ?? 'مورد',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _supplierId = value),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: _pickExpectedDate,
                      borderRadius: AppRadius.smAll,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'التسليم المتوقع (اختياري)',
                          prefixIcon: Icon(Icons.event_outlined),
                          isDense: true,
                        ),
                        child: Text(
                          _expectedDeliveryDate == null
                              ? 'غير محدد'
                              : _formatDate(_expectedDeliveryDate!),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('تعذر تحميل قائمة الموردين'),
          ),
        ],
      ),
    );
  }

  Widget _productPicker(
    AsyncValue<List<ProductEntity>> productsAsync,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'إضافة الأصناف', dense: true),
        AppSpacing.gapSm,
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'بحث بالاسم أو الباركود لإضافة صنف...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: HeadlessBarcodeScannerButton(
              controller: _searchController,
              onScanned: (code) => setState(() => _search = code.trim()),
              tooltip: 'مسح باركود الصنف',
            ),
          ),
          onChanged: (value) => setState(() => _search = value.trim()),
        ),
        AppSpacing.gapSm,
        productsAsync.when(
          data: (products) {
            final q = _search.toLowerCase();
            final filtered = products
                .where((p) {
                  if (q.isEmpty) return true;
                  return p.nameAr.toLowerCase().contains(q) ||
                      p.nameFr.toLowerCase().contains(q) ||
                      p.category.toLowerCase().contains(q) ||
                      p.barcodes.any((b) => b.contains(q));
                })
                .take(8)
                .toList();

            if (filtered.isEmpty) {
              return Text(
                'لا توجد أصناف مطابقة.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }

            return Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = filtered[index];
                  final alreadyAdded =
                      _lines.any((l) => l.product.id == product.id);
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor:
                          const Color(0xFFD4AF37).withValues(alpha: 0.14),
                      child: Icon(
                        alreadyAdded
                            ? Icons.check_rounded
                            : Icons.inventory_2_outlined,
                        size: 18,
                        color: const Color(0xFFB8860B),
                      ),
                    ),
                    title: Text(
                      product.nameAr,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      'المخزون: ${product.availableQty} ${product.unit}  •  التكلفة: ${DzdFormatter.formatCentimes(product.costCentimes)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: IconButton(
                      tooltip: 'إضافة',
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onPressed: () => _addProduct(product),
                    ),
                    onTap: () => _addProduct(product),
                  );
                },
              ),
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('تعذر تحميل الأصناف'),
        ),
      ],
    );
  }

  Widget _linesSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionHeader(title: 'أصناف أمر الشراء', dense: true),
            Text(
              '${_lines.length} أصناف',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        AppSpacing.gapSm,
        if (_lines.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.playlist_add_rounded,
                  size: 36,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.45),
                ),
                AppSpacing.gapSm,
                Text(
                  'ابحث عن صنف وأضفه لبدء بناء أمر الشراء.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final line = _lines[index];
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.product.nameAr,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${line.product.unit} • آخر تكلفة ${DzdFormatter.formatCentimes(line.product.costCentimes)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 74,
                        child: TextField(
                          controller: line.costController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'التكلفة',
                            suffixText: 'دج',
                          ),
                          onChanged: (value) => setState(
                            () => line.unitCostCentimes =
                                (int.tryParse(value) ?? 0) * 100,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      _QtyStepper(
                        quantity: line.qty,
                        onChanged: (value) {
                          setState(() {
                            line.qty = value;
                            line.qtyController.text = '$value';
                          });
                        },
                      ),
                      SizedBox(
                        width: 82,
                        child: Text(
                          DzdFormatter.formatCentimes(
                            line.qty * line.unitCostCentimes,
                          ),
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: Colors.red,
                        ),
                        onPressed: () => _removeLine(line),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _notesSection(ThemeData theme) {
    return TextField(
      controller: _notesController,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'ملاحظات أمر الشراء (اختياري)',
        hintText: 'مثال: التسليم على دفعتين، يرجى إرفاق الفاتورة...',
        prefixIcon: Icon(Icons.notes_rounded),
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'إجمالي أمر الشراء',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                DzdPriceTag.lg(centimes: _totalCentimes, gold: true),
              ],
            ),
          ),
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          const SizedBox(width: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed:
                _isSaving ? null : () => _save(PurchaseOrderStatus.draft),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('حفظ كمسودة'),
          ),
          const SizedBox(width: AppSpacing.sm),
          GoldButton.icon(
            icon: Icons.send_rounded,
            label: _isSaving ? 'جاري الحفظ...' : 'إنشاء وإرسال',
            loading: _isSaving,
            onPressed:
                _isSaving ? null : () => _save(PurchaseOrderStatus.ordered),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _PoDraftLine {
  final ProductEntity product;
  final TextEditingController qtyController;
  final TextEditingController costController;
  int qty;
  int unitCostCentimes;

  _PoDraftLine({required this.product})
      : qty = 1,
        unitCostCentimes = product.costCentimes,
        qtyController = TextEditingController(text: '1'),
        costController = TextEditingController(
          text: (product.costCentimes / 100).toStringAsFixed(0),
        );

  void dispose() {
    qtyController.dispose();
    costController.dispose();
  }
}

class _QtyStepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;

  const _QtyStepper({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'إنقاص',
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 19),
          onPressed: quantity <= 1 ? null : () => onChanged(quantity - 1),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 30),
          alignment: Alignment.center,
          child: Text(
            '$quantity',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'زيادة',
          icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
          onPressed: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}
