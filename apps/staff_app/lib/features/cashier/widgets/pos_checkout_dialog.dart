import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';

enum PosPaymentMode { cash, credit, mixed }

class PosCheckoutDialog extends ConsumerStatefulWidget {
  final int totalCentimes;

  const PosCheckoutDialog({
    super.key,
    required this.totalCentimes,
  });

  @override
  ConsumerState<PosCheckoutDialog> createState() => _PosCheckoutDialogState();
}

class _PosCheckoutDialogState extends ConsumerState<PosCheckoutDialog> {
  late TextEditingController _paidCashController;
  late int _paidCentimes;
  PosPaymentMode _paymentMode = PosPaymentMode.cash;
  bool _autoPrint = true;

  @override
  void initState() {
    super.initState();
    _paidCentimes = widget.totalCentimes;
    final initialText = (widget.totalCentimes / 100.0).toStringAsFixed(0);
    _paidCashController = TextEditingController(text: initialText);
    _paidCashController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initialText.length,
    );
  }

  @override
  void dispose() {
    _paidCashController.dispose();
    super.dispose();
  }

  void _setCashAmount(double dzd) {
    setState(() {
      _paidCentimes = (dzd * 100).round();
      final text = dzd.toStringAsFixed(0);
      _paidCashController.text = text;
      _paidCashController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
      if (_paidCentimes >= widget.totalCentimes) {
        _paymentMode = PosPaymentMode.cash;
      } else if (_paidCentimes == 0) {
        _paymentMode = PosPaymentMode.credit;
      } else {
        _paymentMode = PosPaymentMode.mixed;
      }
    });
  }

  void _addCashAmount(double dzd) {
    final currentDzd = (_paidCentimes / 100.0);
    _setCashAmount(currentDzd + dzd);
  }

  void _handleConfirm() {
    final customer = ref.read(posActiveCustomerProvider);
    final cashToPay = _paidCentimes > widget.totalCentimes
        ? widget.totalCentimes
        : _paidCentimes;
    final onAccount = widget.totalCentimes > _paidCentimes
        ? (widget.totalCentimes - _paidCentimes)
        : 0;

    if (onAccount > 0 && customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'المبلغ المتبقي دين! يجب تحديد حساب زبون مسجل للبيع على الحساب.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (onAccount > 0 &&
        customer != null &&
        customer.isCreditExceeded(onAccount)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تجاوز سقف الائتمان! السقف: ${DzdFormatter.formatCentimes(customer.creditLimitCentimes)}, الدين الحالي: ${DzdFormatter.formatCentimes(customer.currentDebtCentimes)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'paidCash': cashToPay,
      'onAccount': onAccount,
      'autoPrint': _autoPrint,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final customer = ref.watch(posActiveCustomerProvider);
    final difference = _paidCentimes - widget.totalCentimes;
    final isCreditNeeded = difference < 0;
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: const Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              borderRadius: AppRadius.smAll,
              boxShadow: [AppShadows.goldGlowSm],
            ),
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.shopping_cart_checkout_rounded,
                  color: Color(0xFF1A1400), size: 20),
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Text('إتمام الدفع وتحصيل الوصل',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ],
      ),
      content: SingleChildScrollView(
        child: ContentConstrainedBox.form(
          maxWidth: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Total Due Banner
              Container(
                padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                decoration: BoxDecoration(
                  gradient: Theme.of(context).brightness == Brightness.dark
                      ? AppGradients.darkGlass
                      : AppGradients.goldSubtleLight,
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: const [AppShadows.goldGlowSm],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('المبلغ الإجمالي المستحق:',
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFFB8A882)
                                    : const Color(0xFF9A8A60))),
                        DzdPriceTag.hero(
                            centimes: widget.totalCentimes, gold: true),
                      ],
                    ),
                    if (customer != null)
                      Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFD4AF37).withValues(alpha: 0.12),
                          borderRadius: AppRadius.pillAll,
                          border: Border.all(
                            color:
                                const Color(0xFFD4AF37).withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_rounded,
                                size: 13, color: Color(0xFFD4AF37)),
                            const SizedBox(width: 4),
                            Text(customer.name,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              // Payment Mode Segmented Button - clean, responsive labels
              SegmentedButton<PosPaymentMode>(
                segments: const [
                  ButtonSegment<PosPaymentMode>(
                    value: PosPaymentMode.cash,
                    label: Text('نقدًا'),
                    icon: Icon(Icons.payments_outlined, size: 16),
                  ),
                  ButtonSegment<PosPaymentMode>(
                    value: PosPaymentMode.credit,
                    label: Text('دين'),
                    icon: Icon(Icons.credit_card_outlined, size: 16),
                  ),
                  ButtonSegment<PosPaymentMode>(
                    value: PosPaymentMode.mixed,
                    label: Text('مجزأ'),
                    icon: Icon(Icons.call_split_rounded, size: 16),
                  ),
                ],
                selected: {_paymentMode},
                onSelectionChanged: (set) {
                  final mode = set.first;
                  setState(() {
                    _paymentMode = mode;
                    if (mode == PosPaymentMode.cash) {
                      _paidCentimes = widget.totalCentimes;
                      final text =
                          (widget.totalCentimes / 100.0).toStringAsFixed(0);
                      _paidCashController.text = text;
                      _paidCashController.selection = TextSelection(
                          baseOffset: 0, extentOffset: text.length);
                    } else if (mode == PosPaymentMode.credit) {
                      _paidCentimes = 0;
                      _paidCashController.text = '0';
                      _paidCashController.selection =
                          const TextSelection(baseOffset: 0, extentOffset: 1);
                    }
                  });
                },
              ),
              AppSpacing.gapMd,
              // Paid Cash Input Field with auto-select on tap
              TextField(
                controller: _paidCashController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                onTap: () {
                  _paidCashController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _paidCashController.text.length,
                  );
                },
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'المبلغ المستلم نقدًا من الزبون (دج) [Enter]',
                  prefixIcon: const Icon(Icons.money_rounded),
                  suffixText: 'دج',
                  suffixStyle: const TextStyle(fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLow,
                ),
                onChanged: (val) {
                  final clean = val.replaceAll(' ', '').trim();
                  final parsed = double.tryParse(clean) ?? 0.0;
                  setState(() {
                    _paidCentimes = (parsed * 100).round();
                    if (_paidCentimes >= widget.totalCentimes) {
                      _paymentMode = PosPaymentMode.cash;
                    } else if (_paidCentimes == 0) {
                      _paymentMode = PosPaymentMode.credit;
                    } else {
                      _paymentMode = PosPaymentMode.mixed;
                    }
                  });
                },
                onSubmitted: (_) => _handleConfirm(),
              ),
              AppSpacing.gapSm,
              // Fast Algerian Currency Buttons
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.done_all_rounded, size: 14),
                    label: const Text('كامل المبلغ'),
                    onPressed: () =>
                        _setCashAmount(widget.totalCentimes / 100.0),
                    backgroundColor: isDark
                        ? const Color(0xFF1A1400)
                        : const Color(0xFFD4AF37),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.clear_rounded, size: 14),
                    label: const Text('0 دج (دين)'),
                    onPressed: () => _setCashAmount(0),
                    backgroundColor: isDark
                        ? const Color(0xFF1A1400)
                        : const Color(0xFFD4AF37),
                  ),
                  ...[500, 1000, 2000, 5000, 10000].map((val) {
                    return ActionChip(
                      label: Text('$val'),
                      onPressed: () => _setCashAmount(val.toDouble()),
                      backgroundColor: isDark 
                          ? const Color(0xFF1A1400)
                          : const Color(0xFFD4AF37)
                    );
                  }),
               
               
                ],
              ),
              AppSpacing.gapMd,
              // Missing Customer Alert if credit needed
              if (isCreditNeeded && customer == null) ...[
                Container(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smAll,
                    border:
                        Border.all(color: colors.error.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: colors.error),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'تنبيه: البيع بالدين أو الحساب المجزأ يتطلب اختيار زبون مسجل.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapSm,
              ],
              // Change / Remaining Debt Result Box
              Container(
                padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: difference >= 0
                      ? colors.successContainer
                      : colors.warningContainer,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                      color: difference >= 0 ? colors.success : colors.warning),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          Icon(
                            difference >= 0
                                ? Icons.monetization_on_outlined
                                : Icons.pending_actions_outlined,
                            color: difference >= 0
                                ? colors.onSuccessContainer
                                : colors.onWarningContainer,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            difference >= 0
                                ? 'المتبقي للزبون:'
                                : 'المتبقي كدين:',
                            style: TextStyle(
                              color: difference >= 0
                                  ? colors.onSuccessContainer
                                  : colors.onWarningContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ), // closes Flexible
                    DzdPriceTag(
                      centimes: difference.abs(),
                      color: difference >= 0
                          ? colors.onSuccessContainer
                          : colors.onWarningContainer,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              AppSpacing.gapSm,
              // Print Toggle
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('طباعة الوصل الحراري 80mm فورًا'),
                value: _autoPrint,
                onChanged: (v) => setState(() => _autoPrint = v ?? true),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        GoldButton.icon(
          icon: Icons.check_circle_rounded,
          label: isCreditNeeded ? 'تأكيد وترحيل الدين' : 'تأكيد وطباعة الوصل',
          onPressed: _handleConfirm,
        ),
      ],
    );
  }
}
