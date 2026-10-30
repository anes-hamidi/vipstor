import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Quiet inline notice shown when the storefront is serving cached data.
///
/// Offline is a warning; a failed refresh while online is informational. Both
/// share the same shape so the list below never jumps between two layouts.
class CatalogOfflineBanner extends StatelessWidget {
  final bool offline;
  final String? message;
  final DateTime? syncedAt;
  final VoidCallback onRetry;

  const CatalogOfflineBanner({
    super.key,
    required this.offline,
    required this.syncedAt,
    required this.onRetry,
    this.message,
  });

  String get _timestamp {
    final synced = syncedAt;
    if (synced == null) return 'تُعرض البيانات المحفوظة على جهازك';

    final local = synced.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'آخر مزامنة $day/$month · $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final background = offline ? colors.warningContainer : colors.infoContainer;
    final foreground =
        offline ? colors.onWarningContainer : colors.onInfoContainer;
    final title = offline ? 'أنت غير متصل' : 'تعذر تحديث القائمة';
    final subtitle = message == null || message!.trim().isEmpty
        ? _timestamp
        : '$_timestamp · سنعيد المحاولة تلقائياً';

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $subtitle',
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: foreground.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(
              offline ? Icons.wifi_off_rounded : Icons.sync_problem_rounded,
              size: 20,
              color: foreground,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip: 'تحديث الآن',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              style: IconButton.styleFrom(
                foregroundColor: foreground,
                minimumSize: const Size(44, 44),
                maximumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
