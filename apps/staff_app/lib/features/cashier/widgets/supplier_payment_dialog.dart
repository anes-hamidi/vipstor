import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';
import '../services/pos_thermal_printer.dart';

/// A responsive, high-fidelity screen for paying suppliers in cash and printing disbursal vouchers.
class SupplierPaymentDialog extends ConsumerStatefulWidget {
  final SupplierProfileEntity? initialSupplier;
  final String payerId;
  final String payerName;
  final String payerRole; // 'cashier' or 'moderator'

  const SupplierPaymentDialog({
    super.key,
    this.initialSupplier,
    required this.payerId,
    required this.payerName,
    required this.payerRole,
  });

  /// Opens supplier payment screen as a dedicated fullscreen screen route.
  static Future<void> show(
    BuildContext context, {
    SupplierProfileEntity? initialSupplier,
    required String payerId,
    required String payerName,
    required String payerRole,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => SupplierPaymentDialog(
          initialSupplier: initialSupplier,
          payerId: payerId,
          payerName: payerName,
          payerRole: payerRole,
        ),
      ),
    );
  }

  @override
  ConsumerState<SupplierPaymentDialog> createState() =>
      _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends ConsumerState<SupplierPaymentDialog> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();
  final _pinController = TextEditingController();

  SupplierProfileEntity? _selectedSupplier;
  bool _autoPrintVoucher = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedSupplier = widget.initialSupplier;
    if (_selectedSupplier != null &&
        _selectedSupplier!.currentBalanceCentimes > 0) {
      _amountController.text =
          (_selectedSupplier!.currentBalanceCentimes / 100).toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  int get _enteredCentimes {
    final val = double.tryParse(_amountController.text.trim()) ?? 0;
    return (val * 100).round();
  }

  void _onSupplierSelected(SupplierProfileEntity supplier) {
    setState(() {
      _selectedSupplier = supplier;
      if (supplier.currentBalanceCentimes > 0) {
        _amountController.text =
            (supplier.currentBalanceCentimes / 100).toStringAsFixed(0);
      } else {
        _amountController.clear();
      }
    });
  }

  void _applyPresetPercent(double factor) {
    if (_selectedSupplier == null) return;
    final amountCentimes =
        (_selectedSupplier!.currentBalanceCentimes * factor).round();
    _amountController.text = (amountCentimes / 100).toStringAsFixed(0);
    setState(() {});
  }

  Future<void> _handlePayment() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى اختيار المورد أولاً'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final payCentimes = _enteredCentimes;
    if (payCentimes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى إدخال مبلغ صحيح لسداد مستحقات المورد'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final callerPin = _pinController.text.trim();
    if (callerPin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('يرجى إدخال رمز PIN الخاص بك (4 أرقام على الأقل)'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final isCashier = widget.payerRole.toLowerCase().contains('cashier');
    if (isCashier) {
      final activeShift = ref.read(posActiveShiftProvider);
      if (activeShift == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'خطأ: لا يوجد وردية كاشير مفتوحة حالياً لتسديد المبلغ منها!'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      if (payCentimes > activeShift.expectedCashInDrawerCentimes) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber),
                SizedBox(width: 8),
                Text('تنبيه: عجز بالدرج'),
              ],
            ),
            content: Text(
              'المبلغ المطلوب صرفه (${DzdFormatter.formatCentimes(payCentimes)}) أكبر من النقد المتوفر بالدرج حالياً (${DzdFormatter.formatCentimes(activeShift.expectedCashInDrawerCentimes)}).\nهل أنت متأكد من المتابعة وتسجيل خروج نقدية؟',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade800),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تأكيد الصرف'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    if (!mounted) return;

    if (payCentimes > _selectedSupplier!.currentBalanceCentimes &&
        _selectedSupplier!.currentBalanceCentimes > 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
          title: const Text('تنبيه: سداد يفوق الدين'),
          content: Text(
            'المبلغ المدخل (${DzdFormatter.formatCentimes(payCentimes)}) يفوق مستحقات المورد الحالية (${DzdFormatter.formatCentimes(_selectedSupplier!.currentBalanceCentimes)}).\nهل تود المتابعة؟',
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
      final repo = ref.read(purchaseRepositoryProvider);
      final notes = _notesController.text.trim();

      final result = await repo.recordSupplierPayment(
        supplierId: _selectedSupplier!.id,
        amountCentimes: payCentimes,
        payerUserId: widget.payerId,
        payerName: widget.payerName,
        payerRole: widget.payerRole,
        callerPin: callerPin,
        notes: notes,
      );

      if (isCashier) {
        ref.read(posActiveShiftProvider.notifier).registerSupplierCashPayment(
              cashCentimes: payCentimes,
            );
      }

      ref.invalidate(suppliersWithBalancesProvider);
      ref.invalidate(suppliersProvider);
      ref.invalidate(purchasesListProvider);

      if (_autoPrintVoucher && mounted) {
        try {
          await PosThermalPrinterService.printSupplierPaymentVoucher(
            result: result,
            supplier: _selectedSupplier!,
            payerName: widget.payerName,
            payerRole: widget.payerRole,
          );
        } catch (e) {
          debugPrint('Failed to auto print supplier voucher: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context, result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                    'تم تسجيل سداد مستحقات المورد نقدًا بنجاح: ${DzdFormatter.formatCentimes(payCentimes)}'),
              ],
            ),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تسجيل السداد: ${e.toString()}'),
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
    final isCashier = widget.payerRole.toLowerCase().contains('cashier');
    final activeShift = ref.watch(posActiveShiftProvider);

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
                    child: Icon(Icons.payments_rounded,
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
                        'سداد مستحقات الموردين (نقدًا)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'المسؤول: ${widget.payerName} | الدور: ${widget.payerRole}',
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
              if (isCashier && activeShift != null)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(end: AppSpacing.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.successContainer,
                      borderRadius: AppRadius.pillAll,
                      border: Border.all(color: colors.success),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.point_of_sale_rounded,
                            size: 16, color: colors.onSuccessContainer),
                        const SizedBox(width: 6),
                        Text(
                          'نقد الدرج: ${DzdFormatter.formatCentimes(activeShift.expectedCashInDrawerCentimes)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colors.onSuccessContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 840;

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left: Supplier Search & Balance List
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
                        child: _buildSupplierSelector(theme, colorScheme, colors),
                      ),
                    ),
                    // Right: Payment Form & Execution
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildPaymentForm(
                                    theme, colorScheme, colors, brand),
                                AppSpacing.gapLg,
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'طباعة سند صرف فوري (80mm Thermal Voucher)',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: const Text(
                                    'إخراج إيصال الصرف المالي الموقع من الكاشير والمورد',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  value: _autoPrintVoucher,
                                  onChanged: (v) => setState(
                                      () => _autoPrintVoucher = v ?? true),
                                ),
                                AppSpacing.gapLg,
                                GoldButton.icon(
                                  onPressed:
                                      _isSubmitting ? null : _handlePayment,
                                  icon: _isSubmitting
                                      ? Icons.hourglass_top_rounded
                                      : Icons.check_circle_rounded,
                                  label: _isSubmitting
                                      ? 'جاري تسجيل الصرف...'
                                      : 'تأكيد وصرف المبلغ نقدًا للمورد',
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
                    SizedBox(
                      height: 260,
                      child: _buildSupplierSelector(theme, colorScheme, colors),
                    ),
                    const Divider(height: 32),
                    _buildPaymentForm(theme, colorScheme, colors, brand),
                    AppSpacing.gapMd,
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('طباعة سند صرف فوري'),
                      value: _autoPrintVoucher,
                      onChanged: (v) =>
                          setState(() => _autoPrintVoucher = v ?? true),
                    ),
                    AppSpacing.gapLg,
                    GoldButton.icon(
                      onPressed: _isSubmitting ? null : _handlePayment,
                      icon: Icons.check_circle_rounded,
                      label: _isSubmitting ? 'جاري الصرف...' : 'تأكيد الصرف نقدًا',
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

  Widget _buildSupplierSelector(
      ThemeData theme, ColorScheme colorScheme, dynamic colors) {
    final suppliersAsync = ref.watch(suppliersWithBalancesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اختيار المورد المستحق:',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث باسم المورد أو رقم الهاتف...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: colorScheme.surfaceContainer,
                  border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: suppliersAsync.when(
            loading: () =>
                const Center(child: AppLoadingView(message: 'جاري تحميل الموردين...')),
            error: (err, _) => Center(
              child: AppErrorView(
                message: 'تعذر تحميل قائمة الموردين: $err',
                onRetry: () => ref.invalidate(suppliersWithBalancesProvider),
              ),
            ),
            data: (suppliers) {
              final query = _searchController.text.trim().toLowerCase();
              final filtered = suppliers.where((s) {
                if (query.isEmpty) return true;
                return s.name.toLowerCase().contains(query) ||
                    s.phone.contains(query);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: AppEmptyView(
                    icon: Icons.business_outlined,
                    title: 'لا يوجد موردين',
                    description: 'لم يتم العثور على موردين مطابقين.',
                  ),
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final s = filtered[index];
                  final isSelected = _selectedSupplier?.id == s.id;
                  final hasDebt = s.currentBalanceCentimes > 0;

                  return ListTile(
                    selected: isSelected,
                    selectedTileColor:
                        colorScheme.primaryContainer.withValues(alpha: 0.25),
                    onTap: () => _onSupplierSelected(s),
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      child: Text(
                        s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S',
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      s.name,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                    subtitle: s.phone.isNotEmpty
                        ? Text(s.phone, style: theme.textTheme.bodySmall)
                        : null,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        DzdPriceTag(
                          centimes: s.currentBalanceCentimes,
                          color: hasDebt ? colors.error : colors.success,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          hasDebt ? 'مستحق له' : 'خالص',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: hasDebt ? colors.error : colors.success,
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
      ],
    );
  }

  Widget _buildPaymentForm(ThemeData theme, ColorScheme colorScheme,
      dynamic colors, Color brand) {
    final balanceCentimes = _selectedSupplier?.currentBalanceCentimes ?? 0;
    final payCentimes = _enteredCentimes;
    final remainingCentimes = balanceCentimes - payCentimes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selected Supplier Summary Card
        LuxuryCard(
          goldAccent: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _selectedSupplier?.name ?? 'يرجى اختيار المورد من القائمة',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Chip(
                    label: const Text('دفع نقدًا فقط (Cash Only)'),
                    backgroundColor: brand.withValues(alpha: 0.12),
                    side: BorderSide(color: brand.withValues(alpha: 0.3)),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('إجمالي مستحقات المورد الحالية:'),
                  DzdPriceTag(
                    centimes: balanceCentimes,
                    color: balanceCentimes > 0 ? colors.error : null,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        // Quick Presets
        if (balanceCentimes > 0) ...[
          Text('نسب التسديد السريع:',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildPresetButton('25%', () => _applyPresetPercent(0.25)),
              const SizedBox(width: 6),
              _buildPresetButton('50%', () => _applyPresetPercent(0.50)),
              const SizedBox(width: 6),
              _buildPresetButton('75%', () => _applyPresetPercent(0.75)),
              const SizedBox(width: 6),
              _buildPresetButton(
                  '100% (تسديد كامل)', () => _applyPresetPercent(1.00),
                  isPrimary: true, brand: brand),
            ],
          ),
          AppSpacing.gapLg,
        ],

        // Amount Input
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: 'المبلغ المراد صرفه نقدًا (دج) *',
            suffixText: 'دج',
            prefixIcon: const Icon(Icons.attach_money_rounded, size: 28),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
          onChanged: (_) => setState(() {}),
        ),
        AppSpacing.gapMd,

        // Remaining Balance Live Preview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: remainingCentimes <= 0
                ? colors.successContainer
                : colors.warningContainer,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: remainingCentimes <= 0 ? colors.success : colors.warning,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                remainingCentimes <= 0
                    ? 'الرصيد المتبقي بعد السداد (خالص):'
                    : 'الرصيد المتبقي بذمة المحل:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: remainingCentimes <= 0
                      ? colors.onSuccessContainer
                      : colors.onWarningContainer,
                ),
              ),
              DzdPriceTag(
                centimes: remainingCentimes.clamp(0, double.infinity).toInt(),
                color: remainingCentimes <= 0
                    ? colors.onSuccessContainer
                    : colors.onWarningContainer,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,

        // PIN Field
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(
            labelText: 'رمز PIN الخاص بك لتأكيد العملية *',
            hintText: '••••',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            helperText: 'مطلوب لحماية الصندوق وتسجيل التدقيق المالي',
            counterText: '',
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
        AppSpacing.gapMd,

        // Notes
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'ملاحظات وسند الصرف (اختياري)',
            hintText: 'مثال: تسديد دفعة نقدية عن فاتورة استلام شحنة...',
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetButton(String label, VoidCallback onTap,
      {bool isPrimary = false, Color? brand}) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          backgroundColor: isPrimary ? brand?.withValues(alpha: 0.15) : null,
          side: BorderSide(
            color: isPrimary && brand != null ? brand : Colors.grey.shade400,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isPrimary && brand != null ? brand : null,
          ),
        ),
      ),
    );
  }
}
