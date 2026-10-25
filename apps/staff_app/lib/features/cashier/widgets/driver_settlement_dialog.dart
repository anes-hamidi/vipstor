import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';
import '../services/pos_thermal_printer.dart';

/// A responsive, high-fidelity screen for settling delivery drivers' COD collections and drawer intake.
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

  /// Opens the driver settlement screen as a dedicated fullscreen screen route.
  static Future<void> show(
    BuildContext context, {
    String? initialDriverId,
    String? initialDriverName,
    required String receiverId,
    required String receiverName,
    required String receiverRole,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => DriverSettlementDialog(
          initialDriverId: initialDriverId,
          initialDriverName: initialDriverName,
          receiverId: receiverId,
          receiverName: receiverName,
          receiverRole: receiverRole,
        ),
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

      if (widget.receiverRole == 'cashier' && countedCentimes > 0) {
        ref.read(posActiveShiftProvider.notifier).registerDriverSettlement(
              cashCentimes: countedCentimes,
            );
      }

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
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final role = context.roleTheme;
    final brand = role.roleBrandColor;
    final driversAsync = ref.watch(pendingDriverSettlementsProvider);

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
              onPressed:
                  _isSubmitting ? null : () => Navigator.pop(context),
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
                    child: Icon(Icons.handshake_rounded,
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
                        'تسوية عهدة سائق التوصيل (Cash Close)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'المستلم: ${widget.receiverName} (${widget.receiverRole == "cashier" ? "أمين الصندوق" : "المشرف"})',
                        style:
                            theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: driversAsync.when(
            loading: () =>
                const Center(child: AppLoadingView(message: 'جاري جلب بيانات السائقين...')),
            error: (e, _) => Center(
              child: AppErrorView(
                message: 'تعذر تحميل السائقين: $e',
                onRetry: () =>
                    ref.invalidate(pendingDriverSettlementsProvider),
              ),
            ),
            data: (drivers) {
              if (drivers.isEmpty) {
                return const Center(
                  child: AppEmptyView(
                    icon: Icons.local_shipping_outlined,
                    title: 'لا يوجد سائقو توصيل مسجلون',
                    description: 'قم بإضافة سائقين أولاً لتمكين تسوية العهدة.',
                  ),
                );
              }

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

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 840;

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Column: Drivers List & Selected Driver Orders Preview
                        SizedBox(
                          width: 400,
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
                                  Text(
                                    'اختر سائق التوصيل:',
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  ...drivers.map((d) {
                                    final isSel = d.driverId == _selectedDriverId;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 6),
                                      child: ListTile(
                                        selected: isSel,
                                        selectedTileColor: colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.25),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: AppRadius.mdAll,
                                          side: BorderSide(
                                            color: isSel
                                                ? brand
                                                : colorScheme.outlineVariant
                                                    .withValues(alpha: 0.4),
                                          ),
                                        ),
                                        onTap: () => _onDriverSelected(d),
                                        leading: CircleAvatar(
                                          backgroundColor: isSel
                                              ? brand
                                              : colorScheme
                                                  .surfaceContainerHighest,
                                          child: Icon(
                                            Icons.person_pin_circle_rounded,
                                            size: 20,
                                            color: isSel
                                                ? Colors.white
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        title: Text(
                                          d.driverName,
                                          style: TextStyle(
                                            fontWeight: isSel
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'طلبات غير مسواة: ${d.unsettledOrdersCount}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        trailing: DzdPriceTag(
                                          centimes: d.pendingCashCentimes,
                                          color: d.pendingCashCentimes > 0
                                              ? brand
                                              : null,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    );
                                  }),
                                  const Divider(height: 24),
                                  _buildOrdersListPreview(selectedDriver.driverId,
                                      theme, colorScheme, colors),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Right Column: Counting, Denominations, Discrepancy, Actions
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 620),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildDriverSummaryBanner(
                                        selectedDriver, theme, colors, brand),
                                    AppSpacing.gapLg,
                                    _buildCountingSection(
                                        expectedCentimes,
                                        theme,
                                        colorScheme,
                                        colors,
                                        brand),
                                    AppSpacing.gapLg,
                                    _buildDifferenceIndicator(
                                        diffCentimes, theme, colors),
                                    AppSpacing.gapLg,
                                    TextField(
                                      controller: _notesController,
                                      maxLines: 2,
                                      decoration: InputDecoration(
                                        labelText: diffCentimes != 0
                                            ? 'ملاحظات وتوضيح الفارق (إلزامي في حال وجود عجز/فائض) *'
                                            : 'ملاحظات التسوية (اختياري)',
                                        labelStyle: TextStyle(
                                          color: diffCentimes != 0
                                              ? colors.error
                                              : null,
                                          fontSize: 12,
                                        ),
                                        filled: true,
                                        fillColor:
                                            colorScheme.surfaceContainerLow,
                                        border: const OutlineInputBorder(
                                            borderRadius: AppRadius.mdAll),
                                      ),
                                    ),
                                    AppSpacing.gapMd,
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'طباعة وصل تسوية العهدة تلقائيًا (80mm)',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: const Text(
                                        'إصدار سند استلام نقدية موقع للطرفين',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      value: _autoPrintVoucher,
                                      onChanged: (v) => setState(() =>
                                          _autoPrintVoucher = v ?? true),
                                    ),
                                    AppSpacing.gapLg,
                                    GoldButton.icon(
                                      icon: _isSubmitting
                                          ? Icons.hourglass_top_rounded
                                          : Icons.check_circle_rounded,
                                      label: _isSubmitting
                                          ? 'جاري الترحيل...'
                                          : 'تأكيد التسوية وترحيل الكاش للدرج',
                                      onPressed: _isSubmitting
                                          ? null
                                          : () => _submitSettlement(
                                                expectedCentimes,
                                                selectedDriver
                                                    .unsettledOrdersCount,
                                              ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  // Mobile Layout
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMobileDriverSelector(drivers, theme, colors, brand),
                        AppSpacing.gapMd,
                        _buildDriverSummaryBanner(
                            selectedDriver, theme, colors, brand),
                        AppSpacing.gapMd,
                        _buildOrdersListPreview(
                            selectedDriver.driverId, theme, colorScheme, colors),
                        AppSpacing.gapMd,
                        _buildCountingSection(
                            expectedCentimes, theme, colorScheme, colors, brand),
                        AppSpacing.gapMd,
                        _buildDifferenceIndicator(diffCentimes, theme, colors),
                        AppSpacing.gapMd,
                        TextField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: diffCentimes != 0
                                ? 'ملاحظات وتوضيح الفارق *'
                                : 'ملاحظات التسوية (اختياري)',
                            filled: true,
                            fillColor: colorScheme.surfaceContainerLow,
                            border: const OutlineInputBorder(
                                borderRadius: AppRadius.mdAll),
                          ),
                        ),
                        AppSpacing.gapSm,
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('طباعة وصل التسوية تلقائياً'),
                          value: _autoPrintVoucher,
                          onChanged: (v) =>
                              setState(() => _autoPrintVoucher = v ?? true),
                        ),
                        AppSpacing.gapLg,
                        GoldButton.icon(
                          icon: Icons.check_circle_rounded,
                          label: _isSubmitting
                              ? 'جاري الترحيل...'
                              : 'تأكيد التسوية وترحيل الكاش',
                          onPressed: _isSubmitting
                              ? null
                              : () => _submitSettlement(
                                    expectedCentimes,
                                    selectedDriver.unsettledOrdersCount,
                                  ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMobileDriverSelector(List<DriverSettlementSummaryEntity> drivers,
      ThemeData theme, dynamic colors, Color brand) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: drivers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final d = drivers[i];
          final isSel = d.driverId == _selectedDriverId;
          return ChoiceChip(
            label: Text('${d.driverName} (${DzdFormatter.formatCentimes(d.pendingCashCentimes)})'),
            selected: isSel,
            onSelected: (_) => _onDriverSelected(d),
          );
        },
      ),
    );
  }

  Widget _buildDriverSummaryBanner(DriverSettlementSummaryEntity selectedDriver,
      ThemeData theme, dynamic colors, Color brand) {
    return LuxuryCard(
      goldAccent: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الكاش المتوقع بالعهدة (Expected):',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 4),
              DzdPriceTag.hero(
                centimes: selectedDriver.pendingCashCentimes,
                gold: true,
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: brand.withValues(alpha: 0.12),
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: brand.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'طلبات غير مسواة',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${selectedDriver.unsettledOrdersCount} طلبات',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersListPreview(String driverId, ThemeData theme,
      ColorScheme colorScheme, dynamic colors) {
    final ordersAsync = ref.watch(driverUnsettledOrdersProvider(driverId));
    return ordersAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: ExpansionTile(
            title: Text(
              'الطلبات المشمولة بالعهدة (${orders.length}):',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final o = orders[idx];
                    return ListTile(
                      dense: true,
                      title: Text(
                        'طلب #${o.orderNumber ?? o.id.substring(0, 6)} - ${o.customerName ?? "زبون"}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      trailing: DzdPriceTag(
                        centimes: o.paidAmountCentimes,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildCountingSection(int expectedCentimes, ThemeData theme,
      ColorScheme colorScheme, dynamic colors, Color brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'المبلغ المقبوض فعليًا (Counted Cash):',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('مطابقة تامة'),
                  onPressed: () {
                    setState(() {
                      _amountController.text =
                          (expectedCentimes / 100).toStringAsFixed(0);
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
                  label: Text(_showDenominations ? 'إخفاء الفئات' : 'عد الفئات'),
                  onPressed: () => setState(
                      () => _showDenominations = !_showDenominations),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _amountController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: false),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            suffixText: 'دج (DZD)',
            prefixIcon: const Icon(Icons.attach_money_rounded, size: 28),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_showDenominations) ...[
          AppSpacing.gapMd,
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تفصيل عد الفئات النقدية:',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: _denomControllers.entries.map((entry) {
                    final denom = entry.key;
                    final ctrl = entry.value;
                    return SizedBox(
                      width: 140,
                      child: Row(
                        children: [
                          Text(
                            '$denom: ',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => _recalcFromDenominations(),
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
      ],
    );
  }

  Widget _buildDifferenceIndicator(
      int diffCentimes, ThemeData theme, dynamic colors) {
    final isMatch = diffCentimes == 0;
    final isShort = diffCentimes < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMatch
            ? colors.successContainer
            : (isShort ? colors.errorContainer : colors.warningContainer),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: isMatch
              ? colors.success
              : (isShort ? colors.error : colors.warning),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isMatch
                ? Icons.check_circle_rounded
                : (isShort
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded),
            color: isMatch
                ? colors.onSuccessContainer
                : (isShort
                    ? colors.onErrorContainer
                    : colors.onWarningContainer),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMatch
                      ? 'مطابقة تامة — المبلغ المستلم يطابق العهدة تماماً'
                      : (isShort
                          ? 'عجز في العهدة (Shortage): ${DzdFormatter.formatCentimes(diffCentimes.abs())}'
                          : 'فائض في العهدة (Overage): ${DzdFormatter.formatCentimes(diffCentimes)}'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isMatch
                        ? colors.onSuccessContainer
                        : (isShort
                            ? colors.onErrorContainer
                            : colors.onWarningContainer),
                  ),
                ),
                if (!isMatch)
                  const Text(
                    'يرجى تدوين سبب الفارق في حقل الملاحظات أسفله لإرفاقه في تقرير التدقيق.',
                    style: TextStyle(fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
