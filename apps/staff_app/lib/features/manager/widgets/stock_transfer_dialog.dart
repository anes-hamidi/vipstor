import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:uuid/uuid.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../../common/widgets/headless_barcode_scanner_button.dart';
import '../../common/services/headless_barcode_scanner_service.dart';



class StockTransferDialog extends ConsumerStatefulWidget {
  const StockTransferDialog({super.key});

  @override
  ConsumerState<StockTransferDialog> createState() =>
      _StockTransferDialogState();
}

class _StockTransferDialogState extends ConsumerState<StockTransferDialog> {
  InventoryLocationEntity _sourceLocation = InventoryLocationEntity.mainWarehouse;
  InventoryLocationEntity _targetLocation = InventoryLocationEntity.retailFloor;
  TransferStatus _selectedStatus = TransferStatus.inTransit;

  String? _selectedProductId;
  final _qtyController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  final List<StockTransferItemEntity> _transferItems = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    HeadlessBarcodeScannerService.instance.stopScanning();
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _addItem(List<Product> products) {
    if (_selectedProductId == null) return;
    final product = products.where((p) => p.id == _selectedProductId).firstOrNull;
    if (product == null) return;

    final qty = int.tryParse(_qtyController.text) ?? 1;
    if (qty <= 0) return;

    const uuid = Uuid();
    final existingIdx =
        _transferItems.indexWhere((it) => it.productId == product.id);

    setState(() {
      if (existingIdx >= 0) {
        final existing = _transferItems[existingIdx];
        _transferItems[existingIdx] = StockTransferItemEntity(
          id: existing.id,
          productId: existing.productId,
          productName: existing.productName,
          unit: existing.unit,
          quantity: existing.quantity + qty,
          unitCostCentimes: existing.unitCostCentimes,
        );
      } else {
        _transferItems.add(
          StockTransferItemEntity(
            id: uuid.v4(),
            productId: product.id,
            productName: product.nameAr,
            unit: product.unit,
            quantity: qty,
            unitCostCentimes: product.costCentimes,
          ),
        );
      }
      _selectedProductId = null;
      _qtyController.text = '1';
    });
  }

  Future<void> _submitTransfer() async {
    if (_transferItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إضافة منتج واحد على الأقل للتحويل')),
      );
      return;
    }

