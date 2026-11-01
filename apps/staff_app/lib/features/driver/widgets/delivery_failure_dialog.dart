import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import 'delivery_failure_reason.dart';
import 'driver_order_utils.dart';

class DeliveryFailureResult {
  final DeliveryFailureReason reason;
  final String? notes;

  const DeliveryFailureResult({required this.reason, this.notes});
}

/// Records why a delivery could not be handed over. The screen owns the
/// persistence call so this dialog stays reusable from the list and the map.
class DeliveryFailureDialog extends StatefulWidget {
  final OrderEntity order;

  const DeliveryFailureDialog({super.key, required this.order});

  static Future<DeliveryFailureResult?> show(
    BuildContext context, {
    required OrderEntity order,
  }) {
    final content = DeliveryFailureDialog(order: order);
    final width = MediaQuery.sizeOf(context).width;

    if (width >= 720) {
      return showDialog<DeliveryFailureResult>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: content,
          ),
        ),
      );
    }

    return showModalBottomSheet<DeliveryFailureResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: content,
      ),
    );
  }

  @override
  State<DeliveryFailureDialog> createState() => _DeliveryFailureDialogState();
}

class _DeliveryFailureDialogState extends State<DeliveryFailureDialog> {
  final _notesController = TextEditingController();
  DeliveryFailureReason? _reason;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'اختر سبب تعذر التسليم أولاً.');
      return;
    }
    final notes = _notesController.text.trim();
    if (reason == DeliveryFailureReason.other && notes.isEmpty) {
      setState(() => _error = 'اكتب توضيحاً للسبب الآخر.');
      return;
    }

    Navigator.of(context).pop(
      DeliveryFailureResult(
        reason: reason,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final order = widget.order;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.xxlAll,
        border: Border.all(color: colors.cancelled.withValues(alpha: 0.32)),
        boxShadow: AppShadows.dialogLuxury,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.all(9),
                  decoration: BoxDecoration(
                    color: colors.cancelled.withValues(alpha: 0.12),
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: colors.cancelled.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.report_gmailerrorred_rounded,
                    color: colors.cancelled,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تعذر تسليم الطلب',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '#${orderShortNumber(order)} • ${deliveryCustomerName(order)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.warningContainer.withValues(alpha: 0.45),
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 17,
                    color: colors.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'سيُعاد الطلب إلى قائمة مراجعة المشرف ولن يُحتسب ضمن مهامك النشطة.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onWarningContainer,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'ما سبب تعذر التسليم؟',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final reason in DeliveryFailureReason.values) ...[
              _ReasonTile(
                reason: reason,
                selected: _reason == reason,
                onTap: () => setState(() {
                  _reason = reason;
                  _error = null;
                }),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات إضافية (اختياري)',
                hintText: 'مثال: حاولت الاتصال ثلاث مرات دون رد',
                prefixIcon: Icon(Icons.edit_note_rounded),
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.cancelled,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('رجوع'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.cancelled,
                      foregroundColor: colors.onCancelled,
                      minimumSize: const Size(0, 46),
                    ),
                    onPressed: _submit,
                    icon:
                        const Icon(Icons.assignment_return_outlined, size: 17),
                    label: const Text('تسجيل تعذر التسليم'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final DeliveryFailureReason reason;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.goldMuted : null,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: selected
                  ? colors.gold.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                reason.icon,
                size: 19,
                color:
                    selected ? colors.gold : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reason.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      reason.description,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 19,
                color:
                    selected ? colors.gold : theme.colorScheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
