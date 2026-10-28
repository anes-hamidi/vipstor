import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../../common/widgets/headless_barcode_scanner_button.dart';
import '../../common/services/headless_barcode_scanner_service.dart';

/// A responsive, high-fidelity screen for searching sales receipts, processing returns, and restocking items.
class SalesReturnDialog extends ConsumerStatefulWidget {
  final String? initialOrderId;

  const SalesReturnDialog({super.key, this.initialOrderId});

  /// Opens the sales return screen as a dedicated fullscreen screen route.
  static Future<void> show(BuildContext context, {String? initialOrderId}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SalesReturnDialog(initialOrderId: initialOrderId),
      ),
    );
  }

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
    HeadlessBarcodeScannerService.instance.stopScanning();
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

  void _returnAllItems() {
    if (_fetchedOrder == null) return;
    setState(() {
      for (final it in _fetchedOrder!.items) {
        _returnQuantities[it.productId] = it.quantity;
      }
    });
  }

  void _resetReturnItems() {
    setState(() {
      _returnQuantities.clear();
    });
  }

  Future<String?> _promptCashierPin() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد رمز PIN'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'رمز PIN الحالي',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    return (pin == null || pin.trim().isEmpty) ? null : pin.trim();
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

    final user = ref.read(authStateProvider);
    if (user == null) return;
    final pin = await _promptCashierPin();
    if (!mounted || pin == null) return;

    setState(() => _isSubmitting = true);
    try {
      final returnItemsList = _fetchedOrder!.items
          .where((it) => (_returnQuantities[it.productId] ?? 0) > 0)
          .map((it) => {
                'productId': it.productId,
                'qty': _returnQuantities[it.productId]!,
                'refundCentimes':
                    _returnQuantities[it.productId]! * it.unitPriceCentimes,
              })
          .toList();

      final result = await ref.read(posCartProvider.notifier).processReturn(
            originalOrderId: _fetchedOrder!.id,
            cashierId: user.id,
            callerPin: pin,
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
            content: Text(
                'تم تسجيل عملية الإرجاع وإعادة ${_restockInventory ? "الكميات للمخزون واسترجاع المبلغ" : "المبلغ للزبون"} بنجاح!'),
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
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final role = context.roleTheme;
    final brand = role.roleBrandColor;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 2,
            backgroundColor: colorScheme.surfaceContainer,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'رجوع [Esc]',
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: role.badgeBackground,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: brand.withValues(alpha: 0.30)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.assignment_return_rounded,
                        size: 20, color: role.badgeText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'إرجاع واستبدال المبيعات [F9]',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'إرجاع المنتجات، استرداد المبالغ النقدية وإعادة المخزون',
                        style:
                            theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (_fetchedOrder != null)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(end: AppSpacing.md),
                  child: Chip(
                    label: Text(
                        'وصل #${_fetchedOrder!.orderNumber ?? _fetchedOrder!.id.substring(0, 8)}'),
                    backgroundColor: brand.withValues(alpha: 0.12),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              // Search and Barcode Header
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                color: colorScheme.surfaceContainerLow,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _orderIdController,
                            decoration: InputDecoration(
                              hintText:
                                  'امسح باركود الوصل بالكاميرا أو أدخل معرّف الطلب...',
                              prefixIcon:
                                  const Icon(Icons.qr_code_scanner_rounded),
                              suffixIcon: HeadlessBarcodeScannerButton(
                                controller: _orderIdController,
                                onScanned: (_) => _fetchOrder(),
                                tooltip: 'مسح باركود الوصل بالكاميرا',
                              ),
                              filled: true,
                              fillColor: colorScheme.surfaceContainer,
                              border: const OutlineInputBorder(
                                  borderRadius: AppRadius.mdAll),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                            onSubmitted: (_) => _fetchOrder(),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _fetchOrder,
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('تحقق وجلب الوصل'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              // Body Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: AppLoadingView(
                            message: 'جاري التحقق من الوصل والمنتجات...'),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: AppErrorView(
                              message: _errorMessage!,
                              onRetry: _fetchOrder,
                            ),
                          )
                        : _fetchedOrder != null
                            ? _buildReturnWorkspace(
                                theme, colorScheme, colors, role, brand)
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.barcode_reader,
                                      size: 64,
                                      color: colorScheme.outlineVariant,
                                    ),
                                    AppSpacing.gapMd,
                                    Text(
                                      'امسح باركود الوصل لبدء الإرجاع',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'يرجى استخدام قارئ الباركود أو إدخال رقم الوصل يدويًا أعلاه',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReturnWorkspace(ThemeData theme, ColorScheme colorScheme,
      dynamic colors, dynamic role, Color brand) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: Configuration, Reason, Restock, Refund Summary & Confirmation
              SizedBox(
                width: 380,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    border: BorderDirectional(
                      end: BorderSide(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildOrderSummaryCard(theme, brand, role),
                        AppSpacing.gapLg,
                        DropdownButtonFormField<String>(
                          initialValue: _selectedReason,
                          decoration: InputDecoration(
                            labelText: 'سبب الإرجاع الإلزامي (سجل التدقيق) *',
                            prefixIcon: const Icon(Icons.help_outline_rounded),
                            filled: true,
                            fillColor: colorScheme.surfaceContainer,
                            border:
                                const OutlineInputBorder(borderRadius: AppRadius.mdAll),
                          ),
                          items: _reasons.entries.map((e) {
                            return DropdownMenuItem(
                                value: e.key, child: Text(e.value));
                          }).toList(),
                          onChanged: (v) => v != null
                              ? setState(() => _selectedReason = v)
                              : null,
                        ),
                        AppSpacing.gapMd,
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'إعادة المواد للمخزون تلقائيًا',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'ألغِ التحديد إذا كانت المواد تالفة أو غير صالحة للبيع مجددًا',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: _restockInventory,
                          onChanged: (v) =>
                              setState(() => _restockInventory = v ?? true),
                        ),
                        AppSpacing.gapLg,
                        _buildRefundTotalCard(theme, colorScheme, colors),
                        AppSpacing.gapLg,
                        GoldButton.icon(
                          onPressed: (_calculatedRefundTotalCentimes <= 0 ||
                                  _isSubmitting)
                              ? null
                              : _handleConfirmReturn,
                          icon: _isSubmitting
                              ? Icons.hourglass_top_rounded
                              : Icons.check_circle_rounded,
                          label: _isSubmitting
                              ? 'جاري التسجيل...'
                              : 'تأكيد الإرجاع واسترداد المبلغ',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Right: Selected Items and Steppers
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 750),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'حدد المنتجات والكميات المراد إرجاعها:',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: _returnAllItems,
                                    child: const Text('إرجاع كامل الوصل'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: _resetReturnItems,
                                    child: const Text('إلغاء التحديد'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          AppSpacing.gapMd,
                          _buildItemsList(theme, colorScheme),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        // Mobile Layout: Single-column scroll
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOrderSummaryCard(theme, brand, role),
              AppSpacing.gapMd,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'المنتجات المسترجعة:',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: _returnAllItems,
                    child: const Text('إرجاع الكل'),
                  ),
                ],
              ),
              AppSpacing.gapSm,
              _buildItemsList(theme, colorScheme),
              AppSpacing.gapLg,
              DropdownButtonFormField<String>(
                initialValue: _selectedReason,
                decoration: const InputDecoration(
                  labelText: 'سبب الإرجاع الإلزامي *',
                  prefixIcon: Icon(Icons.help_outline),
                ),
                items: _reasons.entries.map((e) {
                  return DropdownMenuItem(value: e.key, child: Text(e.value));
                }).toList(),
                onChanged: (v) =>
                    v != null ? setState(() => _selectedReason = v) : null,
              ),
              AppSpacing.gapSm,
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إعادة المواد للمخزون المتاح تلقائيًا'),
                value: _restockInventory,
                onChanged: (v) =>
                    setState(() => _restockInventory = v ?? true),
              ),
              AppSpacing.gapMd,
              _buildRefundTotalCard(theme, colorScheme, colors),
              AppSpacing.gapLg,
              GoldButton.icon(
                onPressed: (_calculatedRefundTotalCentimes <= 0 || _isSubmitting)
                    ? null
                    : _handleConfirmReturn,
                icon: Icons.check_circle_rounded,
                label: _isSubmitting ? 'جاري التسجيل...' : 'تأكيد الإرجاع',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderSummaryCard(
      ThemeData theme, Color brand, dynamic role) {
    final o = _fetchedOrder!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: role.badgeBackground,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: brand.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'وصل #${o.orderNumber ?? o.id.substring(0, 8)}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              DzdPriceTag(
                centimes: o.totalAmountCentimes,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const Divider(height: 16),
          Text(
            'تاريخ الوصل: ${o.createdAt.toString().substring(0, 16)}',
            style: theme.textTheme.bodySmall,
          ),
          if (o.customerName != null) ...[
            const SizedBox(height: 4),
            Text(
              'الزبون: ${o.customerName}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRefundTotalCard(
      ThemeData theme, ColorScheme colorScheme, dynamic colors) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.monetization_on_rounded, color: colorScheme.error),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'المبلغ المسترجع للزبون:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          DzdPriceTag(
            centimes: _calculatedRefundTotalCentimes,
            color: colorScheme.error,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(ThemeData theme, ColorScheme colorScheme) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _fetchedOrder!.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, idx) {
        final it = _fetchedOrder!.items[idx];
        final returnQty = _returnQuantities[it.productId] ?? 0;
        final isSelected = returnQty > 0;

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.15)
                : colorScheme.surfaceContainer,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'المشترى: ${it.formattedQuantityWithUnit} • سعر الوحدة: ${DzdFormatter.formatCentimes(it.unitPriceCentimes)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove, size: 16),
                    onPressed: returnQty > 0
                        ? () => setState(() =>
                            _returnQuantities[it.productId] = returnQty - 1)
                        : null,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                    ),
                  ),
                  Container(
                    width: 44,
                    alignment: Alignment.center,
                    child: Text(
                      '$returnQty',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: returnQty < it.quantity
                        ? () => setState(() =>
                            _returnQuantities[it.productId] = returnQty + 1)
                        : null,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 90,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: DzdPriceTag(
                    centimes: returnQty * it.unitPriceCentimes,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: returnQty > 0 ? theme.colorScheme.error : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
