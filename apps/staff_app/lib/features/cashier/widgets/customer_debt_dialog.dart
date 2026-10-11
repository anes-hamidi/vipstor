import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';
import '../services/pos_thermal_printer.dart';

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

  @override
  ConsumerState<CustomerDebtDialog> createState() => _CustomerDebtDialogState();
}

class _CustomerDebtDialogState extends ConsumerState<CustomerDebtDialog> with SingleTickerProviderStateMixin {
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

    // Default amount = full debt
    if (_currentCustomer.currentDebtCentimes > 0) {
      _amountController.text = (_currentCustomer.currentDebtCentimes / 100).toStringAsFixed(0);
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
    final amountCentimes = (_currentCustomer.currentDebtCentimes * factor).round();
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

    if (payCentimes > _currentCustomer.currentDebtCentimes && _currentCustomer.currentDebtCentimes > 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
          title: const Text('تنبيه: سداد يفوق الدين'),
          content: Text(
            'المبلغ المدخل (${DzdFormatter.formatCentimes(payCentimes)}) يفوق الدين الحالي (${DzdFormatter.formatCentimes(_currentCustomer.currentDebtCentimes)}). هل تود المتابعة؟',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
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
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        referenceNumber: _paymentMethod == 'cheque' ? _chequeRefController.text.trim() : null,
      );

      // Register cash payment in shift if method is cash
      if (_paymentMethod == 'cash') {
        ref.read(posActiveShiftProvider.notifier).registerDebtCashPayment(cashCentimes: payCentimes);
      }

      // Refresh customer data
      final updatedCustomer = await repo.getCustomerById(_currentCustomer.id);
      if (updatedCustomer != null) {
        ref.read(posActiveCustomerProvider.notifier).state = updatedCustomer;
      }

      // Print thermal voucher if enabled
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
          content: Text('✓ تم تحصيل مبلغ ${DzdFormatter.formatCentimes(payCentimes)} بنجاح!'),
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
    final colors = context.appColors;
    final isCompact = MediaQuery.of(context).size.width < 700;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header with Customer Summary Card
              _buildCustomerHeaderCard(theme, colors),
              AppSpacing.gapSm,

              // Tabs
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.payments_outlined, size: 20), text: 'سداد دين (تحصيل)'),
                  Tab(icon: Icon(Icons.receipt_long_outlined, size: 20), text: 'كشف الحساب وسجل الديون'),
                ],
              ),
              AppSpacing.gapMd,

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPaymentCollectionTab(theme, colors, isCompact),
                    _buildStatementLedgerTab(theme, colors),
                  ],
                ),
              ),

              // Bottom Cancel Action
              const Divider(height: 1),
              AppSpacing.gapSm,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق [Esc]'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerHeaderCard(ThemeData theme, AppColors colors) {
    final hasDebt = _currentCustomer.currentDebtCentimes > 0;
    final isOverLimit = _currentCustomer.isCreditExceeded(0);

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isOverLimit
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: isOverLimit ? theme.colorScheme.error : theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: hasDebt ? colors.warningContainer : theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.account_balance_wallet,
              color: hasDebt ? colors.onWarningContainer : theme.colorScheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _currentCustomer.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (isOverLimit) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: AppRadius.xsAll,
                        ),
                        child: Text(
                          'تجاوز سقف الائتمان',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onError, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(_currentCustomer.phone, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('إجمالي الدين: ', style: theme.textTheme.bodySmall),
                  DzdPriceTag(
                    centimes: _currentCustomer.currentDebtCentimes,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: hasDebt ? theme.colorScheme.error : colors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('سقف الائتمان: ', style: theme.textTheme.bodySmall),
                  DzdPriceTag(
                    centimes: _currentCustomer.creditLimitCentimes,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCollectionTab(ThemeData theme, AppColors colors, bool isCompact) {
    final payCentimes = _enteredCentimes;
    final prevCentimes = _currentCustomer.currentDebtCentimes;
    final remainingCentimes = (prevCentimes - payCentimes) > 0 ? (prevCentimes - payCentimes) : 0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSpacing.gapMd,
          // Presets Row
          Text('خيارات السداد السريع:', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
          AppSpacing.gapSm,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
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
          AppSpacing.gapMd,

          // Amount Input
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'المبلغ المقبوض (دج) *',
              prefixIcon: Icon(Icons.money),
              suffixText: 'دج',
              border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
              helperText: 'أدخل المبلغ الذي يدفعه الزبون الآن',
            ),
            onChanged: (_) => setState(() {}),
          ),
          AppSpacing.gapMd,

          // Payment Method Selector
          Text('طريقة الدفع:', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
          AppSpacing.gapSm,
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'cash',
                label: Text('نقداً (درج الكاشير)'),
                icon: Icon(Icons.attach_money),
              ),
              ButtonSegment(
                value: 'card',
                label: Text('بطاقة / ذهبية'),
                icon: Icon(Icons.credit_card),
              ),
              ButtonSegment(
                value: 'cheque',
                label: Text('شيك بنكي'),
                icon: Icon(Icons.account_balance),
              ),
            ],
            selected: {_paymentMethod},
            onSelectionChanged: (val) => setState(() => _paymentMethod = val.first),
          ),
          AppSpacing.gapMd,

          if (_paymentMethod == 'cheque') ...[
            TextField(
              controller: _chequeRefController,
              decoration: const InputDecoration(
                labelText: 'رقم الشيك / اسم البنك *',
                prefixIcon: Icon(Icons.pin),
                border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
              ),
            ),
            AppSpacing.gapMd,
          ],

          // Notes
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'ملاحظات إضافية (اختياري)',
              prefixIcon: Icon(Icons.note_alt_outlined),
              border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
            ),
          ),
          AppSpacing.gapMd,

          // Real-time calculation summary card
          Container(
            padding: const EdgeInsetsDirectional.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: AppRadius.mdAll,
            ),
            child: Column(
              children: [
                _summaryRow('الرصيد السابق:', DzdPriceTag(centimes: prevCentimes)),
                const SizedBox(height: 4),
                _summaryRow(
                  'المبلغ المقبوض:',
                  DzdPriceTag(
                    centimes: payCentimes,
                    style: TextStyle(fontWeight: FontWeight.bold, color: colors.success),
                  ),
                ),
                const Divider(height: 12),
                _summaryRow(
                  'الرصيد المتبقي بعد السداد:',
                  DzdPriceTag(
                    centimes: remainingCentimes,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: remainingCentimes > 0 ? theme.colorScheme.error : colors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapMd,

          // Auto-print toggle & Submit button
          Row(
            children: [
              Checkbox(
                value: _autoPrintVoucher,
                onChanged: (v) => setState(() => _autoPrintVoucher = v ?? true),
              ),
              const Expanded(
                child: Text('طباعة سند قبض حراري فوري (80mm)'),
              ),
            ],
          ),
          AppSpacing.gapSm,

          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            ),
            onPressed: _isSubmitting ? null : _handleCollectDebt,
            icon: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                : const Icon(Icons.check_circle, size: 20),
            label: Text(
              _isSubmitting
                  ? 'جاري حفظ السداد وتحديث الحساب...'
                  : 'تأكيد وقبض المبلغ [${DzdFormatter.formatCentimes(payCentimes)}]',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementLedgerTab(ThemeData theme, AppColors colors) {
    final ledgerAsync = ref.watch(customerLedgerProvider(_currentCustomer.id));
    final unpaidOrdersAsync = ref.watch(customerUnpaidOrdersProvider(_currentCustomer.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'حركات الحساب والفواتير غير المسددة',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
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
        AppSpacing.gapSm,
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'سجل الحركات المالية'),
                    Tab(text: 'الفواتير والوصولات غير المسددة'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // 1. Ledger Entries
                      ledgerAsync.when(
                        data: (entries) {
                          if (entries.isEmpty) {
                            return const Center(child: Text('لا توجد حركات مالية مسجلة'));
                          }
                          return ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final e = entries[idx];
                              final isPayment = e.isDebtPayment;
                              return ListTile(
                                visualDensity: VisualDensity.compact,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isPayment ? colors.successContainer : theme.colorScheme.errorContainer,
                                  child: Icon(
                                    isPayment ? Icons.arrow_downward : Icons.arrow_upward,
                                    size: 16,
                                    color: isPayment ? colors.onSuccessContainer : theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                                title: Text(
                                  isPayment ? 'سداد / دفعة دين' : 'مبيعات بالدين (وصل)',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${e.createdAt.toString().substring(0, 16)} ${e.notes != null ? '• ${e.notes}' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                trailing: Text(
                                  '${isPayment ? '-' : '+'}${DzdFormatter.formatCentimes(e.amountChangeCentimes.abs())}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isPayment ? colors.success : theme.colorScheme.error,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
                        error: (err, _) => Center(child: Text('تعذر تحميل الحركات: $err')),
                      ),

                      // 2. Unpaid Orders
                      unpaidOrdersAsync.when(
                        data: (unpaidList) {
                          if (unpaidList.isEmpty) {
                            return const Center(child: Text('لا توجد فواتير معلقة غير مسددة'));
                          }
                          return ListView.separated(
                            itemCount: unpaidList.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final order = unpaidList[idx];
                              return ExpansionTile(
                                leading: const Icon(Icons.receipt_outlined),
                                title: Text(
                                  'وصل #${order.orderId.length > 8 ? order.orderId.substring(0, 8) : order.orderId}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Text(
                                  'بتاريخ: ${order.orderDate.toString().substring(0, 10)} | المتبقي: ${DzdFormatter.formatCentimes(order.remainingDebtCentimes)}',
                                  style: TextStyle(color: theme.colorScheme.error, fontSize: 11),
                                ),
                                trailing: DzdPriceTag(
                                  centimes: order.totalAmountCentimes,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Text('المنتجات: ${order.itemsSummary.join(', ')}', style: theme.textTheme.bodySmall),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('المدفوع: ${DzdFormatter.formatCentimes(order.paidAmountCentimes)}', style: theme.textTheme.bodySmall),
                                            Text('المتبقي: ${DzdFormatter.formatCentimes(order.remainingDebtCentimes)}', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.error, fontSize: 12)),
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
                        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
                        error: (err, _) => Center(child: Text('تعذر تحميل الفواتير: $err')),
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
