import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class AuditLogDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> log;

  const AuditLogDetailsDialog({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    final action = (log['action'] as String? ?? 'OPERATION').toUpperCase();
    final targetTable = log['target_table'] as String? ?? '';
    final intelligentTitle = log['intelligent_title'] as String? ?? '$action على $targetTable';
    final actorName = log['actor_name'] as String? ?? 'النظام / تلقائي';
    final actorRole = log['actor_role'] as String? ?? 'system';
    final actorPhone = log['actor_phone'] as String? ?? '';
    final createdAtStr = log['created_at'] as String?;
    final createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr)?.toLocal() : null;
    final targetId = log['target_id'] as String?;

    final beforeState = log['before_state'];
    final afterState = log['after_state'];

    Color badgeColor = colors.info;
    if (action == 'INSERT') badgeColor = colors.success;
    if (action == 'UPDATE') badgeColor = colors.warning;
    if (action == 'DELETE') badgeColor = theme.colorScheme.error;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: badgeColor.withValues(alpha: 0.15),
                    child: Icon(Icons.security_rounded, color: badgeColor, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          intelligentTitle,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'جدول: $targetTable • الإجراء: $action',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.xl),

              // Metadata Grid
              Expanded(
                child: ListView(
                  children: [
                    _buildInfoCard(
                      context,
                      title: 'تفاصيل القائم بالعملية (Actor)',
                      icon: Icons.person_outline,
                      children: [
                        _buildRow('الاسم:', actorName),
                        _buildRow('الدور الوظيفي:', _translateRole(actorRole)),
                        if (actorPhone.isNotEmpty) _buildRow('رقم الهاتف:', actorPhone),
                        if (createdAt != null)
                          _buildRow('توقيت التسجيل:', '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}:${createdAt.second.toString().padLeft(2, '0')}'),
                        if (targetId != null) _buildRow('المعرف المستهدف:', targetId),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Before & After States
                    if (beforeState != null) ...[
                      _buildStateCard(
                        context,
                        title: 'الحالة السابقة (Before State)',
                        data: beforeState,
                        color: colors.warning,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    if (afterState != null)
                      _buildStateCard(
                        context,
                        title: 'الحالة الحالية / الناتجة (After State)',
                        data: afterState,
                        color: colors.success,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, {required String title, required IconData icon, required List<Widget> children}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStateCard(BuildContext context, {required String title, required dynamic data, required Color color}) {
    final theme = Theme.of(context);

    String displayContent = '';
    if (data is Map) {
      final entries = data.entries.map((e) => '  • ${e.key}: ${e.value}').toList();
      displayContent = entries.join('\n');
    } else {
      displayContent = data.toString();
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: AppRadius.xsAll,
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: SelectableText(
                displayContent,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _translateRole(String role) {
    switch (role.toLowerCase()) {
      case 'moderator':
        return 'المشرف العام (Moderator)';
      case 'manager':
        return 'مدير المخزون (Manager)';
      case 'cashier':
        return 'أمين الصندوق (Cashier)';
      case 'driver':
        return 'سائق التوصيل (Driver)';
      case 'customer':
        return 'زبون المتجر (Customer)';
      default:
        return 'النظام (System / Trigger)';
    }
  }
}
