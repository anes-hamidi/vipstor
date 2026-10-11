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
    _paidCashController = TextEditingController(
      text: (widget.totalCentimes / 100.0).toStringAsFixed(0),
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
      _paidCashController.text = dzd.toStringAsFixed(0);
      if (_paidCentimes >= widget.totalCentimes) {
        _paymentMode = PosPaymentMode.cash;
      } else if (_paidCentimes == 0) {
        _paymentMode = PosPaymentMode.credit;
      } else {
        _paymentMode = PosPaymentMode.mixed;
      }
    });
  }

  void _handleConfirm() {
    final customer = ref.read(posActiveCustomerProvider);
    final cashToPay = _paidCentimes > widget.totalCentimes ? widget.totalCentimes : _paidCentimes;
    final onAccount = widget.totalCentimes > _paidCentimes ? (widget.totalCentimes - _paidCentimes) : 0;

    if (onAccount > 0 && customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('المبلغ المتبقي دين! يجب تحديد حساب زبون مسجل للبيع على الحساب.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (onAccount > 0 && customer != null && customer.isCreditExceeded(onAccount)) {
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

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsetsDirectional.all(6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(Icons.shopping_cart_checkout_rounded, color: colorScheme.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Text('إتمام الدفع وتحصيل الوصل (Encaisser)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
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
                  color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('المبلغ الإجمالي المستحق:', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                        DzdPriceTag(
                          centimes: widget.totalCentimes,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    if (customer != null)
                      Container(
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: AppRadius.pillAll,
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person, size: 14, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              customer.name,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              AppSpacing.gapMd,
              // Payment Mode Segmented Button
              SegmentedButton<PosPaymentMode>(
                segments: const [
                  ButtonSegment<PosPaymentMode>(
                    value: PosPaymentMode.cash,
                    label: Text('دفع نقدًا (Espèces)'),
                    icon: Icon(Icons.payments_outlined, size: 16),
                  ),
                  ButtonSegment<PosPaymentMode>(
                    value: PosPaymentMode.credit,
                    label: Text('على الحساب (Crédit)'),
                    icon: Icon(Icons.credit_card_outlined, size: 16),
                  ),
                  ButtonSegment<PosPaymentMode>(
                    value: PosPaymentMode.mixed,
                    label: Text('دفع مجزأ (Mixte)'),
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
                      _paidCashController.text = (widget.totalCentimes / 100.0).toStringAsFixed(0);
                    } else if (mode == PosPaymentMode.credit) {
                      _paidCentimes = 0;
                      _paidCashController.text = '0';
                    }
                  });
                },
              ),
              AppSpacing.gapMd,
              // Paid Cash Input Field
              TextField(
                controller: _paidCashController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    avatar: const Icon(Icons.check, size: 14),
                    label: const Text('المبلغ كاملًا'),
                    onPressed: () => _setCashAmount(widget.totalCentimes / 100.0),
                  ),
                  ...[500, 1000, 2000, 3000, 5000, 10000].map((val) {
                    return ActionChip(
                      label: Text('$val دج'),
                      onPressed: () => _setCashAmount(val.toDouble()),
                    );
                  }),
                ],
              ),
              AppSpacing.gapMd,
              // Change / Remaining Debt Result Box
              Container(
                padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: difference >= 0 ? colors.successContainer : colors.warningContainer,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: difference >= 0 ? colors.success : colors.warning),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          difference >= 0 ? Icons.monetization_on_outlined : Icons.pending_actions_outlined,
                          color: difference >= 0 ? colors.onSuccessContainer : colors.onWarningContainer,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          difference >= 0 ? 'المتبقي للزبون (الصرف):' : 'المتبقي كدين (على الحساب):',
                          style: TextStyle(
                            color: difference >= 0 ? colors.onSuccessContainer : colors.onWarningContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    DzdPriceTag(
                      centimes: difference.abs(),
                      color: difference >= 0 ? colors.onSuccessContainer : colors.onWarningContainer,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _handleConfirm,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(
            isCreditNeeded ? 'تأكيد وترحيل الدين للزبون' : 'تأكيد وطباعة الوصل',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
