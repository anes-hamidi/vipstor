import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import '../../providers/staff_providers.dart';
import '../../router/staff_router.dart';
import 'widgets/create_staff_dialog.dart';
import 'widgets/generate_staff_pin_dialog.dart';
import 'widgets/audit_log_details_dialog.dart';
import 'widgets/staff_profile_edit_sheet.dart';
import '../cashier/widgets/supplier_payment_dialog.dart';
import '../cashier/widgets/driver_settlement_dialog.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final auditSearchQueryProvider    = StateProvider<String>((ref) => '');
final auditActorFilterProvider    = StateProvider<String>((ref) => 'all');
final auditCategoryFilterProvider = StateProvider<String>((ref) => 'all');

/// Full KPI + cash-flow data in one query batch.
final moderatorStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  // Orders: total sales, collected, uncollected, by channel
  final orderRows = await client
      .from('orders')
      .select('total_amount, paid_amount, channel, status, created_at');

  int totalSales = 0, totalCollected = 0, storeSales = 0, onlineSales = 0;
  int deliveredCount = 0, pendingCount = 0, cancelledCount = 0;

  // Daily sales for 7-day sparkline
  final Map<String, int> dailySales = {};
  final now = DateTime.now();
  for (var i = 6; i >= 0; i--) {
    final d = now.subtract(Duration(days: i));
    dailySales['${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}'] = 0;
  }

  for (final r in orderRows as List) {
    final amt  = (r['total_amount'] as num?)?.toInt() ?? 0;
    final paid = (r['paid_amount']  as num?)?.toInt() ?? 0;
    final ch   = r['channel'] as String? ?? 'store';
    final st   = r['status']  as String? ?? '';
    final rawDate = r['created_at'] as String?;

    totalSales     += amt;
    totalCollected += paid;
    if (ch == 'store')  storeSales  += amt;
    if (ch == 'online') onlineSales += amt;
    if (st == 'delivered' || st == 'settled') {
      deliveredCount++;
    } else if (st == 'cancelled') {
      cancelledCount++;
    } else {
      pendingCount++;
    }

    if (rawDate != null) {
      final d = DateTime.tryParse(rawDate)?.toLocal();
      if (d != null) {
        final key = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
        if (dailySales.containsKey(key)) dailySales[key] = dailySales[key]! + amt;
      }
    }
  }

  // Driver wallets
  final walletRows = await client.from('view_driver_wallet_balance').select('current_wallet_balance');
  int totalDriverCash = 0;
  for (final w in walletRows as List) {
    totalDriverCash += (w['current_wallet_balance'] as num?)?.toInt() ?? 0;
  }

  // Customer debt
  final customerRows = await client.from('view_customer_balance').select('current_balance, credit_limit');
  int totalCustomerDebt = 0, totalCreditLimit = 0;
  for (final c in customerRows as List) {
    totalCustomerDebt += (c['current_balance'] as num?)?.toInt() ?? 0;
    totalCreditLimit  += (c['credit_limit']    as num?)?.toInt() ?? 0;
  }

  // Supplier debt
  final supplierRows = await client.from('view_supplier_balance').select('current_balance');
  int totalSupplierDebt = 0;
  for (final s in supplierRows as List) {
    totalSupplierDebt += (s['current_balance'] as num?)?.toInt() ?? 0;
  }

  // Inventory value (stock on hand × last_unit_cost)
  final stockRows = await client
      .from('view_product_stock')
      .select('on_hand_qty, last_unit_cost, available_qty');
  int inventoryValue = 0, lowStockCount = 0, outOfStockCount = 0;
  for (final s in stockRows as List) {
    final qty  = (s['on_hand_qty']    as num?)?.toInt() ?? 0;
    final cost = (s['last_unit_cost'] as num?)?.toInt() ?? 0;
    final avail = (s['available_qty'] as num?)?.toInt() ?? 0;
    inventoryValue += qty * cost;
    if (avail <= 0) {
      outOfStockCount++;
    } else if (avail < 5) {
      lowStockCount++;
    }
  }

  // Staff count
  final staffRows = await client.from('users').select('role, active').neq('role', 'customer');
  int activeStaff = 0, inactiveStaff = 0;
  for (final s in staffRows as List) {
    if (s['active'] == true) {
      activeStaff++;
    } else {
      inactiveStaff++;
    }
  }

  // Cash flow: net = collected - supplier_debt
  final netCashFlow = totalCollected - totalSupplierDebt;
  // Gross profit estimate: sales - (supplier payments this month)
  final grossMargin = totalSales > 0
      ? ((totalSales - totalSupplierDebt) / totalSales * 100).clamp(0, 100).round()
      : 0;

  return {
    'total_sales':       totalSales,
    'total_collected':   totalCollected,
    'uncollected':       totalSales - totalCollected,
    'store_sales':       storeSales,
    'online_sales':      onlineSales,
    'driver_cash':       totalDriverCash,
    'customer_debt':     totalCustomerDebt,
    'credit_limit':      totalCreditLimit,
    'supplier_debt':     totalSupplierDebt,
    'net_cash_flow':     netCashFlow,
    'gross_margin_pct':  grossMargin,
    'inventory_value':   inventoryValue,
    'low_stock_count':   lowStockCount,
    'out_of_stock_count':outOfStockCount,
    'delivered_count':   deliveredCount,
    'pending_count':     pendingCount,
    'cancelled_count':   cancelledCount,
    'active_staff':      activeStaff,
    'inactive_staff':    inactiveStaff,
    'daily_sales':       dailySales,
  };
});

final auditTrailLogsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    // Use the enriched view which has human-readable titles, actor info,
    // and covers all audited tables including addresses/suppliers/prices.
    final rows = await client
        .from('view_audit_log_enriched')
        .select()
        .order('created_at', ascending: false)
        .limit(500);

    return (rows as List).map((r) {
      return {
        'id':               r['id'],
        'created_at':       r['created_at'],
        'action':           r['action'] as String? ?? '',
        'target_table':     r['target_table'] as String? ?? '',
        'target_id':        r['target_id'],
        'user_id':          r['user_id'] ?? '',
        'actor_name':       r['actor_name'] ?? 'النظام',
        'actor_role':       r['actor_role'] ?? 'system',
        'actor_phone':      r['actor_phone'] ?? '',
        'intelligent_title': r['intelligent_title'] ?? r['action'],
        'category':         r['category'] ?? 'عام',
        'actor_type':       (r['actor_role'] == 'customer')
                                ? 'customer'
                                : (['cashier','driver','manager','moderator']
                                    .contains(r['actor_role'])
                                        ? 'staff'
                                        : 'system'),
      };
    }).toList();
  } catch (_) {
    return [];
  }
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ModeratorDashboardScreen extends ConsumerStatefulWidget {
  const ModeratorDashboardScreen({super.key});

  @override
  ConsumerState<ModeratorDashboardScreen> createState() =>
      _ModeratorDashboardScreenState();
}

