import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';
import '../services/pos_thermal_printer.dart';

/// A responsive, high-fidelity screen for collecting customer debts, viewing ledger history, and printing statements.
class CustomerDebtDialog extends ConsumerStatefulWidget {
  final CustomerProfileEntity customer;
  final String cashierId;
  final String cashierName;

  const CustomerDebtDialog({
    super.key,
    required this.customer,
    required this.cashierId,
    required this.cashierName,
  });

  /// Opens the customer debt management screen as a dedicated fullscreen screen route.
  static Future<bool?> show(
    BuildContext context, {
    required CustomerProfileEntity customer,
    required String cashierId,
    required String cashierName,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CustomerDebtDialog(
          customer: customer,
          cashierId: cashierId,
          cashierName: cashierName,
        ),
      ),
    );
  }

  @override
  ConsumerState<CustomerDebtDialog> createState() => _CustomerDebtDialogState();
}

class _CustomerDebtDialogState extends ConsumerState<CustomerDebtDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _chequeRefController = TextEditingController();

  String _paymentMethod = 'cash'; // 'cash', 'card', 'cheque'
  bool _autoPrintVoucher = true;
  bool _isSubmitting = false;

  late CustomerProfileEntity _currentCustomer;

  @override
  void initState() {
    super.initState();
    _currentCustomer = widget.customer;
    _tabController = TabController(length: 2, vsync: this);

    if (_currentCustomer.currentDebtCentimes > 0) {
      _amountController.text =
          (_currentCustomer.currentDebtCentimes / 100).toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _chequeRefController.dispose();
    super.dispose();
  }

  int get _enteredCentimes {
    final val = double.tryParse(_amountController.text.trim()) ?? 0;
    return (val * 100).round();
  }

  void _applyPresetPercent(double factor) {
    final amountCentimes =
        (_currentCustomer.currentDebtCentimes * factor).round();
    _amountController.text = (amountCentimes / 100).toStringAsFixed(0);
    setState(() {});
  }

  Future<void> _handleCollectDebt() async {
    final payCentimes = _enteredCentimes;
    if (payCentimes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى إدخال مبلغ صحيح لسداد الدين'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (payCentimes > _currentCustomer.currentDebtCentimes &&
        _currentCustomer.currentDebtCentimes > 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
          title: const Text('تنبيه: سداد يفوق الدين'),
          content: Text(
            'المبلغ المدخل (${DzdFormatter.formatCentimes(payCentimes)}) يفوق الدين الحالي (${DzdFormatter.formatCentimes(_currentCustomer.currentDebtCentimes)}). هل تود المتابعة؟',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تأكيد')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(customerRepositoryProvider);
      final result = await repo.collectCustomerDebt(
        cashierId: widget.cashierId,
        customerId: _currentCustomer.id,
        amountCentimes: payCentimes,
        paymentMethod: _paymentMethod,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        referenceNumber: _paymentMethod == 'cheque'
            ? _chequeRefController.text.trim()
            : null,
      );

      if (_paymentMethod == 'cash') {
        ref
            .read(posActiveShiftProvider.notifier)
            .registerDebtCashPayment(cashCentimes: payCentimes);
      }

      final updatedCustomer = await repo.getCustomerById(_currentCustomer.id);
      if (updatedCustomer != null) {
        ref.read(posActiveCustomerProvider.notifier).state = updatedCustomer;
      }

      if (_autoPrintVoucher) {
        await PosThermalPrinterService.printCustomerDebtVoucher(
          result: result,
          customer: _currentCustomer,
          cashierName: widget.cashierName,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✓ تم تحصيل مبلغ ${DzdFormatter.formatCentimes(payCentimes)} بنجاح!'),
          backgroundColor: context.appColors.success,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تسجيل السداد: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
                    child: Icon(Icons.account_balance_wallet_rounded,
                        size: 20, color: role.badgeText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'سداد ديون الزبون: ${_currentCustomer.name}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'أمين الصندوق: ${widget.cashierName} | الهاتف: ${_currentCustomer.phone}',
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
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.md),
                child: Chip(
                  avatar: Icon(Icons.credit_card_rounded,
                      size: 16, color: colors.warning),
                  label: Text(
                    'الدين الحالي: ${DzdFormatter.formatCentimes(_currentCustomer.currentDebtCentimes)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _currentCustomer.currentDebtCentimes > 0
                          ? colors.warning
                          : colors.success,
                    ),
                  ),
                  backgroundColor: colors.warningContainer.withValues(alpha: 0.3),
                  side: BorderSide(color: colors.warning.withValues(alpha: 0.4)),
                ),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 880;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: Payment Form
                    SizedBox(
                      width: 440,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          border: BorderDirectional(
                            end: BorderSide(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCustomerHeaderCard(theme, colors),
                              AppSpacing.gapLg,
                              _buildPaymentCollectionSection(
                                  theme, colorScheme, colors, brand),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Right Column: Statement Ledger & Unpaid Invoices
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: _buildStatementLedgerTab(
                            theme, colorScheme, colors),
                      ),
                    ),
                  ],
                );
              }

              // Mobile Layout: Tabs for Payment vs Statement
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: _buildCustomerHeaderCard(theme, colors),
                  ),
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.payments_outlined, size: 18),
                        text: 'سداد دين (تحصيل)',
                      ),
                      Tab(
                        icon: Icon(Icons.receipt_long_outlined, size: 18),
                        text: 'كشف الحساب والديون',
                      ),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: _buildPaymentCollectionSection(
                              theme, colorScheme, colors, brand),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: _buildStatementLedgerTab(
                              theme, colorScheme, colors),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerHeaderCard(ThemeData theme, dynamic colors) {
    final hasDebt = _currentCustomer.currentDebtCentimes > 0;
    final isOverLimit = _currentCustomer.isCreditExceeded(0);

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isOverLimit
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: isOverLimit
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: hasDebt
                    ? colors.warningContainer
                    : theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person_rounded,
                  color: hasDebt
                      ? colors.onWarningContainer
                      : theme.colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentCustomer.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(_currentCustomer.phone,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (isOverLimit)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    borderRadius: AppRadius.xsAll,
                  ),
                  child: Text(
                    'تجاوز سقف الائتمان',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onError,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الدين الإجمالي الحالي:',
                      style: TextStyle(fontSize: 11)),
                  DzdPriceTag(
                    centimes: _currentCustomer.currentDebtCentimes,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: hasDebt ? theme.colorScheme.error : colors.success,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('سقف الائتمان الممنوح:',
                      style: TextStyle(fontSize: 11)),
                  DzdPriceTag(
                    centimes: _currentCustomer.creditLimitCentimes,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCollectionSection(ThemeData theme,
      ColorScheme colorScheme, dynamic colors, Color brand) {
    final payCentimes = _enteredCentimes;
    final prevCentimes = _currentCustomer.currentDebtCentimes;
    final remainingCentimes =
        (prevCentimes - payCentimes) > 0 ? (prevCentimes - payCentimes) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('خيارات السداد السريع:',
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            ActionChip(
              avatar: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('كامل الدين (100%)'),
              onPressed: () => _applyPresetPercent(1.0),
            ),
            ActionChip(
              avatar: const Icon(Icons.pie_chart_outline, size: 16),
              label: const Text('النصف (50%)'),
              onPressed: () => _applyPresetPercent(0.5),
            ),
            ActionChip(
              avatar: const Icon(Icons.pie_chart_outline, size: 16),
              label: const Text('الربع (25%)'),
              onPressed: () => _applyPresetPercent(0.25),
            ),
          ],
        ),
        AppSpacing.gapLg,

        // Amount Input
        TextField(
          controller: _amountController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: 'المبلغ المقبوض من الزبون (دج) *',
            prefixIcon: const Icon(Icons.money_rounded, size: 28),
            suffixText: 'دج',
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
          onChanged: (_) => setState(() {}),
        ),
        AppSpacing.gapMd,

        // Payment Method Selector
        Text('طريقة الدفع والتحصيل:',
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'cash',
              label: Text('نقداً (بالدرج)'),
              icon: Icon(Icons.payments_outlined, size: 16),
            ),
            ButtonSegment(
              value: 'card',
              label: Text('بطاقة بنكية'),
              icon: Icon(Icons.credit_card_outlined, size: 16),
            ),
            ButtonSegment(
              value: 'cheque',
              label: Text('شيك بنكي'),
              icon: Icon(Icons.account_balance_outlined, size: 16),
            ),
          ],
          selected: {_paymentMethod},
          onSelectionChanged: (val) =>
              setState(() => _paymentMethod = val.first),
        ),
        AppSpacing.gapMd,

        if (_paymentMethod == 'cheque') ...[
          TextField(
            controller: _chequeRefController,
            decoration: InputDecoration(
              labelText: 'رقم الشيك / اسم المصرف *',
              prefixIcon: const Icon(Icons.pin),
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
              border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
            ),
          ),
          AppSpacing.gapMd,
        ],

        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'ملاحظات إضافية (اختياري)',
            prefixIcon: const Icon(Icons.note_alt_outlined),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
        AppSpacing.gapMd,

        // Summary Card
        Container(
          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.25),
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              _summaryRow('الرصيد السابق:', DzdPriceTag(centimes: prevCentimes)),
              const SizedBox(height: 4),
              _summaryRow(
                'المبلغ المقبوض الآن:',
                DzdPriceTag(
                  centimes: payCentimes,
                  color: colors.success,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 12),
              _summaryRow(
                'الرصيد المتبقي بعد السداد:',
                DzdPriceTag(
                  centimes: remainingCentimes,
                  color: remainingCentimes > 0
                      ? colorScheme.error
                      : colors.success,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        AppSpacing.gapMd,

        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('طباعة سند قبض حراري فوري (80mm)'),
          value: _autoPrintVoucher,
          onChanged: (v) => setState(() => _autoPrintVoucher = v ?? true),
        ),
        AppSpacing.gapLg,

        GoldButton.icon(
          onPressed: _isSubmitting ? null : _handleCollectDebt,
          icon: _isSubmitting
              ? Icons.hourglass_top_rounded
              : Icons.check_circle_rounded,
          label: _isSubmitting
              ? 'جاري حفظ السداد...'
              : 'تأكيد وقبض المبلغ [${DzdFormatter.formatCentimes(payCentimes)}]',
        ),
      ],
    );
  }

  Widget _buildStatementLedgerTab(
      ThemeData theme, ColorScheme colorScheme, dynamic colors) {
    final ledgerAsync = ref.watch(customerLedgerProvider(_currentCustomer.id));
    final unpaidOrdersAsync =
        ref.watch(customerUnpaidOrdersProvider(_currentCustomer.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'حركات الحساب والفواتير غير المسددة:',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final entries = ledgerAsync.value ?? [];
                await PosThermalPrinterService.printCustomerAccountStatement(
                  customer: _currentCustomer,
                  entries: entries,
                  cashierName: widget.cashierName,
                );
              },
              icon: const Icon(Icons.print_outlined, size: 16),
              label: const Text('طباعة كشف الحساب'),
            ),
          ],
        ),
        AppSpacing.gapMd,
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  labelColor: colorScheme.primary,
                  tabs: const [
                    Tab(text: 'سجل الحركات المالية'),
                    Tab(text: 'الفواتير والوصولات غير المسددة'),
                  ],
                ),
                AppSpacing.gapSm,
                Expanded(
                  child: TabBarView(
                    children: [
                      // 1. Ledger Entries
                      ledgerAsync.when(
                        data: (entries) {
                          if (entries.isEmpty) {
                            return const Center(
                              child: AppEmptyView(
                                icon: Icons.receipt_long_outlined,
                                title: 'لا توجد حركات مالية',
                                description:
                                    'لا توجد قيود مسجلة في دفتر الأستاذ لهذا الزبون.',
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final e = entries[idx];
                              final isPayment = e.isDebtPayment;
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isPayment
                                      ? colors.successContainer
                                      : colorScheme.errorContainer,
                                  child: Icon(
                                    isPayment
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    size: 16,
                                    color: isPayment
                                        ? colors.onSuccessContainer
                                        : colorScheme.onErrorContainer,
                                  ),
                                ),
                                title: Text(
                                  isPayment
                                      ? 'سداد / دفعة دين'
                                      : 'مبيعات بالدين (وصل)',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${e.createdAt.toString().substring(0, 16)} ${e.notes != null ? '• ${e.notes}' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                trailing: Text(
                                  '${isPayment ? '-' : '+'}${DzdFormatter.formatCentimes(e.amountChangeCentimes.abs())}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isPayment
                                        ? colors.success
                                        : colorScheme.error,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                            child: AppLoadingView(
                                message: 'جاري تحميل الحركات...')),
                        error: (err, _) => Center(
                            child: AppErrorView(
                                message: 'تعذر تحميل الحركات: $err')),
                      ),

                      // 2. Unpaid Orders
                      unpaidOrdersAsync.when(
                        data: (unpaidList) {
                          if (unpaidList.isEmpty) {
                            return const Center(
                              child: AppEmptyView(
                                icon: Icons.check_circle_outline_rounded,
                                title: 'لا توجد فواتير معلقة',
                                description:
                                    'جميع الفواتير والوصولات السابقة مسددة بالكامل.',
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: unpaidList.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final order = unpaidList[idx];
                              return ExpansionTile(
                                leading: const Icon(Icons.receipt_outlined),
                                title: Text(
                                  'وصل #${order.orderId.length > 8 ? order.orderId.substring(0, 8) : order.orderId}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                subtitle: Text(
                                  'بتاريخ: ${order.orderDate.toString().substring(0, 10)} | المتبقي: ${DzdFormatter.formatCentimes(order.remainingDebtCentimes)}',
                                  style: TextStyle(
                                      color: colorScheme.error, fontSize: 11),
                                ),
                                trailing: DzdPriceTag(
                                  centimes: order.totalAmountCentimes,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(
                                        AppSpacing.sm),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          'المواد: ${order.itemsSummary.join(', ')}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'المدفوع: ${DzdFormatter.formatCentimes(order.paidAmountCentimes)}',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                            Text(
                                              'المتبقي: ${DzdFormatter.formatCentimes(order.remainingDebtCentimes)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.error,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                            child: AppLoadingView(
                                message: 'جاري تحميل الفواتير...')),
                        error: (err, _) => Center(
                            child: AppErrorView(
                                message: 'تعذر تحميل الفواتير: $err')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, Widget valueWidget) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        valueWidget,
      ],
    );
  }
}
