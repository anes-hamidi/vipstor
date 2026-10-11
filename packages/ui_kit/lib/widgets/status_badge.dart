import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

enum StatusBadgeType {
  draft,
  pending,
  posted,
  completed,
  cancelled,
  processing,
}

class StatusBadge extends StatelessWidget {
  final StatusBadgeType type;
  final String? customLabel;

  const StatusBadge({
    super.key,
    required this.type,
    this.customLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (type) {
      case StatusBadgeType.draft:
        bg = colorScheme.surfaceContainer;
        fg = colors.draft;
        icon = Icons.edit_note_outlined;
        label = 'مسودة (Draft)';
        break;
      case StatusBadgeType.pending:
        bg = colors.warningContainer;
        fg = colors.onWarningContainer;
        icon = Icons.schedule_outlined;
        label = 'قيد المعالجة (En attente)';
        break;
      case StatusBadgeType.posted:
      case StatusBadgeType.completed:
        bg = colors.successContainer;
        fg = colors.onSuccessContainer;
        icon = Icons.check_circle_outline;
        label = 'مكتمل (Terminé)';
        break;
      case StatusBadgeType.cancelled:
        bg = colorScheme.errorContainer;
        fg = colorScheme.onErrorContainer;
        icon = Icons.cancel_outlined;
        label = 'ملغى (Annulé)';
        break;
      case StatusBadgeType.processing:
        bg = colors.infoContainer;
        fg = colors.onInfoContainer;
        icon = Icons.sync_outlined;
        label = 'جاري التنفيذ (En cours)';
        break;
    }

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Text(
            customLabel ?? label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