class _ModeratorDashboardScreenState
    extends ConsumerState<ModeratorDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(moderatorStatsProvider);
    ref.invalidate(staffMembersProvider);
    ref.invalidate(auditTrailLogsProvider);
    ref.invalidate(liveStaffUsersProvider);
  }

  Future<void> _checkUpdatesManually() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جاري التحقق من تحديثات النظام...'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final res = await ref.read(appUpdateServiceProvider).checkForUpdate();
      if (!mounted) return;
      if (res.hasUpdate) {
        final service = ref.read(appUpdateServiceProvider);
        AppUpdateDialog.show(
          context,
          release: res.newRelease!,
          currentVersion: res.currentVersion,
          currentBuild: res.currentBuild,
          updateService: service,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('أنت تستخدم أحدث إصدار متوفر (v${res.currentVersion} #${res.currentBuild})'),
            backgroundColor: const Color(0xFF1E3A2F),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر التحقق من التحديثات: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateProvider);
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0908) : const Color(0xFFFAF7F2),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0A0908) : const Color(0xFFFAF7F2),
        elevation: 0,
        title: Row(
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.gold,
                borderRadius: AppRadius.smAll,
                boxShadow: [AppShadows.goldGlowSm],
              ),
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.admin_panel_settings_rounded,
                    size: 18, color: Color(0xFF1A1400)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('لوحة المشرف العام',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(authUser?.name ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFD4AF37), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded),
            tooltip: 'التحقق من التحديثات',
            onPressed: _checkUpdatesManually,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'خروج',
            onPressed: () => ref.read(authStateProvider.notifier).state = null,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFD4AF37),
          indicatorWeight: 2.5,
          labelColor: const Color(0xFFD4AF37),
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_rounded, size: 18), text: 'المؤشرات'),
            Tab(icon: Icon(Icons.history_edu_rounded, size: 18), text: 'التدقيق'),
            Tab(icon: Icon(Icons.badge_rounded, size: 18), text: 'الموظفون'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _KpiTab(onGoAudit: () => _tabs.animateTo(1)),
          _AuditTab(),
          _StaffTab(),
        ],
      ),
    );
  }
}

// ── KPI Tab ───────────────────────────────────────────────────────────────────

class _KpiTab extends ConsumerWidget {
  final VoidCallback onGoAudit;
  const _KpiTab({required this.onGoAudit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(moderatorStatsProvider);
    return statsAsync.when(
      data: (s) => _KpiContent(stats: s, onGoAudit: onGoAudit, ref: ref),
      loading: () => AppStates.loading(message: 'جاري جلب المؤشرات...'),
      error: (e, _) => AppStates.error('تعذر تحميل البيانات',
          onRetry: () => ref.invalidate(moderatorStatsProvider)),
    );
  }
}

class _KpiContent extends StatelessWidget {
  final Map<String, dynamic> stats;
  final VoidCallback onGoAudit;
  final WidgetRef ref;
  const _KpiContent({required this.stats, required this.onGoAudit, required this.ref});

