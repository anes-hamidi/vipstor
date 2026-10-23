import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';
import '../services/pos_thermal_printer.dart';

class DriverSettlementDialog extends ConsumerStatefulWidget {
  final String? initialDriverId;
  final String? initialDriverName;
  final String receiverId;
  final String receiverName;
  final String receiverRole; // 'cashier' or 'moderator'

  const DriverSettlementDialog({
    super.key,
    this.initialDriverId,
    this.initialDriverName,
    required this.receiverId,
    required this.receiverName,
    required this.receiverRole,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialDriverId,
    String? initialDriverName,
    required String receiverId,
    required String receiverName,
    required String receiverRole,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DriverSettlementDialog(
        initialDriverId: initialDriverId,
        initialDriverName: initialDriverName,
        receiverId: receiverId,
        receiverName: receiverName,
        receiverRole: receiverRole,
      ),
    );
  }

  @override
  ConsumerState<DriverSettlementDialog> createState() =>
      _DriverSettlementDialogState();
}

class _DriverSettlementDialogState
    extends ConsumerState<DriverSettlementDialog> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  String? _selectedDriverId;
  String? _selectedDriverName;
  String? _selectedDriverPhone;
  bool _autoPrintVoucher = true;
  bool _showDenominations = false;
  bool _isSubmitting = false;

  final Map<int, TextEditingController> _denomControllers = {
    2000: TextEditingController(text: '0'),
    1000: TextEditingController(text: '0'),
    500: TextEditingController(text: '0'),
    200: TextEditingController(text: '0'),
    100: TextEditingController(text: '0'),
    50: TextEditingController(text: '0'),
  };

  @override
  void initState() {
    super.initState();
    _selectedDriverId = widget.initialDriverId;
    _selectedDriverName = widget.initialDriverName;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    for (final c in _denomControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _enteredCentimes {
    final val = double.tryParse(_amountController.text.trim()) ?? 0;
    return (val * 100).round();
  }

  void _onDriverSelected(DriverSettlementSummaryEntity driver) {
    setState(() {
      _selectedDriverId = driver.driverId;
      _selectedDriverName = driver.driverName;
      _selectedDriverPhone = driver.driverPhone;
      if (driver.pendingCashCentimes > 0) {
        _amountController.text =
            (driver.pendingCashCentimes / 100).toStringAsFixed(0);
      } else {
        _amountController.text = '0';
      }
    });
  }

  void _recalcFromDenominations() {
    int totalDzd = 0;
    _denomControllers.forEach((denom, controller) {
      final count = int.tryParse(controller.text.trim()) ?? 0;
      totalDzd += denom * count;
    });
    setState(() {
      _amountController.text = totalDzd.toString();
    });
  }

  Future<void> _submitSettlement(
      int expectedCentimes, int unsettledCount) async {
    if (_selectedDriverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد سائق التوصيل أولاً')),
      );
      return;
    }

    final countedCentimes = _enteredCentimes;
    final difference = countedCentimes - expectedCentimes;

    if (difference != 0 && _notesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(difference < 0
              ? 'يوجد عجز بمبلغ ${DzdFormatter.formatCentimes(difference.abs())}. يرجى توضيح السبب في حقل الملاحظات.'
              : 'يوجد فائض بمبلغ ${DzdFormatter.formatCentimes(difference)}. يرجى توضيح السبب في حقل الملاحظات.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(settlementRepositoryProvider);
      final settlement = await repo.settleDriverWallet(
        cashierId: widget.receiverId,
        driverId: _selectedDriverId!,
        countedAmountCentimes: countedCentimes,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      // If active cashier shift, register the incoming cash into drawer
      if (widget.receiverRole == 'cashier' && countedCentimes > 0) {
        ref.read(posActiveShiftProvider.notifier).registerDriverSettlement(
              cashCentimes: countedCentimes,
            );
      }

      // Audit log
      ref.read(staffAuditLoggerProvider).logDriverSettlement(
            cashierId: widget.receiverId,
            cashierName: widget.receiverName,
            driverId: _selectedDriverId!,
            driverName: _selectedDriverName ?? 'سائق التوصيل',
            settlementId: settlement.id,
            expectedCentimes: expectedCentimes,
            countedCentimes: countedCentimes,
            differenceCentimes: difference,
            status: settlement.status,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      // Print receipt if requested
      if (_autoPrintVoucher) {
        try {
          await PosThermalPrinterService.printDriverSettlementVoucher(
            settlement: settlement,
            driverPhone: _selectedDriverPhone,
            unsettledOrdersCount: unsettledCount,
            receiverRole:
                widget.receiverRole == 'cashier' ? 'أمين الصندوق' : 'المشرف',
          );
        } catch (_) {}
      }

      // Invalidate relevant providers
      ref.invalidate(pendingDriverSettlementsProvider);
      ref.invalidate(recentSettlementsProvider);
      ref.invalidate(driverWalletBalanceProvider);
      ref.invalidate(driverOrdersProvider);
      ref.invalidate(staffMembersProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ تم تسجيل تسوية عهدة السائق بنجاح (${DzdFormatter.formatCentimes(countedCentimes)})',
            ),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تسجيل التسوية: ${e.toString()}'),
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
    final colors = context.appColors;
    final role = context.roleTheme;
    final driversAsync = ref.watch(pendingDriverSettlementsProvider);

    return Dialog(
      backgroundColor: colors.obsidianSurface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: role.badgeBackground,
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Icon(Icons.handshake_rounded,
                        color: role.badgeText, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تسوية عهدة سائق التوصيل (Cash Close)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.onObsidian,
                          ),
                        ),
                        Text(
                          'المستلم: ${widget.receiverName} (${widget.receiverRole == "cashier" ? "أمين الصندوق" : "المشرف"})',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.gold),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed:
                        _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              // Content Body
              Expanded(
                child: driversAsync.when(
                  data: (drivers) {
                    if (drivers.isEmpty) {
                      return AppStates.empty(
                        icon: Icons.local_shipping_outlined,
                        title: 'لا يوجد سائقو توصيل مسجلون',
                        description:
                            'قم بإضافة سائقين أولاً لتمكين تسوية العهدة.',
                      );
                    }

                    // Auto-select if initial ID or single driver
                    if (_selectedDriverId == null && drivers.isNotEmpty) {
                      final found = drivers.firstWhere(
                        (d) => d.pendingCashCentimes > 0,
                        orElse: () => drivers.first,
                      );
                      _selectedDriverId = found.driverId;
                      _selectedDriverName = found.driverName;
                      _selectedDriverPhone = found.driverPhone;
                      _amountController.text =
                          (found.pendingCashCentimes / 100).toStringAsFixed(0);
                    }

                    final selectedDriver = drivers.firstWhere(
                      (d) => d.driverId == _selectedDriverId,
                      orElse: () => drivers.first,
                    );

                    final expectedCentimes = selectedDriver.pendingCashCentimes;
                    final countedCentimes = _enteredCentimes;
                    final diffCentimes = countedCentimes - expectedCentimes;

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Driver Selector Bar
                          Text(
                            'اختر السائق المطلوب تسويته:',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onObsidian.withValues(alpha: 0.65),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Container(
                            height: 60,
                            decoration: BoxDecoration(
                              color: colors.obsidianCard,
                              borderRadius: AppRadius.mdAll,
                              border: Border.all(
                                  color: colors.gold.withValues(alpha: 0.2)),
                            ),
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              itemCount: drivers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (ctx, i) {
                                final d = drivers[i];
                                final isSel = d.driverId == _selectedDriverId;
                                return ChoiceChip(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person_pin_circle_rounded,
                                        size: 16,
                                        color: isSel
                                            ? theme.colorScheme.onPrimary
                                            : colors.gold,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        d.driverName,
                                        style: TextStyle(
                                          fontWeight: isSel
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSel
                                              ? theme.colorScheme.onPrimary
                                              : colors.onObsidian,
                                        ),
                                      ),
                                      if (d.pendingCashCentimes > 0) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isSel
                                                ? theme.colorScheme.onPrimary
                                                    .withValues(alpha: 0.2)
                                                : colors.gold
                                                    .withValues(alpha: 0.2),
                                            borderRadius: AppRadius.pillAll,
                                          ),
                                          child: Text(
                                            DzdFormatter.formatCentimes(
                                                d.pendingCashCentimes),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isSel
                                                  ? theme.colorScheme.onPrimary
                                                  : colors.gold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  selected: isSel,
                                  selectedColor: colors.gold,
                                  backgroundColor: colors.obsidianSurface,
                                  onSelected: (_) => _onDriverSelected(d),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // Driver Summary Card
                          LuxuryCard(
                            padding:
                                const EdgeInsetsDirectional.all(AppSpacing.md),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'الكاش المتوقع بالعهدة (Expected):',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colors.onObsidian
                                              .withValues(alpha: 0.65),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        DzdFormatter.formatCentimes(
                                            expectedCentimes),
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colors.gold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: colors.obsidianSurface,
                                    borderRadius: AppRadius.smAll,
                                    border: Border.all(
                                        color:
                                            colors.gold.withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'طلبات غير مسواة',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: colors.onObsidian
                                              .withValues(alpha: 0.65),
                                        ),
                                      ),
                                      Text(
                                        '${selectedDriver.unsettledOrdersCount} طلبات',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // Unsettled Orders Preview (Collapsible)
                          Consumer(
                            builder: (context, ref, _) {
                              final ordersAsync = ref.watch(
                                  driverUnsettledOrdersProvider(
                                      selectedDriver.driverId));
                              return ordersAsync.when(
                                data: (orders) {
                                  if (orders.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: Text(
                                      'عرض تفاصيل الطلبات المشمولة (${orders.length} طلبات)',
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        color: colors.gold,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    children: [
                                      Container(
                                        constraints: const BoxConstraints(
                                            maxHeight: 140),
                                        child: ListView.separated(
                                          itemCount: orders.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1),
                                          itemBuilder: (ctx, idx) {
                                            final o = orders[idx];
                                            return ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                'طلب #${o.orderNumber ?? o.id.substring(0, 6)} - ${o.customerName ?? "زبون"}',
                                                style: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                              trailing: Text(
                                                DzdFormatter.formatCentimes(
                                                    o.paidAmountCentimes),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: colors.success,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  );
                                },
                                loading: () => const SizedBox.shrink(),
                                error: (_, __) => const SizedBox.shrink(),
                              );
                            },
                          ),

                          const SizedBox(height: AppSpacing.sm),

                          // Cash Counted Input
                          Row(
                            children: [
                              Text(
                                'المبلغ المقبوض فعلياً (Counted Cash):',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colors.onObsidian,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                icon: const Icon(Icons.check_circle_outline,
                                    size: 16),
                                label: const Text('مطابقة تامة للمتوقع',
                                    style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.gold,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _amountController.text =
                                        (expectedCentimes / 100)
                                            .toStringAsFixed(0);
                                  });
                                },
                              ),
                              TextButton.icon(
                                icon: Icon(
                                  _showDenominations
                                      ? Icons.keyboard_arrow_up
                                      : Icons.calculate_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  _showDenominations
                                      ? 'إخفاء الفئات'
                                      : 'عد الفئات',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.gold,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () => setState(() =>
                                    _showDenominations = !_showDenominations),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: false),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.gold,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: colors.obsidianCard,
                              suffixText: 'دج (DZD)',
                              prefixIcon:
                                  const Icon(Icons.attach_money_rounded),
                              border: const OutlineInputBorder(
                                  borderRadius: AppRadius.mdAll),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),

                          // Denominations breakdown (Accordion)
                          if (_showDenominations) ...[
                            const SizedBox(height: AppSpacing.md),
                            Container(
                              padding: const EdgeInsetsDirectional.all(
                                  AppSpacing.md),
                              decoration: BoxDecoration(
                                color: colors.obsidianCard,
                                borderRadius: AppRadius.mdAll,
                                border: Border.all(
                                    color: colors.gold.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تفصيل الفئات النقدية:',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.gold,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children:
                                        _denomControllers.entries.map((entry) {
                                      final denom = entry.key;
                                      final ctrl = entry.value;
                                      return SizedBox(
                                        width: 130,
                                        child: Row(
                                          children: [
                                            Text(
                                              '$denom: ',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            Expanded(
                                              child: SizedBox(
                                                height: 36,
                                                child: TextField(
                                                  controller: ctrl,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                  textAlign: TextAlign.center,
                                                  decoration: InputDecoration(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    filled: true,
                                                    fillColor:
                                                        colors.obsidianSurface,
                                                    border:
                                                        const OutlineInputBorder(
                                                            borderRadius:
                                                                AppRadius
                                                                    .smAll),
                                                  ),
                                                  onChanged: (_) =>
                                                      _recalcFromDenominations(),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: AppSpacing.md),

                          // Difference / Discrepancy Indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md, vertical: 10),
                            decoration: BoxDecoration(
                              color: diffCentimes == 0
                                  ? colors.success.withValues(alpha: 0.12)
                                  : (diffCentimes < 0
                                      ? colors.error.withValues(alpha: 0.12)
                                      : theme.colorScheme.primary
                                          .withValues(alpha: 0.12)),
                              borderRadius: AppRadius.mdAll,
                              border: Border.all(
                                color: diffCentimes == 0
                                    ? colors.success
                                    : (diffCentimes < 0
                                        ? colors.error
                                        : theme.colorScheme.primary),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  diffCentimes == 0
                                      ? Icons.check_circle_rounded
                                      : (diffCentimes < 0
                                          ? Icons.warning_amber_rounded
                                          : Icons.info_outline),
                                  color: diffCentimes == 0
                                      ? colors.success
                                      : (diffCentimes < 0
                                          ? colors.error
                                          : theme.colorScheme.primary),
                                  size: 22,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        diffCentimes == 0
                                            ? 'مطابقة تامة — المبلغ المستلم يطابق العهدة تماماً'
                                            : (diffCentimes < 0
                                                ? 'عجز في العهدة (Shortage): ${DzdFormatter.formatCentimes(diffCentimes.abs())}'
                                                : 'فائض في العهدة (Overage): ${DzdFormatter.formatCentimes(diffCentimes)}'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: diffCentimes == 0
                                              ? colors.success
                                              : (diffCentimes < 0
                                                  ? colors.error
                                                  : theme.colorScheme.primary),
                                        ),
                                      ),
                                      if (diffCentimes != 0)
                                        Text(
                                          'يرجى تدوين سبب الفارق في الملاحظات لإرفاقه في تقرير التدقيق.',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: theme.colorScheme
                                                  .onSurfaceVariant),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // Notes Field
                          TextField(
                            controller: _notesController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: diffCentimes != 0
                                  ? 'ملاحظات وتوضيح الفارق (إلزامي في حال وجود عجز/فائض) *'
                                  : 'ملاحظات التسوية (اختياري)',
                              labelStyle: TextStyle(
                                color: diffCentimes != 0 ? colors.error : null,
                                fontSize: 12,
                              ),
                              filled: true,
                              fillColor: colors.obsidianCard,
                              border: const OutlineInputBorder(
                                  borderRadius: AppRadius.mdAll),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.sm),

                          // Auto print voucher toggle
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                                'طباعة وصل التسوية تلقائياً (وصل حراري 80mm)'),
                            value: _autoPrintVoucher,
                            activeColor: colors.gold,
                            onChanged: (v) =>
                                setState(() => _autoPrintVoucher = v ?? true),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () =>
                      AppStates.loading(message: 'جاري جلب بيانات السائقين...'),
                  error: (e, _) => AppStates.error(
                    'تعذر تحميل السائقين: $e',
                    onRetry: () =>
                        ref.invalidate(pendingDriverSettlementsProvider),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              // Action Buttons
              driversAsync.when(
                data: (drivers) {
                  final selectedDriver = drivers.firstWhere(
                    (d) => d.driverId == _selectedDriverId,
                    orElse: () => drivers.first,
                  );
                  return Row(
                    children: [
                      OutlinedButton(
                        onPressed:
                            _isSubmitting ? null : () => Navigator.pop(context),
                        child: const Text('إلغاء'),
                      ),
                      const Spacer(),
                      GoldButton.icon(
                        icon: Icons.check_circle_rounded,
                        label: _isSubmitting
                            ? 'جاري الترحيل...'
                            : 'تأكيد التسوية وترحيل الكاش',
                        onPressed: _isSubmitting
                            ? null
                            : () => _submitSettlement(
                                  selectedDriver.pendingCashCentimes,
                                  selectedDriver.unsettledOrdersCount,
                                ),
                      ),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
