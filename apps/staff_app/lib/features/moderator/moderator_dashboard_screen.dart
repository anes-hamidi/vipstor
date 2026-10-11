import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'widgets/create_staff_dialog.dart';
import 'widgets/generate_staff_pin_dialog.dart';
import 'widgets/audit_log_details_dialog.dart';

// Filter providers for intelligent audit trail
final auditSearchQueryProvider = StateProvider<String>((ref) => '');
final auditActorFilterProvider = StateProvider<String>((ref) => 'all'); // 'all', 'staff', 'customer'
final auditCategoryFilterProvider = StateProvider<String>((ref) => 'all'); // 'all', 'sales', 'finance', 'inventory', 'security'

// Moderator KPI stats provider
final moderatorStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  // 1. Total sales & collected
  final orderRows = await client.from('orders').select('total_amount, paid_amount');
  int totalSales = 0;
  int totalCollected = 0;
  for (final r in orderRows as List) {
    totalSales += (r['total_amount'] as num?)?.toInt() ?? 0;
    totalCollected += (r['paid_amount'] as num?)?.toInt() ?? 0;
  }

  // 2. Driver wallets
  final walletRows = await client.from('view_driver_wallet_balance').select('current_wallet_balance');
  int totalDriverCash = 0;
  for (final w in walletRows as List) {
    totalDriverCash += (w['current_wallet_balance'] as num?)?.toInt() ?? 0;
  }

  // 3. Customer debt
  final customerRows = await client.from('view_customer_balance').select('current_balance');
  int totalCustomerDebt = 0;
  for (final c in customerRows as List) {
    totalCustomerDebt += (c['current_balance'] as num?)?.toInt() ?? 0;
  }

  // 4. Supplier balance
  final supplierLedgerRows = await client.from('supplier_ledger').select('amount_change');
  int totalSupplierDebt = 0;
  for (final s in supplierLedgerRows as List) {
    totalSupplierDebt += (s['amount_change'] as num?)?.toInt() ?? 0;
  }

  return {
    'total_sales': totalSales,
    'total_collected': totalCollected,
    'driver_cash': totalDriverCash,
    'customer_debt': totalCustomerDebt,
    'supplier_debt': totalSupplierDebt,
  };
});

// Comprehensive & Intelligent Audit Trail Provider
final auditTrailLogsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  try {
    // Attempt querying the rich intelligent audit view
    final rows = await client
        .from('view_audit_trail_intelligence')
        .select()
        .order('created_at', ascending: false)
        .limit(100);

    return List<Map<String, dynamic>>.from(rows as List);
  } catch (_) {
    // Graceful fallback to raw audit_log if view hasn't been migrated yet
    final rawRows = await client
        .from('audit_log')
        .select('*, users(name, role, phone)')
        .order('created_at', ascending: false)
        .limit(100);

    return (rawRows as List).map((r) {
      final user = r['users'] as Map<String, dynamic>?;
      final table = r['target_table'] as String? ?? '';
      final action = r['action'] as String? ?? '';
      final role = user?['role'] as String? ?? 'system';

      return {
        'id': r['id'],
        'created_at': r['created_at'],
        'action': action,
        'target_table': table,
        'target_id': r['target_id'],
        'user_id': r['user_id'],
        'actor_name': user?['name'] ?? 'النظام / تلقائي',
        'actor_role': role,
        'actor_phone': user?['phone'] ?? '',
        'intelligent_title': '$action على $table',
        'category': (table == 'orders' || table == 'order_items')
            ? 'sales'
            : (table == 'payments' || table == 'settlements' || table == 'customer_ledger' || table == 'supplier_ledger')
                ? 'finance'
                : (table == 'stock_ledger' || table == 'products' || table == 'purchases')
                    ? 'inventory'
                    : 'general',
        'actor_type': role == 'customer'
            ? 'customer'
            : (['cashier', 'driver', 'manager', 'moderator'].contains(role) ? 'staff' : 'system'),
        'before_state': r['before_state'],
        'after_state': r['after_state'],
      };
    }).toList();
  }
});

class ModeratorDashboardScreen extends ConsumerStatefulWidget {
  const ModeratorDashboardScreen({super.key});

  @override
  ConsumerState<ModeratorDashboardScreen> createState() => _ModeratorDashboardScreenState();
}

