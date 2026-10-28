import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../services/pos_thermal_printer.dart';

/// A responsive, high-fidelity screen for cashier shift audits, cash counting, and Z-Reports.
class ShiftAuditDialog extends ConsumerStatefulWidget {
  const ShiftAuditDialog({super.key});

  /// Opens the shift audit as a dedicated fullscreen screen route.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ShiftAuditDialog(),
      ),
    );
  }

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

  void _adjustDenomination(int denom, int delta) {
    final controller = _denominationControllers[denom];
    if (controller == null) return;
    final current = int.tryParse(controller.text.trim()) ?? 0;
    final updated = (current + delta).clamp(0, 99999);
    setState(() {
      controller.text = updated.toString();
    });
  }

  void _resetAllDenominations() {
    setState(() {
      for (final c in _denominationControllers.values) {
        c.text = '0';
      }
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

  Future<void> _handleOpenShift() async {
    final user = ref.read(authStateProvider);
    if (user == null) return;
    final pin = await _promptCashierPin();
    if (!mounted || pin == null) return;

    final floatDzd =
        double.tryParse(_openingFloatController.text.trim()) ?? 0.0;
    final floatCentimes = (floatDzd * 100).round();

    ref.read(posActiveShiftProvider.notifier).openShift(
          cashierId: user.id,
          cashierPin: pin,
          cashierName: user.name,
          openingFloatCentimes: floatCentimes,
        );

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'تم فتح الوردية برصيد افتتاحي: ${DzdFormatter.formatCentimes(floatCentimes)}'),
        backgroundColor: context.appColors.success,
      ),
    );
  }

  Future<void> _handlePrintXReport(PosShiftSession shift) async {
    final counted = _calculatedCountedCashCentimes;
    final denomCounts = <int, int>{};
    _denominationControllers.forEach((k, v) {
      denomCounts[k] = int.tryParse(v.text.trim()) ?? 0;
    });

    final tempZReport = ZReportSummary(
      zNumber: shift.zReportNumber,
      cashierName: shift.cashierName,
      openedAt: shift.openedAt,
      closedAt: DateTime.now(),
      openingFloatCentimes: shift.openingFloatCentimes,
      cashSalesCentimes: shift.cashSalesCentimes,
      creditSalesCentimes: shift.creditSalesCentimes,
      totalSalesCentimes: shift.cashSalesCentimes + shift.creditSalesCentimes,
      returnsCentimes: shift.returnsCentimes,
      collectedDebtCashCentimes: shift.collectedDebtCashCentimes,
      supplierPaymentsCashCentimes: shift.supplierPaymentsCashCentimes,
      driverSettlementCashCentimes: shift.driverSettlementCashCentimes,
      expectedCashCentimes: shift.expectedCashInDrawerCentimes,
      countedCashCentimes: counted,
      varianceCentimes: counted - shift.expectedCashInDrawerCentimes,
      denominations: denomCounts,
    );

    await PosThermalPrinterService.printZReport(tempZReport);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تمت طباعة التقرير المرحلي (X-Report) بنجاح!'),
          backgroundColor: context.appColors.success,
        ),
      );
    }
  }

  Future<void> _handleCloseShiftAndZReport(PosShiftSession shift) async {
    final user = ref.read(authStateProvider);
    if (user == null) return;
    final pin = await _promptCashierPin();
    if (!mounted || pin == null) return;

    final counted = _calculatedCountedCashCentimes;
    final denomCounts = <int, int>{};
    _denominationControllers.forEach((k, v) {
      denomCounts[k] = int.tryParse(v.text.trim()) ?? 0;
    });

    final zReport = ref.read(posActiveShiftProvider.notifier).closeShift(
          cashierPin: pin,
          countedCashCentimes: counted,
          denominations: denomCounts,
        );

    if (!mounted) return;
    Navigator.pop(context);

    await PosThermalPrinterService.printZReport(zReport);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تم إغلاق الوردية وطباعة تقرير Z-#${zReport.zNumber} بنجاح!'),
          backgroundColor: context.appColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(posActiveShiftProvider);
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
                    child: Icon(Icons.calculate_rounded,
                        size: 20, color: role.badgeText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift == null
                            ? 'فتح وردية صندوق جديدة'
                            : 'جرد الصندوق وإغلاق الوردية (Z-Report)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        shift == null
                            ? 'نظام إدارة الورديات المالية'
                            : 'تقرير الإقفال المالي #${shift.zReportNumber}',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (shift != null)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(end: AppSpacing.md),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('طباعة X-Report'),
                    onPressed: () => _handlePrintXReport(shift),
                  ),
                ),
            ],
          ),
          body: shift == null
              ? _buildOpenShiftView(theme, colorScheme, colors, role, brand)
              : _buildActiveShiftView(
                  shift, theme, colorScheme, colors, role, brand),
        ),
      ),
    );
  }

  Widget _buildOpenShiftView(ThemeData theme, ColorScheme colorScheme,
      dynamic colors, dynamic role, Color brand) {
    final presets = [5000.0, 10000.0, 15000.0, 20000.0, 30000.0];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: LuxuryCard(
            goldAccent: true,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_open_rounded, size: 56, color: brand),
                AppSpacing.gapMd,
                Text(
                  'بدء جلسة ووردية عمل جديدة',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'يرجى تحديد المبلغ النقدي المتوفر فعليًا في درج الصندوق (Fond de Caisse) قبل بدء استقبال الزبائن:',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                AppSpacing.gapLg,
                TextField(
                  controller: _openingFloatController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'الرصيد الافتتاحي بالدرج (دج) *',
                    prefixIcon: const Icon(Icons.payments_outlined, size: 28),
                    suffixText: 'دج',
                    suffixStyle: const TextStyle(fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerLow,
                    border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
                  ),
                ),
                AppSpacing.gapSm,
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  alignment: WrapAlignment.center,
                  children: presets.map((amount) {
                    return ActionChip(
                      label: Text('${amount.toStringAsFixed(0)} دج'),
                      labelStyle: TextStyle(
                        color: role.badgeText,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: role.badgeBackground,
                      onPressed: () {
                        setState(() {
                          _openingFloatController.text =
                              amount.toStringAsFixed(0);
                        });
                      },
                    );
                  }).toList(),
                ),
                AppSpacing.gapXl,
                GoldButton.icon(
                  icon: Icons.login_rounded,
                  label: 'تأكيد فتح الوردية وبدء البيع',
                  onPressed: _handleOpenShift,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveShiftView(
      PosShiftSession shift,
      ThemeData theme,
      ColorScheme colorScheme,
      dynamic colors,
      dynamic role,
      Color brand) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 880;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Panel: Pulse Metrics, Drawer Balance, Variance and Close Action
              SizedBox(
                width: 420,
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
                        _buildShiftHeaderCard(shift, theme, brand, role),
                        AppSpacing.gapMd,
                        _buildMetricsGrid(shift, theme),
                        AppSpacing.gapMd,
                        _buildVarianceAnalysisCard(shift, theme, colors),
                        AppSpacing.gapLg,
                        GoldButton.icon(
                          onPressed: () => _handleCloseShiftAndZReport(shift),
                          icon: Icons.lock_rounded,
                          label: 'تأكيد الإغلاق النهائي وطباعة Z-Report',
                        ),
                        AppSpacing.gapSm,
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إلغاء والعودة لشاشة البيع'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Right Panel: Denominations Counting Grid
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'جدول جرد وعد الفئات النقدية بالدرج',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'أدخل عدد الأوراق النقدية والقطع المعدنية المحسوبة في الدرج',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('تصفير العداد'),
                                onPressed: _resetAllDenominations,
                              ),
                            ],
                          ),
                          AppSpacing.gapLg,
                          _buildDenominationsGrid(theme, colorScheme, brand),
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
              _buildShiftHeaderCard(shift, theme, brand, role),
              AppSpacing.gapMd,
              _buildMetricsGrid(shift, theme),
              AppSpacing.gapMd,
              _buildVarianceAnalysisCard(shift, theme, colors),
              AppSpacing.gapLg,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'جرد الفئات النقدية:',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: _resetAllDenominations,
                    child: const Text('تصفير'),
                  ),
                ],
              ),
              AppSpacing.gapSm,
              _buildDenominationsGrid(theme, colorScheme, brand),
              AppSpacing.gapXl,
              GoldButton.icon(
                onPressed: () => _handleCloseShiftAndZReport(shift),
                icon: Icons.lock_rounded,
                label: 'تأكيد الإغلاق وطباعة Z-Report',
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
    );
  }

  Widget _buildShiftHeaderCard(
      PosShiftSession shift, ThemeData theme, Color brand, dynamic role) {
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
                'تقرير Z المرتقب: #${shift.zReportNumber}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Chip(
                label: const Text('وردية نشطة', style: TextStyle(fontSize: 11)),
                backgroundColor: brand.withValues(alpha: 0.15),
                side: BorderSide(color: brand.withValues(alpha: 0.3)),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 14),
              const SizedBox(width: 4),
              Text(
                'بدأت في: ${shift.openedAt.toString().substring(11, 16)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: AppSpacing.md),
              const Icon(Icons.person_outline_rounded, size: 14),
              const SizedBox(width: 4),
              Text(
                'الكاشير: ${shift.cashierName}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(PosShiftSession shift, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حركة النقد والعمليات المسجلة:',
            style:
                theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Divider(height: 16),
          _metricRow('الرصيد الافتتاحي (Fond)', shift.openingFloatCentimes),
          _metricRow('المبيعات النقدية (+)', shift.cashSalesCentimes),
          _metricRow('مبيعات الدين (على الحساب)', shift.creditSalesCentimes),
          if (shift.collectedDebtCashCentimes > 0)
            _metricRow(
                'تحصيل ديون الزبائن (+)', shift.collectedDebtCashCentimes),
          if (shift.driverSettlementCashCentimes > 0)
            _metricRow(
                'تسويات عهدة السائقين (+)', shift.driverSettlementCashCentimes),
          if (shift.supplierPaymentsCashCentimes > 0)
            _metricRow('مدفوعات الموردين (-)', -shift.supplierPaymentsCashCentimes,
                isNegative: true),
          if (shift.returnsCentimes > 0)
            _metricRow('المسترجعات للزبائن (-)', -shift.returnsCentimes,
                isNegative: true),
        ],
      ),
    );
  }

  Widget _metricRow(String title, int centimes, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12),
          ),
          DzdPriceTag(
            centimes: centimes.abs(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isNegative ? Colors.redAccent : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVarianceAnalysisCard(
      PosShiftSession shift, ThemeData theme, dynamic colors) {
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
            : (isOver
                ? colors.warningContainer
                : theme.colorScheme.errorContainer),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: isMatch
              ? colors.success
              : (isOver ? colors.warning : theme.colorScheme.error),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المتوقع في الصندوق:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: isMatch
                      ? colors.onSuccessContainer
                      : (isOver
                          ? colors.onWarningContainer
                          : theme.colorScheme.onErrorContainer),
                ),
              ),
              DzdPriceTag(
                centimes: expected,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المعدود فعليًا (الآن):',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: isMatch
                      ? colors.onSuccessContainer
                      : (isOver
                          ? colors.onWarningContainer
                          : theme.colorScheme.onErrorContainer),
                ),
              ),
              DzdPriceTag(
                centimes: counted,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isMatch
                    ? 'الدرج متطابق تمامًا (0 دج)'
                    : (isOver
                        ? 'فائض نقدي بالدرج (+)'
                        : 'عجز نقدي بالدرج (-)'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isMatch
                      ? colors.onSuccessContainer
                      : (isOver
                          ? colors.onWarningContainer
                          : theme.colorScheme.onErrorContainer),
                ),
              ),
              DzdPriceTag(
                centimes: variance.abs(),
                color: isMatch
                    ? colors.onSuccessContainer
                    : (isOver
                        ? colors.onWarningContainer
                        : theme.colorScheme.onErrorContainer),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDenominationsGrid(
      ThemeData theme, ColorScheme colorScheme, Color brand) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 550 ? 2 : 1;
      final entries = _denominationControllers.entries.toList();

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 3.2,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
        ),
        itemCount: entries.length,
        itemBuilder: (context, idx) {
          final entry = entries[idx];
          final denom = entry.key;
          final controller = entry.value;
          final count = int.tryParse(controller.text.trim()) ?? 0;
          final subtotalDzd = count * denom;

          return Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              children: [
                // Denomination Badge
                Container(
                  width: 80,
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    '$denom دج',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Stepper Controls (- / +)
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove, size: 16),
                  onPressed: () => _adjustDenomination(denom, -1),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add, size: 16),
                  onPressed: () => _adjustDenomination(denom, 1),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Subtotal
                SizedBox(
                  width: 90,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'المجموع:',
                        style: TextStyle(fontSize: 10),
                      ),
                      Text(
                        '$subtotalDzd دج',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: count > 0 ? brand : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}
