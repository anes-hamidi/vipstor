import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';

/// Item representing a targeted business change in a simple, human-readable format.
class AuditTargetedChange {
  final String label;
  final String? oldValue;
  final String newValue;
  final IconData? icon;
  final Color? color;

  const AuditTargetedChange({
    required this.label,
    this.oldValue,
    required this.newValue,
    this.icon,
    this.color,
  });
}

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

    final beforeState = log['before_state'];
    final afterState = log['after_state'];
    final hasPayload = beforeState != null || afterState != null;

    Color badgeColor = colors.info;
    if (action == 'INSERT') badgeColor = colors.success;
    if (action == 'UPDATE') badgeColor = colors.warning;
    if (action == 'DELETE') badgeColor = theme.colorScheme.error;

    // Extract human-friendly targeted changes instead of raw dump
    final targetedChanges = _extractTargetedChanges(action, targetTable, beforeState, afterState);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
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
                    child: Icon(Icons.verified_outlined, color: badgeColor, size: 22),
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
                          'بواسطة: $actorName (${_translateRole(actorRole)})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
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
              const Divider(height: AppSpacing.lg),

              // Scrollable Body
              Expanded(
                child: ListView(
                  children: [
                    // 1. Core Targeted Highlights Card
                    Card(
                      elevation: 0,
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.mdAll,
                        side: BorderSide(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.auto_awesome_rounded, size: 18, color: Color(0xFFD4AF37)),
                                SizedBox(width: 6),
                                Text(
                                  'ملخص التغييرات الجوهرية (Targeted Changes)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFFD4AF37),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            if (targetedChanges.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  hasPayload
                                      ? 'تم تسجيل العملية بنجاح بدون تعديل في الحقول الأساسية.'
                                      : 'تم تسجيل العملية. تفاصيل الحالة الكاملة محجوبة لأسباب أمنية.',
                                ),
                              )
                            else
                              ...targetedChanges.map((change) => _buildChangeRow(context, change)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // 2. Operation Context & Actor Card
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 17, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                const Text('بيانات العملية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _buildInfoRow('نوع الإجراء:', action),
                            _buildInfoRow('الجدول المستهدف:', targetTable),
                            _buildInfoRow('المنفّذ:', '$actorName (${_translateRole(actorRole)})'),
                            if (actorPhone.isNotEmpty) _buildInfoRow('الهاتف:', actorPhone),
                            if (createdAt != null)
                              _buildInfoRow(
                                'الوقت والتاريخ:',
                                '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
                                '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}:${createdAt.second.toString().padLeft(2, '0')}',
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (hasPayload) ...[
                      const SizedBox(height: AppSpacing.md),

                      // 3. Technical Raw Data (Expandable accordion for advanced inspection)
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            'عرض البيانات التقنية الكاملة (JSON)',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                          ),
                          children: [
                            if (beforeState != null) ...[
                              _buildJsonDump(context, 'الحالة السابقة (Before)', beforeState, colors.warning),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                            if (afterState != null)
                              _buildJsonDump(context, 'الحالة الناتجة (After)', afterState, colors.success),
                          ],
                        ),
                      ),
                    ],
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

  Widget _buildChangeRow(BuildContext context, AuditTargetedChange change) {
    final theme = Theme.of(context);
    final hasOld = change.oldValue != null && change.oldValue!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppRadius.smAll,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (change.icon != null) ...[
              Icon(change.icon, size: 18, color: change.color ?? const Color(0xFFD4AF37)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    change.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (hasOld) ...[
                        Text(
                          change.oldValue!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade700,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        change.newValue,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: change.color ?? Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonDump(BuildContext context, String title, dynamic data, Color color) {
    final theme = Theme.of(context);
    String text = '';
    if (data is Map) {
      text = data.entries.map((e) => '• ${e.key}: ${e.value}').join('\n');
    } else {
      text = data.toString();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: AppRadius.xsAll,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }

  List<AuditTargetedChange> _extractTargetedChanges(
    String action,
    String table,
    dynamic before,
    dynamic after,
  ) {
    final b = (before is Map) ? before : <String, dynamic>{};
    final a = (after is Map) ? after : <String, dynamic>{};
    final list = <AuditTargetedChange>[];

    // 1. Stock Ledger / Adjustments (Quantity & Reason)
    if (table == 'stock_ledger') {
      final qty = a['qty_change'] ?? b['qty_change'];
      if (qty != null) {
        final intQty = (qty as num).toInt();
        list.add(AuditTargetedChange(
          label: 'تغيير كمية المخزون (Qty Change)',
          newValue: '${intQty > 0 ? "+$intQty" : "$intQty"} وحدة',
          icon: Icons.inventory_2_rounded,
          color: intQty >= 0 ? Colors.green.shade700 : Colors.red.shade700,
        ));
      }
      if (a['reason'] != null) {
        list.add(AuditTargetedChange(
          label: 'سبب حركة المخزون',
          newValue: '${a['reason']} ${a['notes'] != null ? "(${a['notes']})" : ""}',
          icon: Icons.label_important_outline_rounded,
        ));
      }
      return list;
    }

    // 2. Product Prices (Price & Tier Change)
    if (table == 'product_prices') {
      final oldP = b['price'] != null ? DzdFormatter.formatCentimes((b['price'] as num).toInt()) : null;
      final newP = a['price'] != null ? DzdFormatter.formatCentimes((a['price'] as num).toInt()) : null;
      if (newP != null) {
        list.add(AuditTargetedChange(
          label: 'تعديل السعر (${a['tier'] ?? b['tier'] ?? "سعر"})',
          oldValue: oldP,
          newValue: newP,
          icon: Icons.sell_rounded,
          color: Colors.amber.shade800,
        ));
      }
      if (a['min_qty'] != null && a['min_qty'] != b['min_qty']) {
        list.add(AuditTargetedChange(
          label: 'الحد الأدنى للكمية (Min Qty)',
          oldValue: b['min_qty']?.toString(),
          newValue: '${a['min_qty']} قطعة',
          icon: Icons.numbers_rounded,
        ));
      }
      return list;
    }

    // 3. Products (Name, Cost, Stock Alert)
    if (table == 'products') {
      if (a['name_ar'] != null && (b['name_ar'] != a['name_ar'])) {
        list.add(AuditTargetedChange(
          label: 'اسم المنتج (العربية)',
          oldValue: b['name_ar'] as String?,
          newValue: a['name_ar'] as String,
          icon: Icons.edit_note_rounded,
        ));
      }
      if (a['last_unit_cost'] != null && (b['last_unit_cost'] != a['last_unit_cost'])) {
        list.add(AuditTargetedChange(
          label: 'تكلفة الوحدة (Unit Cost)',
          oldValue: b['last_unit_cost'] != null ? DzdFormatter.formatCentimes((b['last_unit_cost'] as num).toInt()) : null,
          newValue: DzdFormatter.formatCentimes((a['last_unit_cost'] as num).toInt()),
          icon: Icons.attach_money_rounded,
        ));
      }
      if (a['active'] != null && (b['active'] != a['active'])) {
        final isActive = a['active'] == true;
        list.add(AuditTargetedChange(
          label: 'حالة تفعيل المنتج',
          oldValue: b['active'] == true ? 'مفعل' : 'معطل',
          newValue: isActive ? 'مفعل' : 'معطل',
          icon: isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
          color: isActive ? Colors.green : Colors.grey,
        ));
      }
      return list;
    }

    // 4. Payments & Debt Collection
    if (table == 'payments' || table == 'customer_ledger' || table == 'supplier_ledger') {
      final amt = a['amount'] ?? a['amount_change'] ?? a['amount_centimes'];
      if (amt != null) {
        final intAmt = (amt as num).toInt().abs();
        list.add(AuditTargetedChange(
          label: 'المبلغ المالي',
          newValue: DzdFormatter.formatCentimes(intAmt),
          icon: Icons.payments_rounded,
          color: Colors.green.shade800,
        ));
      }
      if (a['notes'] != null && (a['notes'] as String).isNotEmpty) {
        list.add(AuditTargetedChange(
          label: 'البيان والملاحظات',
          newValue: a['notes'].toString(),
          icon: Icons.notes_rounded,
        ));
      }
      return list;
    }

    // 5. Orders (Status & Total Amount)
    if (table == 'orders') {
      if (a['status'] != null && a['status'] != b['status']) {
        list.add(AuditTargetedChange(
          label: 'حالة الطلب',
          oldValue: b['status'] as String?,
          newValue: a['status'] as String,
          icon: Icons.sync_alt_rounded,
          color: Colors.blue.shade700,
        ));
      }
      if (a['total_amount'] != null && a['total_amount'] != b['total_amount']) {
        list.add(AuditTargetedChange(
          label: 'إجمالي قيمة الطلب',
          oldValue: b['total_amount'] != null ? DzdFormatter.formatCentimes((b['total_amount'] as num).toInt()) : null,
          newValue: DzdFormatter.formatCentimes((a['total_amount'] as num).toInt()),
          icon: Icons.receipt_long_rounded,
        ));
      }
      return list;
    }

    // 6. Cashier Shifts (Open / Close & Variance)
    if (action == 'SHIFT_OPENED' || action == 'SHIFT_CLOSED') {
      if (a['opening_float_centimes'] != null) {
        list.add(AuditTargetedChange(
          label: 'الرصيد الافتتاحي للدرج',
          newValue: DzdFormatter.formatCentimes((a['opening_float_centimes'] as num).toInt()),
          icon: Icons.point_of_sale_rounded,
        ));
      }
      if (a['counted_cash_centimes'] != null) {
        list.add(AuditTargetedChange(
          label: 'النقد الفعلي بالدرج عند الإغلاق',
          newValue: DzdFormatter.formatCentimes((a['counted_cash_centimes'] as num).toInt()),
          icon: Icons.check_circle_outline_rounded,
        ));
      }
      if (a['variance_centimes'] != null) {
        final variance = (a['variance_centimes'] as num).toInt();
        list.add(AuditTargetedChange(
          label: 'فارق العجز أو الزيادة (Variance)',
          newValue: DzdFormatter.formatCentimes(variance),
          icon: variance == 0 ? Icons.check_rounded : Icons.warning_rounded,
          color: variance == 0 ? Colors.green : (variance < 0 ? Colors.red : Colors.orange),
        ));
      }
      return list;
    }

    // 7. Staff Logins / Logouts / Switches
    if (action.startsWith('STAFF_') || action == 'CASHIER_SWITCH') {
      if (a['device'] != null) {
        list.add(AuditTargetedChange(
          label: 'نقطة الوصول / الجهاز',
          newValue: a['device'].toString(),
          icon: Icons.devices_rounded,
        ));
      }
      if (a['new_cashier_name'] != null) {
        list.add(AuditTargetedChange(
          label: 'الكاشير المستلم',
          oldValue: b['previous_cashier_name'] as String?,
          newValue: a['new_cashier_name'].toString(),
          icon: Icons.swap_horiz_rounded,
        ));
      }
      return list;
    }

    // Fallback: Show changed scalar keys
    for (final entry in a.entries) {
      if (['id', 'created_at', 'updated_at', 'client_id'].contains(entry.key)) continue;
      if (b[entry.key] != entry.value) {
        list.add(AuditTargetedChange(
          label: entry.key,
          oldValue: b[entry.key]?.toString(),
          newValue: entry.value?.toString() ?? 'فارغ',
        ));
      }
    }

    return list;
  }

  String _translateRole(String role) {
    switch (role.toLowerCase()) {
      case 'moderator':
        return 'المشرف العام';
      case 'manager':
        return 'مدير المخزون';
      case 'cashier':
        return 'أمين الصندوق';
      case 'driver':
        return 'سائق التوصيل';
      case 'customer':
        return 'زبون المتجر';
      default:
        return 'النظام';
    }
  }
}
