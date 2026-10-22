import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import 'package:core/core.dart';
import '../../../providers/staff_providers.dart';
import '../services/pos_thermal_printer.dart';

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

  static Future<void> show(
    BuildContext context, {
    SupplierProfileEntity? initialSupplier,
    required String payerId,
    required String payerName,
    required String payerRole,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SupplierPaymentDialog(
        initialSupplier: initialSupplier,
        payerId: payerId,
        payerName: payerName,
        payerRole: payerRole,
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
          content: const Text('يرجى إدخال رمز PIN الخاص بك (4 أرقام على الأقل)'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Role-specific validations:
    // If Cashier: check that active shift exists and drawer has enough cash
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

      // If cashier, register cash withdrawal in the active drawer
      if (isCashier) {
        ref.read(posActiveShiftProvider.notifier).registerSupplierCashPayment(
              cashCentimes: payCentimes,
            );
      }

      // Refresh providers
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
            backgroundColor: Colors.green.shade700,
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
    final isCashier = widget.payerRole.toLowerCase().contains('cashier');
    final activeShift = ref.watch(posActiveShiftProvider);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: const BoxDecoration(
                      gradient: AppGradients.gold,
                      borderRadius: AppRadius.mdAll,
                      boxShadow: [AppShadows.goldGlow],
                    ),
                    child: const Icon(Icons.payments_rounded,
                        color: Colors.black87, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سداد مستحقات الموردين (نقدًا - Cash Only)',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'المسؤول: ${widget.payerName} | الصلاحية: ${widget.payerRole}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  if (isCashier && activeShift != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: AppRadius.mdAll,
                        border:
                            Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('نقد الدرج المتوفر',
                              style: theme.textTheme.labelSmall),
                          Text(
                            DzdFormatter.formatCentimes(
                                activeShift.expectedCashInDrawerCentimes),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.xl),

              // 2. Body
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Supplier Selection / Switch
                    Expanded(
                      flex: 4,
                      child: _buildSupplierSelector(theme),
                    ),
                    const VerticalDivider(width: AppSpacing.xl),
                    // Right Column: Cash Payment Form
                    Expanded(
                      flex: 5,
                      child: _buildPaymentForm(theme),
                    ),
                  ],
                ),
              ),

              const Divider(height: AppSpacing.xl),

              // 3. Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _autoPrintVoucher,
                        onChanged: (v) =>
                            setState(() => _autoPrintVoucher = v ?? true),
                      ),
                      Text(
                        'طباعة سند صرف فوري (80mm Thermal)',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed:
                            _isSubmitting ? null : () => Navigator.pop(context),
                        child: const Text('إلغاء'),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37), // VIP Gold
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md),
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.mdAll),
                        ),
                        onPressed: _isSubmitting ? null : _handlePayment,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _isSubmitting
                              ? 'جاري المعالجة...'
                              : 'تأكيد وصرف المبلغ نقدًا',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierSelector(ThemeData theme) {
    final suppliersAsync = ref.watch(suppliersWithBalancesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اختيار المورد المستحق',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'بحث باسم المورد أو رقم الهاتف...',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
            isDense: true,
            border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: suppliersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text('تعذر تحميل قائمة الموردين: $err',
                  style: theme.textTheme.bodySmall),
            ),
            data: (suppliers) {
              final query = _searchController.text.trim().toLowerCase();
              final filtered = suppliers.where((s) {
                if (query.isEmpty) return true;
                return s.name.toLowerCase().contains(query) ||
                    s.phone.contains(query);
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text('لا يوجد موردين مطابقين',
                      style: theme.textTheme.bodySmall),
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final s = filtered[index];
                  final isSelected = _selectedSupplier?.id == s.id;
                  return InkWell(
                    onTap: () => _onSupplierSelected(s),
                    borderRadius: AppRadius.mdAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.3)
                            : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            child: Text(
                              s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (s.phone.isNotEmpty)
                                  Text(s.phone,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color:
                                                  theme.colorScheme.outline)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                DzdFormatter.formatCentimes(
                                    s.currentBalanceCentimes),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: s.currentBalanceCentimes > 0
                                      ? Colors.red.shade700
                                      : Colors.green.shade700,
                                ),
                              ),
                              Text(
                                s.currentBalanceCentimes > 0
                                    ? 'مستحق له'
                                    : 'خالص',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: s.currentBalanceCentimes > 0
                                      ? Colors.red.shade600
                                      : Colors.green.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  Widget _buildPaymentForm(ThemeData theme) {
    final balanceCentimes = _selectedSupplier?.currentBalanceCentimes ?? 0;
    final payCentimes = _enteredCentimes;
    final remainingCentimes = balanceCentimes - payCentimes;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selected Supplier Summary Card
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: AppRadius.lgAll,
              border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _selectedSupplier?.name ??
                            'يرجى اختيار المورد من القائمة',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: AppRadius.smAll,
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: const Text(
                        'دفع نقدًا فقط (CASH ONLY)',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('إجمالي مستحقات المورد الحالية:',
                        style: theme.textTheme.bodySmall),
                    Text(
                      DzdFormatter.formatCentimes(balanceCentimes),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: balanceCentimes > 0
                            ? Colors.red.shade700
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Quick Presets
          if (balanceCentimes > 0) ...[
            Text('نسب التسديد السريع:', style: theme.textTheme.labelMedium),
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
                    isPrimary: true),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Amount Input
          Text('المبلغ المراد صرفه نقداً (د.ج):',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
            decoration: InputDecoration(
              suffixText: 'د.ج',
              prefixIcon: const Icon(Icons.attach_money_rounded),
              hintText: '0',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              border: const OutlineInputBorder(borderRadius: AppRadius.mdAll),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),

          // Remaining Balance Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: remainingCentimes <= 0
                  ? Colors.green.shade50
                  : Colors.amber.shade50,
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: remainingCentimes <= 0
                    ? Colors.green.shade300
                    : Colors.amber.shade300,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  remainingCentimes <= 0
                      ? 'الرصيد المتبقي بعد السداد (خالص):'
                      : 'الرصيد المتبقي بذمة المؤسسة:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: remainingCentimes <= 0
                        ? Colors.green.shade800
                        : Colors.amber.shade900,
                  ),
                ),
                Text(
                  DzdFormatter.formatCentimes(
                      remainingCentimes.clamp(0, double.infinity).toInt()),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: remainingCentimes <= 0
                        ? Colors.green.shade800
                        : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Caller PIN confirmation
          Text('رمز PIN الخاص بك لتأكيد الصرف:',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
              hintText: '••••',
              prefixIcon: Icon(Icons.lock_outline_rounded),
              helperText: 'مطلوب لمنع أي عملية صرف غير مصرح بها',
              counterText: '',
              isDense: true,
              border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Notes
          Text('ملاحظات وسند الصرف (اختياري):',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'مثال: تسديد دفعة نقدية عن فاتورة استلام شحنة...',
              isDense: true,
              border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, VoidCallback onTap,
      {bool isPrimary = false}) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          backgroundColor: isPrimary ? Colors.amber.shade100 : null,
          side: BorderSide(
            color: isPrimary ? Colors.amber.shade800 : Colors.grey.shade400,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isPrimary ? Colors.amber.shade900 : null,
          ),
        ),
      ),
    );
  }
}
