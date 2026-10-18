import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../services/pos_thermal_printer.dart';

class ShiftAuditDialog extends ConsumerStatefulWidget {
  const ShiftAuditDialog({super.key});

  @override
  ConsumerState<ShiftAuditDialog> createState() => _ShiftAuditDialogState();
}

class _ShiftAuditDialogState extends ConsumerState<ShiftAuditDialog> {
  // Opening float controller
  final _openingFloatController = TextEditingController(text: '10000');

  // Denominations Map: Value in DZD -> Count controller
  final Map<int, TextEditingController> _denominationControllers = {
    2000: TextEditingController(text: '0'),
    1000: TextEditingController(text: '0'),
    500: TextEditingController(text: '0'),
    200: TextEditingController(text: '0'),
    100: TextEditingController(text: '0'),
    50: TextEditingController(text: '0'),
    20: TextEditingController(text: '0'),
    10: TextEditingController(text: '0'),
  };

  @override
  void dispose() {
    _openingFloatController.dispose();
    for (final c in _denominationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _calculatedCountedCashCentimes {
    int totalDzd = 0;
    _denominationControllers.forEach((denomDzd, controller) {
      final count = int.tryParse(controller.text.trim()) ?? 0;
      totalDzd += (denomDzd * count);
    });
    return totalDzd * 100;
  }

  void _handleOpenShift() {
    final user = ref.read(authStateProvider);
    final floatDzd = double.tryParse(_openingFloatController.text.trim()) ?? 0.0;
    final floatCentimes = (floatDzd * 100).round();

    final cashierId = user?.id ?? '';
    final cashierName = user?.name ?? 'أمين الصندوق';

    ref.read(posActiveShiftProvider.notifier).openShift(
          cashierId: cashierId,
          cashierName: cashierName,
          openingFloatCentimes: floatCentimes,
        );

    final currentShift = ref.read(posActiveShiftProvider);
    if (currentShift != null) {
      ref.read(staffAuditLoggerProvider).logShiftOpened(
            cashierId: cashierId,
            cashierName: cashierName,
            openingFloatCentimes: floatCentimes,
            zReportNumber: currentShift.zReportNumber,
          );
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم فتح الوردية برصيد افتتاحي: ${DzdFormatter.formatCentimes(floatCentimes)}'),
        backgroundColor: context.appColors.success,
      ),
    );
  }

  void _handleCloseShiftAndZReport(PosShiftSession shift) async {
    final counted = _calculatedCountedCashCentimes;
    final denomCounts = <int, int>{};
    _denominationControllers.forEach((k, v) {
      denomCounts[k] = int.tryParse(v.text.trim()) ?? 0;
    });

    final zReport = ref.read(posActiveShiftProvider.notifier).closeShift(
          countedCashCentimes: counted,
          denominations: denomCounts,
        );

    // Audit log shift close
    ref.read(staffAuditLoggerProvider).logShiftClosed(
          cashierId: shift.cashierId,
          cashierName: shift.cashierName,
          zNumber: zReport.zNumber,
          expectedCentimes: zReport.expectedCashCentimes,
          countedCentimes: zReport.countedCashCentimes,
          varianceCentimes: zReport.varianceCentimes,
          cashSalesCentimes: zReport.cashSalesCentimes,
          creditSalesCentimes: zReport.creditSalesCentimes,
          debtCollectedCentimes: zReport.collectedDebtCashCentimes,
          supplierPaymentsCentimes: zReport.supplierPaymentsCashCentimes,
        );

    Navigator.pop(context);

    // Prompt for print
    await PosThermalPrinterService.printZReport(zReport);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إغلاق الوردية وطباعة تقرير Z-#${zReport.zNumber} بنجاح!'),
          backgroundColor: context.appColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(posActiveShiftProvider);
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppGradients.gold,
                          borderRadius: AppRadius.smAll,
                          boxShadow: [AppShadows.goldGlowSm],
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.point_of_sale_rounded,
                              size: 18, color: Color(0xFF1A1400)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          shift == null ? 'فتح وردية صندوق جديدة' : 'جرد الصندوق وإغلاق الوردية (Z-Report)',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              if (shift == null)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_open_rounded, size: 64, color: Colors.blueGrey),
                      AppSpacing.gapLg,
                      Text(
                        'لا توجد وردية مفتوحة حاليًا',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'يرجى تحديد المبلغ النقدي الافتتاحي في درج الصندوق (Fond de caisse) لبدء العمليات:',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      AppSpacing.gapLg,
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: TextField(
                          controller: _openingFloatController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'الرصيد الافتتاحي (دج) *',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                        ),
                      ),
                      AppSpacing.gapXl,
                      GoldButton.icon(
                        icon: Icons.login_rounded,
                        label: 'فتح الوردية وبدء البيع',
                        onPressed: _handleOpenShift,
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Shift Summary Card
                        LuxuryCard(
                          goldAccent: true,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(child: Text('رقم تقرير Z المرتقب: #${shift.zReportNumber}',
                                      style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                  Text('افتتحت في: ${shift.openedAt.toString().substring(11, 16)}',
                                      style: theme.textTheme.bodySmall),
                                ],
                              ),
                              const Divider(height: 16),
                              Wrap(
                                spacing: AppSpacing.md,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  _summaryMetric('الرصيد الافتتاحي', shift.openingFloatCentimes),
                                  _summaryMetric('المبيعات النقدية', shift.cashSalesCentimes),
                                  _summaryMetric('مبيعات الدين', shift.creditSalesCentimes),
                                  if (shift.collectedDebtCashCentimes > 0)
                                    _summaryMetric('سداد ديون الزبائن (+)', shift.collectedDebtCashCentimes),
                                  if (shift.driverSettlementCashCentimes > 0)
                                    _summaryMetric('تسويات عهدة السائقين (+)', shift.driverSettlementCashCentimes),
                                  if (shift.supplierPaymentsCashCentimes > 0)
                                    _summaryMetric('مدفوعات الموردين (-)', -shift.supplierPaymentsCashCentimes, isNegative: true),
                                  _summaryMetric('المسترجعات', -shift.returnsCentimes, isNegative: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                        AppSpacing.gapMd,
                        Text(
                          'جدول جرد وعد الفئات النقدية في الدرج:',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        AppSpacing.gapSm,
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 3.5,
                            crossAxisSpacing: AppSpacing.md,
                            mainAxisSpacing: AppSpacing.sm,
                          ),
                          itemCount: _denominationControllers.length,
                          itemBuilder: (context, idx) {
                            final denom = _denominationControllers.keys.elementAt(idx);
                            final controller = _denominationControllers[denom]!;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.colorScheme.outlineVariant),
                                borderRadius: AppRadius.smAll,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      '$denom دج',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  const Text('x'),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      '${((int.tryParse(controller.text.trim()) ?? 0) * denom)} دج',
                                      textAlign: TextAlign.end,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        AppSpacing.gapLg,
                        // Cash Variance Live Analysis
                        Builder(
                          builder: (context) {
                            final counted = _calculatedCountedCashCentimes;
                            final expected = shift.expectedCashInDrawerCentimes;
                            final variance = counted - expected;
                            final isMatch = variance == 0;
                            final isOver = variance > 0;

                            return Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: isMatch
                                    ? colors.successContainer
                                    : (isOver ? colors.warningContainer : theme.colorScheme.errorContainer),
                                borderRadius: AppRadius.mdAll,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('المتوقع بالدرج: ${DzdFormatter.formatCentimes(expected)}',
                                            style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                        Text('المحسوب فعليًا: ${DzdFormatter.formatCentimes(counted)}',
                                            style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        isMatch ? 'الدرج متطابق تمامًا (0 دج)' : (isOver ? 'فائض نقدي بالدرج' : 'عجز نقدي بالدرج'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isMatch
                                              ? colors.onSuccessContainer
                                              : (isOver ? colors.onWarningContainer : theme.colorScheme.onErrorContainer),
                                        ),
                                      ),
                                      DzdPriceTag(
                                        centimes: variance.abs(),
                                        color: isMatch
                                            ? colors.onSuccessContainer
                                            : (isOver ? colors.onWarningContainer : theme.colorScheme.onErrorContainer),
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              if (shift != null) ...[
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء والعودة للبيع'),
                      ),
                    ),
                    Flexible(
                      child: GoldButton.icon(
                        onPressed: () => _handleCloseShiftAndZReport(shift),
                        icon: Icons.lock_rounded,
                        label: 'تأكيد الإغلاق وطباعة Z-Report',
                      ),
                    ),                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryMetric(String label, int centimes, {bool isNegative = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        DzdPriceTag(
          centimes: centimes.abs(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }
}
