import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';

/// Order / document lifecycle status badge.
///
/// ```dart
/// StatusBadge(type: StatusBadgeType.pending)
/// StatusBadge(type: StatusBadgeType.completed, customLabel: 'مسلّم')
/// ```
enum StatusBadgeType {
  draft,
  pending,
  processing,
  preparing,
  ready,
  posted,
  completed,
  delivered,
  cancelled,
  returned,
}

class StatusBadge extends StatelessWidget {
  final StatusBadgeType type;
  final String? customLabel;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.type,
    this.customLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    Color border;
    IconData icon;
    String label;

    switch (type) {
      case StatusBadgeType.draft:
        bg = cs.surfaceContainer;
        fg = colors.draft;
        border = colors.draft.withValues(alpha: 0.30);
        icon = Icons.edit_note_outlined;
        label = 'مسودة';
      case StatusBadgeType.pending:
        bg = colors.warningContainer;
        fg = colors.onWarningContainer;
        border = colors.onWarningContainer.withValues(alpha: 0.25);
        icon = Icons.schedule_outlined;
        label = 'قيد الانتظار';
      case StatusBadgeType.processing:
        bg = colors.infoContainer;
        fg = colors.onInfoContainer;
        border = colors.onInfoContainer.withValues(alpha: 0.25);
        icon = Icons.sync_outlined;
        label = 'قيد المعالجة';
      case StatusBadgeType.preparing:
        bg = isDark ? const Color(0xFF1E3040) : const Color(0xFFE0F0FF);
        fg = isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1);
        border = fg.withValues(alpha: 0.25);
        icon = Icons.kitchen_outlined;
        label = 'يُحضَّر';
      case StatusBadgeType.ready:
        bg = colors.successContainer;
        fg = colors.success;
        border = colors.success.withValues(alpha: 0.30);
        icon = Icons.check_circle_outline;
        label = 'جاهز';
      case StatusBadgeType.posted:
      case StatusBadgeType.completed:
        bg = colors.successContainer;
        fg = colors.onSuccessContainer;
        border = colors.onSuccessContainer.withValues(alpha: 0.25);
        icon = Icons.task_alt_outlined;
        label = 'مكتمل';
      case StatusBadgeType.delivered:
        bg = isDark ? const Color(0xFF0D2E1A) : const Color(0xFFDCFCE7);
        fg = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
        border = fg.withValues(alpha: 0.30);
        icon = Icons.local_shipping_outlined;
        label = 'تم التسليم';
      case StatusBadgeType.cancelled:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        border = cs.onErrorContainer.withValues(alpha: 0.25);
        icon = Icons.cancel_outlined;
        label = 'ملغى';
      case StatusBadgeType.returned:
        bg = isDark ? const Color(0xFF2A1A2E) : const Color(0xFFF5E8FF);
        fg = isDark ? const Color(0xFFC084FC) : const Color(0xFF7C3AED);
        border = fg.withValues(alpha: 0.25);
        icon = Icons.assignment_return_outlined;
        label = 'مُرتجع';
    }

    final resolvedBg = isDark
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.15), bg)
        : bg;

    return Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 1.5 : 3.0,
      ),
      decoration: BoxDecoration(
        color: resolvedBg,
        borderRadius: AppRadius.fullAll,
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 11 : 13, color: fg),
          SizedBox(width: compact ? AppSpacing.xxs : AppSpacing.xs),
          Text(
            customLabel ?? label,
            style: TextStyle(
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