    if (_sourceLocation.id == _targetLocation.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن التحويل إلى نفس الموقع المصدر')),
      );
      return;
    }

    final authUser = ref.read(authStateProvider);
    const uuid = Uuid();

    setState(() => _isSubmitting = true);

    try {
      final transfer = StockTransferEntity(
        id: uuid.v4(),
        transferNumber: 'TRF-${DateTime.now().millisecondsSinceEpoch % 100000}',
        sourceLocationId: _sourceLocation.id,
        sourceLocationName: _sourceLocation.nameAr,
        targetLocationId: _targetLocation.id,
        targetLocationName: _targetLocation.nameAr,
        status: _selectedStatus,
        requestedByUserId: authUser?.id ?? 'manager',
        requestedByName: authUser?.name ?? 'مدير المخزون',
        createdAt: DateTime.now(),
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        items: _transferItems,
      );

      final repo = ref.read(inventoryRepositoryProvider);
      await repo.createTransfer(transfer: transfer);

      ref.invalidate(stockTransfersProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إنشاء أمر النقل الداخلي [${transfer.transferNumber}] بنجاح!'),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء أمر النقل: $e'),
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

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1A16) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
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
                      child: Icon(Icons.swap_horiz_rounded, size: 20, color: Color(0xFF1A1400)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أمر نقل مخزون داخلي (Stock Transfer)',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'نقل بضاعة بين المستودع الرئيسي وصالة العرض أو المخازن الفرعية',
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

              // Locations Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('من (الموقع المصدر)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<InventoryLocationEntity>(
                          initialValue: _sourceLocation,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: InventoryLocationEntity.defaultLocations.map((loc) {
                            return DropdownMenuItem(value: loc, child: Text(loc.nameAr, overflow: TextOverflow.ellipsis));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _sourceLocation = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Icon(Icons.arrow_forward_rounded, color: Color(0xFFD4AF37)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('إلى (الموقع الوجهة)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<InventoryLocationEntity>(
                          initialValue: _targetLocation,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: InventoryLocationEntity.defaultLocations.map((loc) {
                            return DropdownMenuItem(value: loc, child: Text(loc.nameAr, overflow: TextOverflow.ellipsis));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _targetLocation = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // In-Transit status banner & toggle
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: const Color(0xFF9C27B0).withValues(alpha: 0.10),
                  borderRadius: AppRadius.smAll,
                  border: Border.all(
                    color: const Color(0xFF9C27B0).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined, color: Color(0xFF9C27B0), size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _selectedStatus == TransferStatus.inTransit
                            ? 'الحالة: في الطريق (In-Transit) — تُخصم البضائع فوراً من المصدر وتُحفظ كـ "في الطريق" لمنع الفقدان الوهمي حتى تأكيد الاستلام.'
                            : 'الحالة: مسودة قيد الانتظار (Pending) — لا تؤثر على الأرصدة حتى يتم اعتماد النقل.',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('في الطريق (In-Transit)', style: TextStyle(fontSize: 10)),
                      selected: _selectedStatus == TransferStatus.inTransit,
                      onSelected: (val) {
                        if (val) setState(() => _selectedStatus = TransferStatus.inTransit);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Add Item Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('اختيار الصنف للنقل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  HeadlessBarcodeScannerButton(
                    tooltip: 'مسح باركود الصنف لاختياره فوراً',
                    onScanned: (code) {
                      final clean = code.trim();
                      final products = productsAsync.value ?? [];
                      final found = products
                          .where((p) => p.barcodes.any((b) => b.trim() == clean))
                          .firstOrNull;
                      if (found != null) {
                        setState(() => _selectedProductId = found.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم تحديد الصنف: ${found.nameAr}'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('لم يتم العثور على صنف بالباركود: $clean'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 3,
                    child: productsAsync.when(
                      data: (products) {
                        final seenIds = <String>{};
                        final uniqueProducts =
                            products.where((p) => seenIds.add(p.id)).toList();
                        final hasValidSelection = _selectedProductId != null &&
                            uniqueProducts.any((p) => p.id == _selectedProductId);
                        final effectiveSelectedId =
                            hasValidSelection ? _selectedProductId : null;

                        return DropdownButtonFormField<String>(
                          initialValue: effectiveSelectedId,
                          hint: const Text('اختر صنفاً للنقل...'),
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: uniqueProducts.map((p) {
                            return DropdownMenuItem<String>(
                              value: p.id,
                              child: Text(
                                '${p.nameAr} (${p.availableQty} ${p.unit})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (id) =>
                              setState(() => _selectedProductId = id),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('تعذر تحميل الأصناف'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, labelText: 'الكمية'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GoldButton.icon(
                    icon: Icons.add_rounded,
                    label: 'إضافة',
                    compact: true,
                    onPressed: _selectedProductId != null
                        ? () => _addItem(productsAsync.value ?? [])
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Items Table / List
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? const Color(0x38D4AF37) : const Color(0x28C59B27)),
                  borderRadius: AppRadius.smAll,
                ),
                child: _transferItems.isEmpty
                    ? const Center(child: Text('لم يتم اختيار منتجات بعد', style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        itemCount: _transferItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final item = _transferItems[i];
                          return ListTile(
                            dense: true,
                            title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('الكمية: ${item.quantity} ${item.unit}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              onPressed: () => setState(() => _transferItems.removeAt(i)),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Notes
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات التحويل (اختياري)',
                  hintText: 'مثال: تغذية صالة العرض بالبضائع الأكثر مبيعاً...',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GoldButton.icon(
                    icon: Icons.send_rounded,
                    label: _isSubmitting ? 'جاري المعالجة...' : 'إرسال أمر النقل',
                    onPressed: _isSubmitting ? null : _submitTransfer,
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
