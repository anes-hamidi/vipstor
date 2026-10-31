import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import 'pin_confirm_dialog.dart';

/// Goods Received Note (GRN) entry against an open purchase order.
///
/// Quantities are clamped to the remaining ordered quantity and posted to the
/// authoritative stock ledger through `rpc_adjust_stock` after PIN validation.
class GrnReceivingDialog extends ConsumerStatefulWidget {
  final PurchaseOrderEntity purchaseOrder;

  const GrnReceivingDialog({super.key, required this.purchaseOrder});

  static Future<bool?> show(
    BuildContext context,
    PurchaseOrderEntity purchaseOrder,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GrnReceivingDialog(purchaseOrder: purchaseOrder),
    );
  }

  @override
  ConsumerState<GrnReceivingDialog> createState() => _GrnReceivingDialogState();
}

class _GrnReceivingDialogState extends ConsumerState<GrnReceivingDialog> {
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _costControllers = {};
  final Map<String, TextEditingController> _batchControllers = {};
  final Map<String, TextEditingController> _expiryControllers = {};
  bool _isSubmitting = false;

  List<PurchaseOrderItemEntity> get _openItems => widget.purchaseOrder.items
      .where((item) => item.remainingQty > 0)
      .toList();

  @override
  void initState() {
    super.initState();
    for (final item in _openItems) {
      _qtyControllers[item.id] = TextEditingController(
        text: '${item.remainingQty}',
      );
      _costControllers[item.id] = TextEditingController(
        text: (item.unitCostCentimes / 100).toStringAsFixed(0),
      );
      _batchControllers[item.id] = TextEditingController(
        text: item.batchNumber ?? '',
      );
      _expiryControllers[item.id] = TextEditingController(
        text: item.expiryDate == null ? '' : _formatDate(item.expiryDate!),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in [
      ..._qtyControllers.values,
      ..._costControllers.values,
      ..._batchControllers.values,
      ..._expiryControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _receivedQty(PurchaseOrderItemEntity item) {
    final raw = int.tryParse(_qtyControllers[item.id]?.text ?? '') ?? 0;
    return raw.clamp(0, item.remainingQty);
  }

  int _unitCost(PurchaseOrderItemEntity item) {
    final raw = _costControllers[item.id]?.text.trim() ?? '';
    if (raw.isEmpty) return item.unitCostCentimes;
    final dinars = int.tryParse(raw);
    return dinars == null ? item.unitCostCentimes : dinars * 100;
  }

  int get _totalCentimes => _openItems.fold<int>(
        0,
        (sum, item) => sum + (_receivedQty(item) * _unitCost(item)),
      );

  Future<void> _submit() async {
    for (final item in _openItems) {
      final expiryRaw = _expiryControllers[item.id]?.text.trim() ?? '';
      if (expiryRaw.isNotEmpty && DateTime.tryParse(expiryRaw) == null) {
        _showError(
          'تاريخ صلاحية غير صالح للصنف "${item.productName}". استخدم الصيغة YYYY-MM-DD.',
        );
        return;
      }
    }

    final rows = _openItems.where((item) => _receivedQty(item) > 0).map((item) {
      final expiryRaw = _expiryControllers[item.id]?.text.trim() ?? '';
      final expiry = expiryRaw.isEmpty ? null : DateTime.tryParse(expiryRaw);
      return {
        'product_id': item.productId,
        'qty_received': _receivedQty(item),
        'unit_cost_centimes': _unitCost(item),
        'batch_number': _batchControllers[item.id]?.text.trim().isEmpty ?? true
            ? null
            : _batchControllers[item.id]!.text.trim(),
        'expiry_date': expiry?.toIso8601String(),
      };
    }).toList();

    if (rows.isEmpty) {
      _showError('أدخل كمية مستلمة أكبر من صفر لصنف واحد على الأقل.');
      return;
    }

    final user = ref.read(authStateProvider);
    if (user == null) {
      _showError('انتهت الجلسة. يرجى تسجيل الدخول من جديد.');
      return;
    }

    final pin = await PinConfirmDialog.show(
      context,
      message: 'أدخل رمز PIN لتأكيد استلام البضاعة وترحيلها إلى المخزون',
      confirmLabel: 'تأكيد الاستلام',
    );
    if (!mounted || pin == null || pin.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(inventoryRepositoryProvider).receiveGoodsNote(
            poId: widget.purchaseOrder.id,
            receivedItems: rows,
            userId: user.id,
            userName: user.name,
            callerPin: pin,
          );

      ref.invalidate(liveProductsProvider);
      ref.invalidate(lowStockProductsProvider);
      ref.invalidate(purchaseOrdersListProvider);
      ref.invalidate(stockAdjustmentHistoryProvider);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final successColor = context.appColors.success;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'تم استلام البضاعة وترحيلها للمخزون بأمر الشراء [${widget.purchaseOrder.poNumber}].',
          ),
          backgroundColor: successColor,
        ),
      );
    } catch (e) {
      _showError('فشل استلام البضاعة: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 880),
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
                    _poSummary(theme),
                    AppSpacing.gapLg,
                    const SectionHeader(
                      title: 'الكميات المستلمة فعلياً',
                      dense: true,
                    ),
                    AppSpacing.gapSm,
                    ..._openItems.map((item) => _itemRow(item, theme)),
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
                Icons.inventory_rounded,
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
                  'استلام بضاعة — ${widget.purchaseOrder.poNumber}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'سجّل الكميات الواردة فعلياً مع الدفعة وتاريخ الصلاحية',
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

  Widget _poSummary(ThemeData theme) {
    final po = widget.purchaseOrder;
    return LuxuryCard(
      goldAccent: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 18,
                color: Color(0xFFB8860B),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  po.supplierName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${po.totalReceivedQuantity}/${po.totalOrderedQuantity} وحدة',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              value: po.totalOrderedQuantity == 0
                  ? 0
                  : po.totalReceivedQuantity / po.totalOrderedQuantity,
              minHeight: 7,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation(Color(0xFFD4AF37)),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _metaChip(
                Icons.event_outlined,
                'تاريخ الطلب: ${_formatDate(po.orderDate)}',
              ),
              if (po.expectedDeliveryDate != null)
                _metaChip(
                  Icons.local_shipping_outlined,
                  'التسليم المتوقع: ${_formatDate(po.expectedDeliveryDate!)}',
                ),
              _metaChip(
                Icons.payments_outlined,
                'قيمة الأمر: ${DzdFormatter.formatCentimes(po.totalOrderedAmountCentimes)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemRow(PurchaseOrderItemEntity item, ThemeData theme) {
    final isCompact = MediaQuery.sizeOf(context).width < 680;
    final qtyField = TextField(
      controller: _qtyControllers[item.id],
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        isDense: true,
        labelText: 'المستلم',
        suffixText: item.unit,
        helperText: 'المتبقي: ${item.remainingQty}',
      ),
      onChanged: (_) => setState(() {}),
    );
    final costField = TextField(
      controller: _costControllers[item.id],
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'تكلفة الوحدة',
        suffixText: 'دج',
      ),
      onChanged: (_) => setState(() {}),
    );
    final batchField = TextField(
      controller: _batchControllers[item.id],
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'رقم الدفعة',
        hintText: 'LOT-...',
      ),
    );
    final expiryField = TextField(
      controller: _expiryControllers[item.id],
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'الصلاحية',
        hintText: 'YYYY-MM-DD',
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                'مطلوب ${item.orderedQty} • مستلم ${item.receivedQty}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isCompact)
            Column(
              children: [
                Row(
                  children: [
                    Expanded(child: qtyField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: costField),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: batchField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: expiryField),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: qtyField),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: costField),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: batchField),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: expiryField),
              ],
            ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              'قيمة السطر: ${DzdFormatter.formatCentimes(_receivedQty(item) * _unitCost(item))}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFB8860B),
              ),
            ),
          ),
        ],
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
                  'إجمالي قيمة الاستلام',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                DzdPriceTag.lg(centimes: _totalCentimes, gold: true),
              ],
            ),
          ),
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          const SizedBox(width: AppSpacing.sm),
          GoldButton.icon(
            icon: Icons.download_done_rounded,
            label:
                _isSubmitting ? 'جاري الترحيل...' : 'تأكيد الاستلام والترحيل',
            loading: _isSubmitting,
            onPressed: _isSubmitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFFB8860B)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