class _ModeratorDashboardScreenState extends ConsumerState<ModeratorDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showAddStaffDialog() async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const CreateStaffDialog(),
    );

    if (res != null && mounted) {
      ref.invalidate(staffMembersProvider);
      ref.invalidate(auditTrailLogsProvider);
      final pin = res['pin'] as String?;
      final pinMsg = pin != null ? ' مع رمز PIN: $pin' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنشاء حساب الموظف "${res['name']}" بنجاح!$pinMsg'),
          backgroundColor: context.appColors.success,
        ),
      );
    }
  }

  Future<void> _showGeneratePinDialog(Map<String, dynamic> staffUser) async {
    await showDialog(
      context: context,
      builder: (ctx) => GenerateStaffPinDialog(staffUser: staffUser),
    );
    if (mounted) {
      ref.invalidate(auditTrailLogsProvider);
    }
  }

  void _showAuditLogDetails(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (ctx) => AuditLogDetailsDialog(log: log),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings_rounded),
            const SizedBox(width: AppSpacing.sm),
            Text('لوحة تحكم المشرف العام - ${authUser?.name ?? "Admin"}'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(moderatorStatsProvider);
              ref.invalidate(staffMembersProvider);
              ref.invalidate(auditTrailLogsProvider);
            },
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authStateProvider.notifier).state = null,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: 'المؤشرات المالية (KPIs)'),
            Tab(icon: Icon(Icons.history_edu_outlined), text: 'سجل التدقيق الشامل (Audit Trail)'),
            Tab(icon: Icon(Icons.badge_outlined), text: 'طاقم العمل (Staff)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFinancialStatsTab(),
          _buildAuditTrailTab(),
          _buildStaffManagementTab(),
        ],
      ),
    );
  }

  Widget _buildFinancialStatsTab() {
    final statsAsync = ref.watch(moderatorStatsProvider);
    final theme = Theme.of(context);
    final colors = context.appColors;

    return ContentConstrainedBox.dashboard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: statsAsync.when(
        data: (stats) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisExtent: 115,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                  ),
                  children: [
                    KpiCard(
                      title: 'إجمالي المبيعات المحققة',
                      value: DzdFormatter.formatCentimes(stats['total_sales'] as int),
                      icon: Icons.trending_up,
                      accentColor: theme.colorScheme.primary,
                    ),
                    KpiCard(
                      title: 'كاش في عهدة السائقين',
                      value: DzdFormatter.formatCentimes(stats['driver_cash'] as int),
                      icon: Icons.account_balance_wallet,
                      accentColor: colors.warning,
                    ),
                    KpiCard(
                      title: 'إجمالي ديون الزبائن',
                      value: DzdFormatter.formatCentimes(stats['customer_debt'] as int),
                      icon: Icons.people_alt_outlined,
                      accentColor: colors.info,
                    ),
                    KpiCard(
                      title: 'مستحقات الموردين',
                      value: DzdFormatter.formatCentimes(stats['supplier_debt'] as int),
                      icon: Icons.inventory_2_outlined,
                      accentColor: theme.colorScheme.secondary,
                    ),
                  ],
                ),
                AppSpacing.gapLg,
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'نظام التدقيق الرقمي ومراقبة العمليات',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'يتم تسجيل وتوثيق كافة العمليات تلقائياً عبر Triggers في قاعدة البيانات (Immutable Audit Trail). '
                          'انتقل إلى تبويب "سجل التدقيق الشامل" للبحث والتصفية ومعاينة تفاصيل كل عملية قام بها الموظفون أو الزبائن بدقة متناهية.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.tonalIcon(
                          onPressed: () => _tabController.animateTo(1),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('فتح سجل التدقيق الشامل (Audit Trail)'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const AppLoadingView(message: 'جاري جلب المؤشرات المالية...'),
        error: (err, _) => AppErrorView(
          message: 'تعذر تحميل الإحصائيات من الخادم',
          onRetry: () => ref.invalidate(moderatorStatsProvider),
        ),
      ),
    );
  }

  Widget _buildAuditTrailTab() {
    final auditAsync = ref.watch(auditTrailLogsProvider);
    final theme = Theme.of(context);
    final colors = context.appColors;

    final searchQuery = ref.watch(auditSearchQueryProvider).trim().toLowerCase();
    final actorFilter = ref.watch(auditActorFilterProvider);
    final categoryFilter = ref.watch(auditCategoryFilterProvider);

    return ContentConstrainedBox.dashboard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter & Search Controls
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'البحث في العمليات (اسم الموظف/الزبون، الجدول، الإجراء)...',
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            border: const OutlineInputBorder(borderRadius: AppRadius.smAll),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => ref.read(auditSearchQueryProvider.notifier).state = '',
                                  )
                                : null,
                          ),
                          onChanged: (val) => ref.read(auditSearchQueryProvider.notifier).state = val,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      FilledButton.tonalIcon(
                        onPressed: () => ref.invalidate(auditTrailLogsProvider),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('تحديث'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('الطرف المنفذ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ChoiceChip(
                        label: const Text('الكل'),
                        selected: actorFilter == 'all',
                        onSelected: (_) => ref.read(auditActorFilterProvider.notifier).state = 'all',
                      ),
                      ChoiceChip(
                        label: const Text('طاقم العمل (Staff)'),
                        selected: actorFilter == 'staff',
                        onSelected: (_) => ref.read(auditActorFilterProvider.notifier).state = 'staff',
                      ),
                      ChoiceChip(
                        label: const Text('الزبائن (Customers)'),
                        selected: actorFilter == 'customer',
                        onSelected: (_) => ref.read(auditActorFilterProvider.notifier).state = 'customer',
                      ),
                      const SizedBox(width: AppSpacing.md),
                      const Text('التصنيف:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ChoiceChip(
                        label: const Text('الكل'),
                        selected: categoryFilter == 'all',
                        onSelected: (_) => ref.read(auditCategoryFilterProvider.notifier).state = 'all',
                      ),
                      ChoiceChip(
                        label: const Text('المبيعات'),
                        selected: categoryFilter == 'sales',
                        onSelected: (_) => ref.read(auditCategoryFilterProvider.notifier).state = 'sales',
                      ),
                      ChoiceChip(
                        label: const Text('المالية والديون'),
                        selected: categoryFilter == 'finance',
                        onSelected: (_) => ref.read(auditCategoryFilterProvider.notifier).state = 'finance',
                      ),
                      ChoiceChip(
                        label: const Text('المخزون'),
                        selected: categoryFilter == 'inventory',
                        onSelected: (_) => ref.read(auditCategoryFilterProvider.notifier).state = 'inventory',
                      ),
                      ChoiceChip(
                        label: const Text('الأمان والمستخدمين'),
                        selected: categoryFilter == 'security',
                        onSelected: (_) => ref.read(auditCategoryFilterProvider.notifier).state = 'security',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AppSpacing.gapMd,

          // Audit Log List
          Expanded(
            child: auditAsync.when(
              data: (logs) {
                // Apply Client-side Filters
                final filtered = logs.where((item) {
                  // Filter by actor
                  if (actorFilter != 'all') {
                    final itemActorType = item['actor_type'] as String? ?? 'system';
                    if (actorFilter == 'staff' && itemActorType != 'staff') return false;
                    if (actorFilter == 'customer' && itemActorType != 'customer') return false;
                  }

                  // Filter by category
                  if (categoryFilter != 'all') {
                    final itemCategory = item['category'] as String? ?? 'general';
                    if (itemCategory != categoryFilter) return false;
                  }

                  // Search query filter
                  if (searchQuery.isNotEmpty) {
                    final title = (item['intelligent_title'] as String? ?? '').toLowerCase();
                    final actorName = (item['actor_name'] as String? ?? '').toLowerCase();
                    final table = (item['target_table'] as String? ?? '').toLowerCase();
                    final action = (item['action'] as String? ?? '').toLowerCase();

                    final match = title.contains(searchQuery) ||
                        actorName.contains(searchQuery) ||
                        table.contains(searchQuery) ||
                        action.contains(searchQuery);

                    if (!match) return false;
                  }

                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return const AppEmptyView(
                    icon: Icons.history,
                    title: 'لا توجد سجلات مطابقة',
                    description: 'لم يتم العثور على عمليات تدقيق تطابق معايير البحث والتصفية المحددة.',
                  );
                }

                return Card(
                  margin: EdgeInsets.zero,
                  child: ListView.separated(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = filtered[index];
                      final action = (log['action'] as String? ?? 'OPERATION').toUpperCase();
                      final table = log['target_table'] as String? ?? '';
                      final intelligentTitle = log['intelligent_title'] as String? ?? '$action على $table';
                      final actorName = log['actor_name'] as String? ?? 'النظام / تلقائي';
                      final actorRole = log['actor_role'] as String? ?? 'system';
                      final actorType = log['actor_type'] as String? ?? 'system';
                      final createdAtStr = log['created_at'] as String?;
                      final date = createdAtStr != null ? DateTime.tryParse(createdAtStr)?.toLocal() : null;

                      Color actionColor = colors.info;
                      IconData actionIcon = Icons.info_outline;

                      if (action == 'INSERT') {
                        actionColor = colors.success;
                        actionIcon = Icons.add_circle_outline;
                      } else if (action == 'UPDATE') {
                        actionColor = colors.warning;
                        actionIcon = Icons.edit_note_outlined;
                      } else if (action == 'DELETE') {
                        actionColor = theme.colorScheme.error;
                        actionIcon = Icons.delete_outline;
                      }

                      return ListTile(
                        onTap: () => _showAuditLogDetails(log),
                        leading: CircleAvatar(
                          backgroundColor: actionColor.withValues(alpha: 0.15),
                          child: Icon(actionIcon, color: actionColor, size: 20),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                intelligentTitle,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: actionColor.withValues(alpha: 0.12),
                                borderRadius: AppRadius.xsAll,
                              ),
                              child: Text(
                                action,
                                style: TextStyle(color: actionColor, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              Icon(
                                actorType == 'customer' ? Icons.person_outline : Icons.badge_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$actorName (${_translateRoleLabel(actorRole)})',
                                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                date != null
                                    ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                                    : 'الآن',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              table,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            const Icon(Icons.chevron_left, size: 18),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const AppLoadingView(message: 'جاري جلب سجل التدقيق الشامل والذكي...'),
              error: (err, _) => AppErrorView(
                message: 'تعذر تحميل سجل التدقيق',
                onRetry: () => ref.invalidate(auditTrailLogsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _translateRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'moderator':
        return 'مشرف عام';
      case 'manager':
        return 'مدير مخزون';
      case 'cashier':
        return 'أمين صندوق';
      case 'driver':
        return 'سائق';
      case 'customer':
        return 'زبون';
      default:
        return 'نظام';
    }
  }

  Widget _buildStaffManagementTab() {
    final staffAsync = ref.watch(staffMembersProvider);
    final theme = Theme.of(context);

    return ContentConstrainedBox.dashboard(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'قائمة موظفي المتجر والصلاحيات:',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                onPressed: _showAddStaffDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('إضافة موظف جديد'),
              ),
            ],
          ),
          AppSpacing.gapMd,
          Expanded(
            child: staffAsync.when(
              data: (staff) {
                if (staff.isEmpty) {
                  return AppEmptyView(
                    icon: Icons.people_outline,
                    title: 'لا يوجد موظفون مسجلون',
                    description: 'قم بإضافة الموظفين وتحديد أدوارهم لتفعيل صلاحياتهم.',
                    actionLabel: 'إضافة موظف الآن',
                    onAction: _showAddStaffDialog,
                  );
                }

                return Card(
                  child: ListView.separated(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                    itemCount: staff.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = staff[index];
                      final role = user['role'] as String? ?? 'cashier';
                      final name = user['name'] as String? ?? 'موظف';
                      final phone = user['phone'] as String? ?? '';
                      final active = user['active'] as bool? ?? true;

                      String roleTitle = role;
                      IconData roleIcon = Icons.person;

                      switch (role) {
                        case 'moderator':
                          roleTitle = 'مشرف عام (Moderator)';
                          roleIcon = Icons.admin_panel_settings;
                          break;
                        case 'manager':
                          roleTitle = 'مدير المخزون (Manager)';
                          roleIcon = Icons.inventory;
                          break;
                        case 'cashier':
                          roleTitle = 'أمين الصندوق (Cashier)';
                          roleIcon = Icons.point_of_sale;
                          break;
                        case 'driver':
                          roleTitle = 'سائق التوصيل (Driver)';
                          roleIcon = Icons.local_shipping;
                          break;
                        case 'customer':
                          roleTitle = 'زبون جملة (Customer)';
                          roleIcon = Icons.shopping_bag;
                          break;
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(roleIcon, color: theme.colorScheme.onPrimaryContainer, size: 20),
                        ),
                        title: Row(
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainer,
                                borderRadius: AppRadius.smAll,
                              ),
                              child: Text(
                                roleTitle,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text('رقم الهاتف: $phone', style: theme.textTheme.bodySmall),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusBadge(
                              type: active ? StatusBadgeType.completed : StatusBadgeType.cancelled,
                              customLabel: active ? 'نشط (Actif)' : 'معطل',
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            FilledButton.tonalIcon(
                              onPressed: () => _showGeneratePinDialog(user),
                              icon: const Icon(Icons.pin_outlined, size: 16),
                              label: const Text('توليد PIN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const AppLoadingView(message: 'جاري جلب قائمة الموظفين...'),
              error: (err, _) => AppErrorView(
                message: 'تعذر الاتصال بقاعدة البيانات',
                onRetry: () => ref.invalidate(staffMembersProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
