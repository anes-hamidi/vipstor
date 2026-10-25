import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';
import '../models/pos_models.dart';

/// A responsive, high-fidelity screen for configuring discounts on cart items (percentage or fixed amount).
class ItemDiscountDialog extends StatefulWidget {
  final PosCartItem item;

  const ItemDiscountDialog({super.key, required this.item});

  /// Opens the item discount screen as a dedicated fullscreen screen route.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required PosCartItem item,
  }) {
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ItemDiscountDialog(item: item),
      ),
    );
  }

  @override
  State<ItemDiscountDialog> createState() => _ItemDiscountDialogState();
}

class _ItemDiscountDialogState extends State<ItemDiscountDialog> {
  late TextEditingController _percentController;
  late TextEditingController _fixedController;
  bool _isPercentageMode = true;

  @override
  void initState() {
    super.initState();
    _percentController = TextEditingController(
      text: widget.item.discountPercent > 0
          ? widget.item.discountPercent.toStringAsFixed(1)
          : '',
    );
    _fixedController = TextEditingController(
      text: widget.item.manualDiscountCentimes > 0
          ? (widget.item.manualDiscountCentimes / 100).toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _percentController.dispose();
    _fixedController.dispose();
    super.dispose();
  }

  void _apply() {
    if (_isPercentageMode) {
      final p = double.tryParse(_percentController.text.trim()) ?? 0.0;
      Navigator.pop(context, {'percent': p, 'fixed': 0});
    } else {
      final f = double.tryParse(_fixedController.text.trim()) ?? 0.0;
      Navigator.pop(context, {'percent': 0.0, 'fixed': (f * 100).round()});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final role = context.roleTheme;
    final brand = role.roleBrandColor;

    final baseUnitPrice = widget.item.baseUnitPriceCentimes;
    final qty = widget.item.quantity;
    final originalLineTotal = baseUnitPrice * qty;

    int newUnitPrice = baseUnitPrice;
    int savingsTotal = 0;

    if (_isPercentageMode) {
      final p = double.tryParse(_percentController.text.trim()) ?? 0.0;
      final discountUnit = (baseUnitPrice * (p / 100.0)).round();
      newUnitPrice = (baseUnitPrice - discountUnit).clamp(0, baseUnitPrice);
      savingsTotal = (discountUnit * qty);
    } else {
      final f = double.tryParse(_fixedController.text.trim()) ?? 0.0;
      final discountUnit = (f * 100).round();
      newUnitPrice = (baseUnitPrice - discountUnit).clamp(0, baseUnitPrice);
      savingsTotal = (discountUnit * qty);
    }

    final finalLineTotal = (newUnitPrice * qty);

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
                    child: Icon(Icons.discount_rounded,
                        size: 20, color: role.badgeText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تخفيض: ${widget.item.nameAr}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      Text(
                        'تطبيق خصم مباشر على مستوى الصنف بالوصل',
                        style:
                            theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Item details card
                    LuxuryCard(
                      goldAccent: true,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.item.nameAr,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                '${widget.item.quantity} ${widget.item.unit.label}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text('السعر الأصلي للوحدة:'),
                              ),
                              DzdPriceTag(
                                  centimes: widget.item.baseUnitPriceCentimes),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text('الإجمالي الأصلي قبل التخفيض:'),
                              ),
                              DzdPriceTag(
                                centimes: originalLineTotal,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapLg,

                    // Mode Toggle (Percentage % vs Fixed Amount)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('نسبة مئوية (%)'),
                          icon: Icon(Icons.percent_rounded, size: 18),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('مبلغ مالي ثابت (دج)'),
                          icon: Icon(Icons.money_off_rounded, size: 18),
                        ),
                      ],
                      selected: {_isPercentageMode},
                      onSelectionChanged: (set) =>
                          setState(() => _isPercentageMode = set.first),
                    ),
                    AppSpacing.gapLg,

                    // Discount Input
                    if (_isPercentageMode) ...[
                      TextField(
                        controller: _percentController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'نسبة التخفيض (%) *',
                          prefixIcon: const Icon(Icons.percent_rounded),
                          suffixText: '%',
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          border:
                              const OutlineInputBorder(borderRadius: AppRadius.mdAll),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      AppSpacing.gapSm,
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [5, 10, 15, 20, 25, 50].map((val) {
                          return ActionChip(
                            label: Text('$val%'),
                            onPressed: () {
                              setState(() {
                                _percentController.text = val.toString();
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ] else ...[
                      TextField(
                        controller: _fixedController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'قيمة التخفيض المباشر للوحدة (دج) *',
                          prefixIcon: const Icon(Icons.attach_money_rounded),
                          suffixText: 'دج',
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                          border:
                              const OutlineInputBorder(borderRadius: AppRadius.mdAll),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      AppSpacing.gapSm,
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [50, 100, 200, 500, 1000].map((val) {
                          return ActionChip(
                            label: Text('$val دج'),
                            onPressed: () {
                              setState(() {
                                _fixedController.text = val.toString();
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],

                    AppSpacing.gapXl,

                    // Real-time Preview Calculation Card
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: colors.successContainer.withValues(alpha: 0.35),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(color: colors.success),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text('سعر الوحدة بعد التخفيض:'),
                              ),
                              DzdPriceTag(
                                centimes: newUnitPrice,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text('إجمالي قيمة الخصم الممنوح:'),
                              ),
                              DzdPriceTag(
                                centimes: savingsTotal,
                                color: colors.success,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'الإجمالي النهائي للبند:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              DzdPriceTag(
                                centimes: finalLineTotal,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    AppSpacing.gapXl,

                    GoldButton.icon(
                      onPressed: _apply,
                      icon: Icons.check_circle_rounded,
                      label: 'تطبيق التخفيض على البند [Enter]',
                    ),
                    AppSpacing.gapSm,
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
