import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';

enum PosPaymentMode { cash, credit, mixed }

/// A responsive, high-fidelity screen for cashier checkout, split payments, and receipt generation.
class PosCheckoutDialog extends ConsumerStatefulWidget {
  final int totalCentimes;

  const PosCheckoutDialog({
    super.key,
    required this.totalCentimes,
  });

  /// Opens the POS checkout as a dedicated fullscreen screen route.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int totalCentimes,
  }) {
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PosCheckoutDialog(totalCentimes: totalCentimes),
      ),
    );
  }

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
      _syncPaymentMode();
    });
  }

  void _appendKeypad(String digit) {
    setState(() {
      String current = _paidCashController.text.trim();
      if (current == '0') current = '';
      final updated = current + digit;
      final parsed = double.tryParse(updated) ?? 0.0;
      _paidCashController.text = updated;
      _paidCentimes = (parsed * 100).round();
      _syncPaymentMode();
    });
  }

  void _backspaceKeypad() {
    setState(() {
      String current = _paidCashController.text.trim();
      if (current.isNotEmpty) {
        current = current.substring(0, current.length - 1);
      }
      if (current.isEmpty) current = '0';
      final parsed = double.tryParse(current) ?? 0.0;
      _paidCashController.text = current;
      _paidCentimes = (parsed * 100).round();
      _syncPaymentMode();
    });
  }

  void _clearKeypad() {
    setState(() {
      _paidCashController.text = '0';
      _paidCentimes = 0;
      _syncPaymentMode();
    });
  }

  void _syncPaymentMode() {
    if (_paidCentimes >= widget.totalCentimes) {
      _paymentMode = PosPaymentMode.cash;
    } else if (_paidCentimes == 0) {
      _paymentMode = PosPaymentMode.credit;
    } else {
      _paymentMode = PosPaymentMode.mixed;
    }
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
            'المبلغ المتبقي دين! يجب تحديد حساب زبون مسجل للبيع على الحساب.',
          ),
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
    final role = context.roleTheme;
    final brand = role.roleBrandColor;
    final customer = ref.watch(posActiveCustomerProvider);
    final difference = _paidCentimes - widget.totalCentimes;
    final isCreditNeeded = difference < 0;

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
                    child: Icon(Icons.point_of_sale_rounded,
                        color: role.badgeText, size: 20),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إتمام الدفع وتحصيل الوصل',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'شاشة تحصيل الدفع - نقطة البيع',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'رجوع [Esc]',
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (customer != null)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(end: AppSpacing.md),
                  child: Chip(
                    avatar:
                        Icon(Icons.person_rounded, size: 16, color: brand),
                    label: Text(
                      customer.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: brand.withValues(alpha: 0.12),
                    side: BorderSide(color: brand.withValues(alpha: 0.25)),
                  ),
                ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 820;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Summary and Confirmation Sidebar (Desktop/Tablet left side)
                    SizedBox(
                      width: 380,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          border: BorderDirectional(
                            end: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildDueBanner(theme, role, brand, customer),
                              AppSpacing.gapLg,
                              if (customer != null) ...[
                                _buildCustomerLedgerCard(customer, theme, colors),
                                AppSpacing.gapMd,
                              ],
                              _buildDifferenceResultCard(difference, colors),
                              AppSpacing.gapMd,
                              Material(
                                color: Colors.transparent,
                                child: CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'طباعة الوصل الحراري 80mm فورًا',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: const Text(
                                    'إرسال أمر الطباعة عبر بروتوكول ESC/POS',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  secondary: const Icon(Icons.print_rounded),
                                  value: _autoPrint,
                                  onChanged: (v) =>
                                      setState(() => _autoPrint = v ?? true),
                                ),
                              ),
                              AppSpacing.gapLg,
                              GoldButton.icon(
                                icon: Icons.check_circle_rounded,
                                label: isCreditNeeded
                                    ? 'تأكيد وترحيل الدين'
                                    : 'تأكيد وطباعة الوصل [Enter]',
                                onPressed: _handleConfirm,
                              ),
                              AppSpacing.gapSm,
                              OutlinedButton.icon(
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('إلغاء والعودة للطلب'),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Payment Inputs and Touch Keypad
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 580),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildModeSelector(),
                                AppSpacing.gapLg,
                                _buildCashInputField(colorScheme),
                                AppSpacing.gapMd,
                                _buildQuickDenominationChips(role),
                                AppSpacing.gapLg,
                                if (isCreditNeeded && customer == null) ...[
                                  _buildMissingCustomerAlert(colors),
                                  AppSpacing.gapMd,
                                ],
                                _buildVirtualKeypad(colorScheme, brand),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // Mobile Layout: Single column scroll with bottom bar
              return SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDueBanner(theme, role, brand, customer),
                    AppSpacing.gapMd,
                    _buildModeSelector(),
                    AppSpacing.gapMd,
                    _buildCashInputField(colorScheme),
                    AppSpacing.gapSm,
                    _buildQuickDenominationChips(role),
                    AppSpacing.gapMd,
                    _buildDifferenceResultCard(difference, colors),
                    if (isCreditNeeded && customer == null) ...[
                      AppSpacing.gapMd,
                      _buildMissingCustomerAlert(colors),
                    ],
                    AppSpacing.gapMd,
                    _buildVirtualKeypad(colorScheme, brand),
                    AppSpacing.gapMd,
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('طباعة الوصل الحراري 80mm فورًا'),
                      value: _autoPrint,
                      onChanged: (v) => setState(() => _autoPrint = v ?? true),
                    ),
                    AppSpacing.gapLg,
                    GoldButton.icon(
                      icon: Icons.check_circle_rounded,
                      label: isCreditNeeded
                          ? 'تأكيد وترحيل الدين'
                          : 'تأكيد وطباعة الوصل',
                      onPressed: _handleConfirm,
                    ),
                    AppSpacing.gapSm,
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDueBanner(
      ThemeData theme, dynamic role, Color brand, CustomerProfileEntity? customer) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: role.badgeBackground,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: brand.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: brand.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المبلغ الإجمالي المطلوب:',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: role.badgeText.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.receipt_long_rounded, size: 18),
            ],
          ),
          const SizedBox(height: 4),
          DzdPriceTag.hero(centimes: widget.totalCentimes, gold: true),
        ],
      ),
    );
  }

  Widget _buildCustomerLedgerCard(
      CustomerProfileEntity customer, ThemeData theme, dynamic colors) {
    final remainingCredit = customer.creditLimitCentimes - customer.currentDebtCentimes;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 16),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'سجل ديون الزبون',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الدين الحالي:', style: TextStyle(fontSize: 12)),
              DzdPriceTag(centimes: customer.currentDebtCentimes),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('سقف الائتمان:', style: TextStyle(fontSize: 12)),
              DzdPriceTag(centimes: customer.creditLimitCentimes),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الائتمان المتبقي:', style: TextStyle(fontSize: 12)),
              DzdPriceTag(
                centimes: remainingCredit > 0 ? remainingCredit : 0,
                color: remainingCredit > 0 ? colors.success : colors.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDifferenceResultCard(int difference, dynamic colors) {
    final isChange = difference >= 0;
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isChange ? colors.successContainer : colors.warningContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: isChange ? colors.success : colors.warning,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  isChange
                      ? Icons.monetization_on_outlined
                      : Icons.pending_actions_outlined,
                  color: isChange
                      ? colors.onSuccessContainer
                      : colors.onWarningContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    isChange ? 'المتبقي كصرف للزبون:' : 'المتبقي كدين على الحساب:',
                    style: TextStyle(
                      color: isChange
                          ? colors.onSuccessContainer
                          : colors.onWarningContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          DzdPriceTag(
            centimes: difference.abs(),
            color: isChange
                ? colors.onSuccessContainer
                : colors.onWarningContainer,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<PosPaymentMode>(
      segments: const [
        ButtonSegment<PosPaymentMode>(
          value: PosPaymentMode.cash,
          label: Text('نقدًا بالكامل'),
          icon: Icon(Icons.payments_outlined, size: 18),
        ),
        ButtonSegment<PosPaymentMode>(
          value: PosPaymentMode.credit,
          label: Text('دين على الحساب'),
          icon: Icon(Icons.credit_card_outlined, size: 18),
        ),
        ButtonSegment<PosPaymentMode>(
          value: PosPaymentMode.mixed,
          label: Text('دفع مجزأ'),
          icon: Icon(Icons.call_split_rounded, size: 18),
        ),
      ],
      selected: {_paymentMode},
      onSelectionChanged: (set) {
        final mode = set.first;
        setState(() {
          _paymentMode = mode;
          if (mode == PosPaymentMode.cash) {
            _paidCentimes = widget.totalCentimes;
            final text = (widget.totalCentimes / 100.0).toStringAsFixed(0);
            _paidCashController.text = text;
            _paidCashController.selection =
                TextSelection(baseOffset: 0, extentOffset: text.length);
          } else if (mode == PosPaymentMode.credit) {
            _paidCentimes = 0;
            _paidCashController.text = '0';
            _paidCashController.selection =
                const TextSelection(baseOffset: 0, extentOffset: 1);
          }
        });
      },
    );
  }

  Widget _buildCashInputField(ColorScheme colorScheme) {
    return TextField(
      controller: _paidCashController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      autofocus: true,
      onTap: () {
        _paidCashController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _paidCashController.text.length,
        );
      },
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: 'المبلغ المستلم نقدًا من الزبون (دج) [Enter]',
        prefixIcon: const Icon(Icons.money_rounded, size: 28),
        suffixText: 'دج',
        suffixStyle:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
      ),
      onChanged: (val) {
        final clean = val.replaceAll(' ', '').trim();
        final parsed = double.tryParse(clean) ?? 0.0;
        setState(() {
          _paidCentimes = (parsed * 100).round();
          _syncPaymentMode();
        });
      },
      onSubmitted: (_) => _handleConfirm(),
    );
  }

  Widget _buildQuickDenominationChips(dynamic role) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        ActionChip(
          avatar: Icon(Icons.done_all_rounded, size: 14, color: role.badgeText),
          label: const Text('كامل المبلغ (بدون باقي)'),
          labelStyle: TextStyle(color: role.badgeText, fontWeight: FontWeight.bold),
          onPressed: () => _setCashAmount(widget.totalCentimes / 100.0),
          backgroundColor: role.badgeBackground,
        ),
        ActionChip(
          avatar: Icon(Icons.clear_rounded, size: 14, color: role.badgeText),
          label: const Text('0 دج (دين كامل)'),
          labelStyle: TextStyle(color: role.badgeText),
          onPressed: () => _setCashAmount(0),
          backgroundColor: role.badgeBackground,
        ),
        ...[500, 1000, 2000, 5000, 10000].map((val) {
          return ActionChip(
            label: Text('$val دج'),
            labelStyle: TextStyle(color: role.badgeText, fontWeight: FontWeight.w600),
            onPressed: () => _setCashAmount(val.toDouble()),
            backgroundColor: role.badgeBackground,
          );
        }),
      ],
    );
  }

  Widget _buildMissingCustomerAlert(dynamic colors) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: colors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'تنبيه: البيع بالدين أو الحساب المجزأ يتطلب اختيار زبون مسجل في الجلسة أولاً.',
              style: TextStyle(
                fontSize: 13,
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVirtualKeypad(ColorScheme colorScheme, Color brand) {
    final keys = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['C', '0', '00'],
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (final row in keys) ...[
            Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: key == 'C'
                                ? colorScheme.errorContainer
                                : colorScheme.surfaceContainerHigh,
                            foregroundColor: key == 'C'
                                ? colorScheme.onErrorContainer
                                : colorScheme.onSurface,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.smAll,
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          onPressed: () {
                            if (key == 'C') {
                              _clearKeypad();
                            } else {
                              _appendKeypad(key);
                            }
                          },
                          child: Text(
                            key,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.backspace_outlined, size: 20),
                label: const Text('حذف الرقم الأخير (Backspace)'),
                onPressed: _backspaceKeypad,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