  void _openSupplierPayment(BuildContext context) {
    final authUser = ref.read(authStateProvider);
    SupplierPaymentDialog.show(
      context,
      payerId: authUser?.id ?? 'moderator',
      payerName: authUser?.name ?? 'المشرف العام',
      payerRole: 'Moderator (مشرف عام)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = context.appColors;
    final isDark = theme.brightness == Brightness.dark;

    final dailySales = Map<String, int>.from(stats['daily_sales'] as Map);
    final salesValues = dailySales.values.toList();

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Cash flow summary card ─────────────────────────────────
          _CashFlowCard(stats: stats, isDark: isDark),
          const SizedBox(height: AppSpacing.lg),

          // ── 7-day sparkline ────────────────────────────────────────
          LuxuryCard(
            goldAccent: true,
            padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('المبيعات — آخر 7 أيام',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      DzdFormatter.formatCentimes(
                          salesValues.fold(0, (a, b) => a + b)),
                      style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 80,
                  child: _BarSparkline(values: salesValues, isDark: isDark),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: dailySales.keys.map((k) {
                    final parts = k.split('-');
                    return Text('${parts[2]}/${parts[1]}',
                        style: const TextStyle(fontSize: 9, color: Colors.grey));
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── KPI grid ───────────────────────────────────────────────
          Text('المؤشرات التفصيلية',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.6,
            children: [
              _MiniKpi(
                label: 'كاش عند السائقين',
                value: DzdFormatter.formatCentimes(stats['driver_cash'] as int),
                icon: Icons.account_balance_wallet_rounded,
                color: colors.warning,
              ),
              _MiniKpi(
                label: 'ديون الزبائن',
                value: DzdFormatter.formatCentimes(stats['customer_debt'] as int),
                icon: Icons.people_alt_rounded,
                color: colors.info,
              ),
              _MiniKpi(
                label: 'مستحقات الموردين',
                value: DzdFormatter.formatCentimes(stats['supplier_debt'] as int),
                icon: Icons.local_shipping_rounded,
                color: colors.error,
                onTap: () => _openSupplierPayment(context),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                    borderRadius: AppRadius.xsAll,
                    border: Border.all(color: const Color(0xFFD4AF37), width: 0.8),
                  ),
                  child: const Text(
                    'تسديد نقدًا',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37)),
                  ),
                ),
              ),
              _MiniKpi(
                label: 'قيمة المخزون',
                value: DzdFormatter.formatCentimes(stats['inventory_value'] as int),
                icon: Icons.inventory_2_rounded,
                color: colors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Orders donut + inventory status ───────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LuxuryCard(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                  child: Column(
                    children: [
                      Text('حالة الطلبيات',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        height: 110,
                        child: _DonutChart(
                          segments: [
                            _DonutSegment(
                                label: 'مُسلَّمة',
                                value: (stats['delivered_count'] as int).toDouble(),
                                color: colors.success),
                            _DonutSegment(
                                label: 'قيد المعالجة',
                                value: (stats['pending_count'] as int).toDouble(),
                                color: colors.warning),
                            _DonutSegment(
                                label: 'ملغاة',
                                value: (stats['cancelled_count'] as int).toDouble(),
                                color: colors.error),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _DonutLegend(segments: [
                        _DonutSegment(label: 'مُسلَّمة (${stats['delivered_count']})',  value: 0, color: colors.success),
                        _DonutSegment(label: 'معالجة (${stats['pending_count']})',   value: 0, color: colors.warning),
                        _DonutSegment(label: 'ملغاة (${stats['cancelled_count']})',     value: 0, color: colors.error),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LuxuryCard(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('حالة المخزون',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: AppSpacing.md),
                      _StockStatusRow(
                        label: 'مخزون منخفض',
                        count: stats['low_stock_count'] as int,
                        color: colors.warning,
                        icon: Icons.warning_amber_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _StockStatusRow(
                        label: 'نفد المخزون',
                        count: stats['out_of_stock_count'] as int,
                        color: colors.error,
                        icon: Icons.cancel_rounded,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _StockStatusRow(
                        label: 'موظف نشط',
                        count: stats['active_staff'] as int,
                        color: colors.success,
                        icon: Icons.person_rounded,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _StockStatusRow(
                        label: 'حساب معطل',
                        count: stats['inactive_staff'] as int,
                        color: colors.error,
                        icon: Icons.person_off_rounded,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Audit trail link ───────────────────────────────────────
          LuxuryCard(
            padding: const EdgeInsetsDirectional.all(AppSpacing.md),
            child: Row(
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.gold,
                    shape: BoxShape.circle,
                    boxShadow: [AppShadows.goldGlowSm],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.shield_rounded,
                        size: 18, color: Color(0xFF1A1400)),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('سجل التدقيق الكامل',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('جميع العمليات موثقة ومحمية',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                GoldButton.icon(
                  icon: Icons.arrow_forward_rounded,
                  label: 'فتح',
                  onPressed: onGoAudit,
                  compact: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Cash-flow summary card
class _CashFlowCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final bool isDark;
  const _CashFlowCard({required this.stats, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = stats['net_cash_flow'] as int;
    final isPositive = net >= 0;
    final netColor = isPositive ? context.appColors.success : context.appColors.error;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF1A1400), Color(0xFF2A2010)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)
            : const LinearGradient(
                colors: [Color(0xFF3D2B00), Color(0xFF6B4A00)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
        boxShadow: const [AppShadows.goldRim],
      ),
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  color: Color(0xFFD4AF37), size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text('التدفق النقدي الصافي',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFFD4AF37),
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: netColor.withValues(alpha: 0.2),
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(color: netColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      color: netColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      isPositive ? 'إيجابي' : 'سلبي',
                      style: TextStyle(
                          color: netColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            DzdFormatter.formatCentimes(net.abs()),
            style: const TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Color(0x33D4AF37)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _CfRow(
                  label: 'إجمالي المبيعات',
                  value: DzdFormatter.formatCentimes(stats['total_sales'] as int),
                  color: const Color(0xFFD4AF37),
                ),
              ),
              Expanded(
                child: _CfRow(
                  label: 'تم تحصيله',
                  value: DzdFormatter.formatCentimes(stats['total_collected'] as int),
                  color: context.appColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _CfRow(
                  label: 'غير محصَّل',
                  value: DzdFormatter.formatCentimes(stats['uncollected'] as int),
                  color: context.appColors.warning,
                ),
              ),
              Expanded(
                child: _CfRow(
                  label: 'هامش الربح',
                  value: '${stats['gross_margin_pct']}%',
                  color: context.appColors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CfRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _CfRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFFB8A882), fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      );
}

// ── Chart Widgets ─────────────────────────────────────────────────────────────

class _BarSparkline extends StatelessWidget {
  final List<int> values;
  final bool isDark;
  const _BarSparkline({required this.values, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarPainter(values: values, isDark: isDark),
      size: Size.infinite,
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<int> values;
  final bool isDark;
  _BarPainter({required this.values, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values.reduce(math.max).toDouble();
    if (maxVal == 0) return;

    const gap = 4.0;
    final barW = (size.width - gap * (values.length - 1)) / values.length;
    const radius = Radius.circular(3);

    for (var i = 0; i < values.length; i++) {
      final ratio = values[i] / maxVal;
      final barH = size.height * ratio;
      final x = i * (barW + gap);
      final y = size.height - barH;

      final isToday = i == values.length - 1;
      final paint = Paint()
        ..shader = LinearGradient(
          colors: isToday
              ? [const Color(0xFFEDD97A), const Color(0xFFD4AF37)]
              : [
                  const Color(0xFFD4AF37).withValues(alpha: 0.5),
                  const Color(0xFFD4AF37).withValues(alpha: 0.25),
                ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(x, y, barW, barH));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.isDark != isDark;
}

class _DonutSegment {
  final String label;
  final double value;
  final Color color;
  const _DonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _DonutChart extends StatelessWidget {
  final List<_DonutSegment> segments;
  const _DonutChart({required this.segments});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutPainter(segments: segments),
      size: Size.infinite,
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  _DonutPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (a, b) => a + b.value);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    const strokeW = 18.0;
    double startAngle = -math.pi / 2;

    for (final seg in segments) {
      final sweep = 2 * math.pi * seg.value / total;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
      startAngle += sweep + 0.02; // gap
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.segments != segments;
}

class _DonutLegend extends StatelessWidget {
  final List<_DonutSegment> segments;
  const _DonutLegend({required this.segments});

  @override
  Widget build(BuildContext context) => Column(
        children: segments
            .map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: s.color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(s.label,
                          style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ))
            .toList(),
      );
}

class _MiniKpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _MiniKpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgAll,
      child: LuxuryCard(
        padding: const EdgeInsetsDirectional.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _StockStatusRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _StockStatusRow(
      {required this.label,
      required this.count,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: AppRadius.pillAll,
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      );
}

// ── Audit Tab ─────────────────────────────────────────────────────────────────

class _AuditTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync      = ref.watch(auditTrailLogsProvider);
    final searchQuery     = ref.watch(auditSearchQueryProvider).trim().toLowerCase();
    final actorFilter     = ref.watch(auditActorFilterProvider);
    final categoryFilter  = ref.watch(auditCategoryFilterProvider);

    return Column(
      children: [
        // Filter bar
        _AuditFilterBar(),
        const Divider(height: 1),
        Expanded(
          child: auditAsync.when(
            data: (logs) {
              final filtered = logs.where((item) {
                if (actorFilter != 'all' && item['actor_type'] != actorFilter) return false;
                if (categoryFilter != 'all' && item['category'] != categoryFilter) return false;
                if (searchQuery.isNotEmpty) {
                  final hay = [
                    item['intelligent_title'], item['actor_name'],
                    item['target_table'], item['action'],
                  ].join(' ').toLowerCase();
                  if (!hay.contains(searchQuery)) return false;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return AppStates.empty(
                  icon: Icons.history_toggle_off_rounded,
                  title: 'لا توجد سجلات مطابقة',
                  description: 'غيِّر معايير البحث أو التصفية',
                );
              }

              return ListView.separated(
                padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (ctx, i) =>
                    _AuditRow(log: filtered[i]),
              );
            },
            loading: () => AppStates.loading(message: 'جاري جلب السجل...'),
            error: (e, _) => AppStates.error('تعذر تحميل السجل',
                onRetry: () => ref.invalidate(auditTrailLogsProvider)),
          ),
        ),
      ],
    );
  }
}

class _AuditFilterBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme          = Theme.of(context);
    final searchQuery    = ref.watch(auditSearchQueryProvider);
    final actorFilter    = ref.watch(auditActorFilterProvider);
    final categoryFilter = ref.watch(auditCategoryFilterProvider);

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Column(
        children: [
          // Search
          TextField(
            decoration: InputDecoration(
              hintText: 'بحث في العمليات...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              contentPadding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              border: OutlineInputBorder(
                  borderRadius: AppRadius.mdAll,
                  borderSide:
                      BorderSide(color: theme.colorScheme.outlineVariant)),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () =>
                          ref.read(auditSearchQueryProvider.notifier).state =
                              '',
                    )
                  : null,
            ),
            onChanged: (v) =>
                ref.read(auditSearchQueryProvider.notifier).state = v,
          ),
          const SizedBox(height: AppSpacing.sm),
          // Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(label: 'الكل',     value: 'all',      current: actorFilter,    onTap: (v) => ref.read(auditActorFilterProvider.notifier).state = v),
                _FilterChip(label: 'موظفون',   value: 'staff',    current: actorFilter,    onTap: (v) => ref.read(auditActorFilterProvider.notifier).state = v),
                _FilterChip(label: 'زبائن',    value: 'customer', current: actorFilter,    onTap: (v) => ref.read(auditActorFilterProvider.notifier).state = v),
                const SizedBox(width: AppSpacing.md),
                _FilterChip(label: 'مبيعات',   value: 'sales',    current: categoryFilter, onTap: (v) => ref.read(auditCategoryFilterProvider.notifier).state = v, isCategory: true),
                _FilterChip(label: 'مالية',    value: 'finance',  current: categoryFilter, onTap: (v) => ref.read(auditCategoryFilterProvider.notifier).state = v, isCategory: true),
                _FilterChip(label: 'مخزون',    value: 'inventory',current: categoryFilter, onTap: (v) => ref.read(auditCategoryFilterProvider.notifier).state = v, isCategory: true),
                _FilterChip(label: 'أمان',     value: 'security', current: categoryFilter, onTap: (v) => ref.read(auditCategoryFilterProvider.notifier).state = v, isCategory: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onTap;
  final bool isCategory;
  const _FilterChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
    this.isCategory = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = current == value || (value == 'all' && current == 'all');
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFD4AF37).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: selected
                  ? const Color(0xFFD4AF37)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected
                  ? const Color(0xFFD4AF37)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditRow extends ConsumerWidget {
  final Map<String, dynamic> log;
  const _AuditRow({required this.log});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme  = Theme.of(context);
    final colors = context.appColors;
    final action = (log['action'] as String? ?? '').toUpperCase();
    final table  = log['target_table'] as String? ?? '';
    final name   = log['actor_name']  as String? ?? 'النظام';
    final rawDate = log['created_at'] as String?;
    final date   = rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null;

    Color actionColor;
    IconData actionIcon;
    switch (action) {
      case 'INSERT':
        actionColor = colors.success; actionIcon = Icons.add_circle_outline_rounded; break;
      case 'UPDATE':
        actionColor = colors.warning; actionIcon = Icons.edit_rounded; break;
      case 'DELETE':
        actionColor = colors.error;   actionIcon = Icons.delete_rounded; break;
      default:
        actionColor = colors.info;    actionIcon = Icons.info_rounded;
    }

    return LuxuryCard(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: () => showDialog(
          context: context,
          builder: (_) => AuditLogDetailsDialog(log: log),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(actionIcon, color: actionColor, size: 18),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${log['intelligent_title'] ?? '$action ← $table'}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: 0.12),
                          borderRadius: AppRadius.xsAll,
                        ),
                        child: Text(action,
                            style: TextStyle(
                                color: actionColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.person_rounded,
                          size: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(name,
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11)),
                      const Spacer(),
                      if (date != null)
                        Text(
                          '${date.day}/${date.month} ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 10, color: theme.colorScheme.outline),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

// ── Staff Tab ─────────────────────────────────────────────────────────────────

class _StaffTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends ConsumerState<_StaffTab> {
  Future<void> _addStaff() async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const CreateStaffDialog(),
    );
    if (res != null && mounted) {
      ref.invalidate(staffMembersProvider);
      ref.invalidate(liveStaffUsersProvider);
      final pin = res['pin'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم إنشاء حساب "${res['name']}"'
            '${pin != null ? " — PIN: $pin" : ""}'),
        backgroundColor: context.appColors.success,
      ));
    }
  }

  Future<void> _editProfile(Map<String, dynamic> user) async {
    final changed = await StaffProfileEditSheet.show(
      context, ref,
      userId:   user['id']       as String,
      name:     user['name']     as String?  ?? '',
      phone:    user['phone']    as String?  ?? '',
      role:     user['role']     as String?  ?? 'cashier',
      active:   user['active']   as bool?    ?? true,
      language: user['language'] as String?  ?? 'ar',
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم تحديث الملف الشخصي')));
    }
  }

  Future<void> _resetPin(Map<String, dynamic> user) async {
    await showDialog(
      context: context,
      builder: (_) => GenerateStaffPinDialog(staffUser: user),
    );
    if (mounted) ref.invalidate(auditTrailLogsProvider);
  }

  Future<void> _settleDriver([Map<String, dynamic>? user]) async {
    final moderator = ref.read(authStateProvider);
    await DriverSettlementDialog.show(
      context,
      receiverId: moderator?.id ?? '',
      receiverName: moderator?.name ?? 'المشرف العام',
      receiverRole: 'moderator',
      initialDriverId: user != null ? user['id'] as String? : null,
      initialDriverName: user != null ? user['name'] as String? : null,
    );
    if (mounted) {
      ref.invalidate(moderatorStatsProvider);
      ref.invalidate(staffMembersProvider);
      ref.invalidate(pendingDriverSettlementsProvider);
      ref.invalidate(auditTrailLogsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffMembersProvider);
    final theme = Theme.of(context);

    return staffAsync.when(
      data: (staff) {
        if (staff.isEmpty) {
          return AppStates.empty(
            icon: Icons.people_outline_rounded,
            title: 'لا يوجد موظفون مسجلون',
            description: 'قم بإضافة موظفين لتفعيل صلاحياتهم',
            actionLabel: 'إضافة موظف',
            onAction: _addStaff,
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  Text('${staff.length} موظف مسجل',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GoldButton.icon(
                    icon: Icons.payments_rounded,
                    label: 'تسوية عهدة السائقين',
                    onPressed: () => _settleDriver(),
                    compact: true,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GoldButton.icon(
                    icon: Icons.person_add_rounded,
                    label: 'موظف جديد',
                    onPressed: _addStaff,
                    compact: true,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                itemCount: staff.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (ctx, i) => _StaffCard(
                  user: staff[i],
                  onEdit:     () => _editProfile(staff[i]),
                  onResetPin: () => _resetPin(staff[i]),
                  onSettle:   staff[i]['role'] == 'driver' ? () => _settleDriver(staff[i]) : null,
                ),
              ),
            ),
          ],
        );
      },
      loading: () => AppStates.loading(message: 'جاري جلب الموظفين...'),
      error: (e, _) => AppStates.error('تعذر تحميل قائمة الموظفين',
          onRetry: () => ref.invalidate(staffMembersProvider)),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onEdit;
  final VoidCallback onResetPin;
  final VoidCallback? onSettle;
  const _StaffCard({
    required this.user,
    required this.onEdit,
    required this.onResetPin,
    this.onSettle,
  });

  static const _roleData = {
    'moderator': ('مشرف عام',     Icons.admin_panel_settings_rounded),
    'manager':   ('مدير مخزون',   Icons.inventory_2_rounded),
    'cashier':   ('أمين صندوق',   Icons.point_of_sale_rounded),
    'driver':    ('سائق توصيل',   Icons.local_shipping_rounded),
    'customer':  ('زبون جملة',    Icons.shopping_bag_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final colors = context.appColors;
    final role   = user['role']   as String? ?? 'cashier';
    final name   = user['name']   as String? ?? 'موظف';
    final phone  = user['phone']  as String? ?? '';
    final active = user['active'] as bool?   ?? true;
    final (roleLabel, roleIcon) = _roleData[role] ?? ('موظف', Icons.person_rounded);

    return LuxuryCard(
      selected: active,
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: active ? AppGradients.obsidianGold : null,
              color: active ? null : theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? const Color(0xFFD4AF37).withValues(alpha: 0.6)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Icon(roleIcon,
                size: 22,
                color: active
                    ? const Color(0xFFD4AF37)
                    : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: AppSpacing.md),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: AppSpacing.xs),
                    if (!active)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.12),
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: Text('معطل',
                            style: TextStyle(
                                color: colors.error,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(roleLabel,
                    style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                Text(phone,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                if (role == 'driver')
                  Consumer(
                    builder: (context, ref, _) {
                      final pendingList = ref.watch(pendingDriverSettlementsProvider).valueOrNull ?? [];
                      final driverSumm = pendingList.where((d) => d.driverId == user['id']).firstOrNull;
                      final bal = driverSumm?.pendingCashCentimes ?? 0;
                      if (bal <= 0) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '✓ العهدة مسواة (0 دج)',
                            style: TextStyle(color: colors.success, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.gold.withValues(alpha: 0.15),
                                borderRadius: AppRadius.pillAll,
                                border: Border.all(color: colors.gold.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                'العهدة الحالية: ${DzdFormatter.formatCentimes(bal)} (${driverSumm?.unsettledOrdersCount ?? 0} طلبات)',
                                style: TextStyle(
                                  color: colors.gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          // Actions
          Column(
            children: [
              if (onSettle != null) ...[
                GoldIconButton(
                  icon: Icons.payments_rounded,
                  tooltip: 'تسوية عهدة السائق (نقدًا)',
                  onPressed: onSettle,
                  size: 34,
                ),
                const SizedBox(height: 4),
              ],
              GoldIconButton(
                icon: Icons.manage_accounts_rounded,
                tooltip: 'تعديل الملف الشخصي',
                onPressed: onEdit,
                size: 34,
              ),
              const SizedBox(height: 4),
              IconButton(
                icon: const Icon(Icons.pin_rounded, size: 18),
                tooltip: 'إعادة توليد PIN',
                onPressed: onResetPin,
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  minimumSize: const Size(34, 34),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
