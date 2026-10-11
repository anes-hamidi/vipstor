import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

class SalesReturnDialog extends ConsumerStatefulWidget {
  final String? initialOrderId;

  const SalesReturnDialog({super.key, this.initialOrderId});

  @override
  ConsumerState<SalesReturnDialog> createState() => _SalesReturnDialogState();
}

class _SalesReturnDialogState extends ConsumerState<SalesReturnDialog> {
  final _orderIdController = TextEditingController();
  OrderEntity? _fetchedOrder;
  bool _isLoading = false;
  String? _errorMessage;

  // Selected item returns: productId -> returnQty
  final Map<String, int> _returnQuantities = {};
  String _selectedReason = 'wrong_item';
  bool _restockInventory = true;
  bool _isSubmitting = false;

  final Map<String, String> _reasons = {
    'wrong_item': 'منتج خاطئ / غير مطابق للطلب',
    'damaged': 'منتج تالف / معيب مصنعيًا',
    'expired': 'منتهي الصلاحية أو قريب الانتهاء',
    'customer_change': 'رغبة الزبون في التبديل أو الاسترجاع',
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialOrderId != null) {
      _orderIdController.text = widget.initialOrderId!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchOrder());
    }
  }

  @override
  void dispose() {
    _orderIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrder() async {
    final cleanId = _orderIdController.text.trim();
    if (cleanId.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _fetchedOrder = null;
      _returnQuantities.clear();
    });

    try {
      final repo = ref.read(orderRepositoryProvider);
      final order = await repo.getOrderById(cleanId);
      setState(() {
        _fetchedOrder = order;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'لم يتم العثور على وصل بهذا المعرّف: $cleanId';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  int get _calculatedRefundTotalCentimes {
    if (_fetchedOrder == null) return 0;
    int total = 0;
    for (final it in _fetchedOrder!.items) {
      final qty = _returnQuantities[it.productId] ?? 0;
      total += (qty * it.unitPriceCentimes);
    }
    return total;
  }

  Future<void> _handleConfirmReturn() async {
    if (_calculatedRefundTotalCentimes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى تحديد كمية واحدة على الأقل للإرجاع'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = ref.read(authStateProvider);
      final returnItemsList = _fetchedOrder!.items
          .where((it) => (_returnQuantities[it.productId] ?? 0) > 0)
          .map((it) => {
                'productId': it.productId,
                'qty': _returnQuantities[it.productId]!,
                'refundCentimes': _returnQuantities[it.productId]! * it.unitPriceCentimes,
              })
          .toList();

      final result = await ref.read(posCartProvider.notifier).processReturn(
            originalOrderId: _fetchedOrder!.id,
            cashierId: user?.id ?? '11111111-1111-1111-1111-111111111111',
            returnItems: returnItemsList,
            totalRefundCentimes: _calculatedRefundTotalCentimes,
            reason: _reasons[_selectedReason] ?? _selectedReason,
            restockInventory: _restockInventory,
          );

      if (result.isSuccess) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تسجيل عملية الإرجاع وإعادة ${_restockInventory ? "الكميات للمخزون واسترجاع المبلغ" : "المبلغ للزبون"} بنجاح!'),
            backgroundColor: context.appColors.success,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.failure?.message ?? 'فشلت عملية الإرجاع'),
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

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment_return_rounded, size: 28),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'إرجاع واستبدال المبيعات [F9]',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _orderIdController,
                      decoration: const InputDecoration(
                        hintText: 'امسح باركود الوصل أو أدخل معرّف الطلب...',
                        prefixIcon: Icon(Icons.qr_code_scanner),
                      ),
                      onSubmitted: (_) => _fetchOrder(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _fetchOrder,
                    icon: const Icon(Icons.search),
                    label: const Text('تحقق وجلب الوصل'),
                  ),
                ],
              ),
              AppSpacing.gapMd,
              if (_isLoading)
                const Expanded(child: AppLoadingView(message: 'جاري التحقق من الوصل والمنتجات...'))
              else if (_errorMessage != null)
                Expanded(child: AppErrorView(message: _errorMessage!, onRetry: _fetchOrder))
              else if (_fetchedOrder != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainer,
                            borderRadius: AppRadius.mdAll,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'رقم الوصل: #${_fetchedOrder!.orderNumber ?? _fetchedOrder!.id.substring(0, 8)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text('التاريخ: ${_fetchedOrder!.createdAt.toString().substring(0, 16)}',
                                      style: theme.textTheme.bodySmall),
                                ],
                              ),
                              DzdPriceTag(
                                centimes: _fetchedOrder!.totalAmountCentimes,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                        AppSpacing.gapMd,
                        Text(
                          'حدد المنتجات والكميات المراد إرجاعها:',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        AppSpacing.gapSm,
                        ..._fetchedOrder!.items.map((it) {
                          final returnQty = _returnQuantities[it.productId] ?? 0;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(it.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text('الكمية المشتراة: ${it.quantity} | سعر الوحدة: ${DzdFormatter.formatCentimes(it.unitPriceCentimes)}',
                                            style: theme.textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline),
                                        onPressed: returnQty > 0
                                            ? () => setState(() => _returnQuantities[it.productId] = returnQty - 1)
                                            : null,
                                      ),
                                      Text('$returnQty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline),
                                        onPressed: returnQty < it.quantity
                                            ? () => setState(() => _returnQuantities[it.productId] = returnQty + 1)
                                            : null,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  SizedBox(
                                    width: 90,
                                    child: DzdPriceTag(
                                      centimes: returnQty * it.unitPriceCentimes,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: returnQty > 0 ? theme.colorScheme.error : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        AppSpacing.gapLg,
                        DropdownButtonFormField<String>(
                          initialValue: _selectedReason,
                          decoration: const InputDecoration(
                            labelText: 'سبب الإرجاع الإلزامي (سجل التدقيق) *',
                            prefixIcon: Icon(Icons.help_outline),
                          ),
                          items: _reasons.entries.map((e) {
                            return DropdownMenuItem(value: e.key, child: Text(e.value));
                          }).toList(),
                          onChanged: (v) => v != null ? setState(() => _selectedReason = v) : null,
                        ),
                        AppSpacing.gapMd,
                        CheckboxListTile(
                          title: const Text('إعادة المنتجات المسترجعة إلى المخزون المتاح تلقائيًا'),
                          subtitle: const Text('قم بإلغاء التحديد إذا كانت المنتجات تالفة أو غير صالحة للبيع'),
                          value: _restockInventory,
                          onChanged: (v) => setState(() => _restockInventory = v ?? true),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Expanded(
                  child: AppEmptyView(
                    icon: Icons.barcode_reader,
                    title: 'امسح باركود الوصل',
                    description: 'يرجى مسح الباركود المطبوع على وصل البيع أو إدخال رقمه للبدء في إجراءات الإرجاع.',
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إجمالي المبلغ المسترجع للزبون:', style: TextStyle(fontWeight: FontWeight.bold)),
                      DzdPriceTag(
                        centimes: _calculatedRefundTotalCentimes,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: (_fetchedOrder == null || _calculatedRefundTotalCentimes <= 0 || _isSubmitting)
                        ? null
                        : _handleConfirmReturn,
                    icon: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                        : const Icon(Icons.check_circle),
                    label: Text(_isSubmitting ? 'جاري التسجيل...' : 'تأكيد الإرجاع واسترداد المبلغ'),
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
