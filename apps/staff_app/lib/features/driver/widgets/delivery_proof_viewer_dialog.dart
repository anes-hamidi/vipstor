import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import 'driver_order_utils.dart';

/// Read-only viewer for the signature/photo/GPS proof attached to a delivery.
class DeliveryProofViewerDialog extends StatelessWidget {
  final OrderEntity order;

  const DeliveryProofViewerDialog({super.key, required this.order});

  static Future<void> show(BuildContext context, {required OrderEntity order}) {
    return showDialog<void>(
      context: context,
      builder: (_) => DeliveryProofViewerDialog(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final signature = _decode(order.signatureBase64);
    final photo = _decode(order.photoBase64);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 780),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.xxlAll,
            border: Border.all(color: colors.gold.withValues(alpha: 0.30)),
            boxShadow: AppShadows.dialogLuxury,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsetsDirectional.all(8),
                      decoration: BoxDecoration(
                        color: colors.success.withValues(alpha: 0.12),
                        borderRadius: AppRadius.mdAll,
                      ),
                      child: Icon(
                        Icons.verified_user_outlined,
                        color: colors.success,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إثبات التسليم',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'طلب #${orderShortNumber(order)} • ${deliveryCustomerName(order)}',
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
              ),
              const GoldDivider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _ProofChip(
                            icon: Icons.draw_outlined,
                            label: signature != null
                                ? 'توقيع محفوظ'
                                : 'لا يوجد توقيع',
                            active: signature != null,
                          ),
                          _ProofChip(
                            icon: Icons.photo_camera_outlined,
                            label:
                                photo != null ? 'صورة محفوظة' : 'لا توجد صورة',
                            active: photo != null,
                          ),
                          _ProofChip(
                            icon: Icons.gps_fixed_rounded,
                            label: order.deliveryLat != null
                                ? 'موقع مسجل'
                                : 'بدون GPS',
                            active: order.deliveryLat != null,
                          ),
                        ],
                      ),
                      if (signature != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _ProofImage(
                          bytes: signature,
                          label: 'توقيع المستلم',
                          background: Colors.white,
                        ),
                      ],
                      if (photo != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _ProofImage(
                          bytes: photo,
                          label: 'صورة التسليم',
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _DetailRow(
                        label: 'المستلم',
                        value: order.deliveryRecipientName?.trim().isNotEmpty ==
                                true
                            ? order.deliveryRecipientName!.trim()
                            : 'غير مسجل',
                      ),
                      if (order.deliveryAttemptedAt != null)
                        _DetailRow(
                          label: 'وقت التسليم',
                          value:
                              formatDateTimeShort(order.deliveryAttemptedAt!),
                        ),
                      if (order.deliveryLat != null &&
                          order.deliveryLng != null)
                        _DetailRow(
                          label: 'إحداثيات GPS',
                          value:
                              '${order.deliveryLat!.toStringAsFixed(5)}, ${order.deliveryLng!.toStringAsFixed(5)}',
                        ),
                      if (order.deliveryNotes?.trim().isNotEmpty == true)
                        _DetailRow(
                          label: 'ملاحظات التسليم',
                          value: order.deliveryNotes!.trim(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Uint8List? _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final payload = raw.contains(',') ? raw.split(',').last : raw;
    try {
      final bytes = base64Decode(payload);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }
}

class _ProofChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _ProofChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final color = active ? colors.success : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofImage extends StatelessWidget {
  final Uint8List bytes;
  final String label;
  final Color? background;

  const _ProofImage({
    required this.bytes,
    required this.label,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: label == 'توقيع المستلم' ? 150 : 240,
          decoration: BoxDecoration(
            color: background ?? theme.colorScheme.surfaceContainerLow,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: colors.goldBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            maxScale: 4,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  'تعذر عرض الصورة',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
