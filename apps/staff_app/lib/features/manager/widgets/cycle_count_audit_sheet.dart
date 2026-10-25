import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../../common/widgets/headless_barcode_scanner_button.dart';
import '../../common/services/headless_barcode_scanner_service.dart';



class CycleCountAuditSheet extends ConsumerStatefulWidget {
  const CycleCountAuditSheet({super.key});

  @override
  ConsumerState<CycleCountAuditSheet> createState() =>
      _CycleCountAuditSheetState();
}

class _CycleCountAuditSheetState extends ConsumerState<CycleCountAuditSheet> {
  final _searchController = TextEditingController();
  String _search = '';
  bool _onlyDiscrepancies = false;
  String _abcFilter = 'all'; // 'all', 'A', 'B', 'C'
  bool _isReconciling = false;
  final _reconciliationNotesCtrl = TextEditingController();

  @override
  void dispose() {
    HeadlessBarcodeScannerService.instance.stopScanning();
    _searchController.dispose();
    _reconciliationNotesCtrl.dispose();
    super.dispose();
  }

  String _getAbcClass(CycleCountItemEntity item) {
    final value = item.systemStock * item.unitCostCentimes;
    if (item.unitCostCentimes >= 500000 || value >= 5000000) {
      return 'A'; // High-value items: weekly audit
    } else if (item.unitCostCentimes >= 100000 || value >= 1000000) {
      return 'B'; // Medium items: bi-weekly audit
    } else {
      return 'C'; // Bulk/low-cost: monthly audit
    }
  }

  Future<void> _startNewAudit() async {
    final authUser = ref.read(authStateProvider);
    final repo = ref.read(inventoryRepositoryProvider);

    final audit = await repo.startCycleCount(
      locationId: 'loc_main',
      locationName: 'المستودع الرئيسي',
      userId: authUser?.id ?? 'manager',
      userName: authUser?.name ?? 'مدير المخزون',
    );

    ref.read(activeCycleCountProvider.notifier).state = audit;
  }

  Future<void> _reconcileAudit(CycleCountAuditEntity audit) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد تسوية الجرد واعتماد الأرصدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سيتم تعديل أرصدة (${audit.discrepantItemsCount}) منتج ذات الفروقات مباشرة في قاعدة البيانات المحلية والسحابية.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'الأثر المالي الإجمالي: ${DzdFormatter.formatCentimes(audit.netCostVarianceCentimes)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: audit.netCostVarianceCentimes < 0 ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reconciliationNotesCtrl,
              decoration: const InputDecoration(
                labelText: 'مبررات التسوية (اختياري)',
                hintText: 'مثال: جرد نهاية الشهر المعتمد...',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          GoldButton(
            label: 'تأكيد التسوية',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final authUser = ref.read(authStateProvider);
    final repo = ref.read(inventoryRepositoryProvider);

    setState(() => _isReconciling = true);
    try {
      final reconciled = await repo.reconcileAudit(
        auditId: audit.id,
        userId: authUser?.id ?? 'manager',
        userName: authUser?.name ?? 'مدير المخزون',
        reconciliationNotes: _reconciliationNotesCtrl.text.trim(),
      );

      ref.read(activeCycleCountProvider.notifier).state = reconciled;
      ref.invalidate(liveProductsProvider);
      ref.invalidate(lowStockProductsProvider);
      ref.invalidate(auditHistoryProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت تسوية الجرد [${reconciled.auditNumber}] بنجاح!'),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسوية الجرد: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReconciling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final audit = ref.watch(activeCycleCountProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0C0A) : const Color(0xFFF8F5EE),
      appBar: AppBar(
        title: const Text('الجرد الدوري والمطابقة الحية (Cycle Counting)'),
        backgroundColor: isDark ? const Color(0xFF141210) : const Color(0xFFFBF8F0),
        actions: [
          if (audit != null && audit.status == AuditStatus.inProgress)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
              child: GoldButton.icon(
                icon: Icons.done_all_rounded,
                label: _isReconciling ? 'جاري الاعتماد...' : 'تسوية واعتماد الأرصدة',
                onPressed: _isReconciling ? null : () => _reconcileAudit(audit),
                compact: true,
              ),
            ),
        ],
      ),
      body: audit == null ? _buildNoActiveAuditView(theme) : _buildActiveAuditView(audit, theme, isDark),
    );
  }

  Widget _buildNoActiveAuditView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fact_check_outlined, size: 72, color: Color(0xFFD4AF37)),
            AppSpacing.gapLg,
            Text(
              'لا يوجد جرد نشط حالياً',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            AppSpacing.gapSm,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'يمكنك بدء جلسة جرد دوري دون إيقاف عمليات البيع والصندوق. ستقوم بمطابقة المخزون الفعلي مع النظام وحساب الفروقات آلياً.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            AppSpacing.gapXl,
            GoldButton.icon(
              icon: Icons.play_arrow_rounded,
              label: 'بدء دورة جرد جديدة الآن',
              onPressed: _startNewAudit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAuditView(CycleCountAuditEntity audit, ThemeData theme, bool isDark) {
    final filteredItems = audit.items.where((it) {
      if (_onlyDiscrepancies && !it.hasDiscrepancy) return false;
      if (_abcFilter != 'all' && _getAbcClass(it) != _abcFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        return it.productName.toLowerCase().contains(q) ||
            it.category.toLowerCase().contains(q) ||
            it.barcodes.any((b) => b.contains(q));
      }
      return true;
    }).toList();

    return Column(
      children: [
        // KPI Summary Bar
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          color: isDark ? const Color(0xFF191714) : Colors.white,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  _statItem(
                    label: 'إجمالي الأصناف',
                    value: '${audit.totalItemsCount}',
                    icon: Icons.inventory_2_outlined,
                  ),
                  _statItem(
                    label: 'أصناف مطابقة',
                    value: '${audit.matchedItemsCount}',
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  _statItem(
                    label: 'أصناف بها فروقات',
                    value: '${audit.discrepantItemsCount}',
                    icon: Icons.warning_amber_rounded,
                    color: audit.discrepantItemsCount > 0 ? Colors.orange : Colors.green,
                  ),
                  _statItem(
                    label: 'نسبة الدقة',
                    value: '${audit.accuracyRate.toStringAsFixed(1)}%',
                    icon: Icons.analytics_outlined,
                    color: const Color(0xFFD4AF37),
                  ),
                  _statItem(
                    label: 'صافي أثر التكلفة',
                    value: DzdFormatter.formatCentimes(audit.netCostVarianceCentimes),
                    icon: Icons.attach_money_rounded,
                    color: audit.netCostVarianceCentimes < 0 ? Colors.red : Colors.green,
                  ),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),

        // ABC Analysis & Filter Bar
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  selected: _abcFilter == 'all',
                  label: const Text('جميع الأصناف'),
                  onSelected: (_) => setState(() => _abcFilter = 'all'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilterChip(
                  selected: _abcFilter == 'A',
                  avatar: const CircleAvatar(
                    backgroundColor: Color(0xFFD4AF37),
                    radius: 8,
                    child: Text('A', style: TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                  label: const Text('فئة A (عالية القيمة - أسبوعي)'),
                  onSelected: (_) => setState(() => _abcFilter = 'A'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilterChip(
                  selected: _abcFilter == 'B',
                  avatar: const CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    radius: 8,
                    child: Text('B', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  label: const Text('فئة B (متوسطة - نصف شهري)'),
                  onSelected: (_) => setState(() => _abcFilter = 'B'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilterChip(
                  selected: _abcFilter == 'C',
                  avatar: const CircleAvatar(
                    backgroundColor: Colors.grey,
                    radius: 8,
                    child: Text('C', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  label: const Text('فئة C (حجمية وعادية - شهري)'),
                  onSelected: (_) => setState(() => _abcFilter = 'C'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilterChip(
                  selected: _onlyDiscrepancies,
                  label: Text('الفروقات فقط (${audit.discrepantItemsCount})'),
                  onSelected: (val) => setState(() => _onlyDiscrepancies = val),
                ),
              ],
            ),
          ),
        ),

        // Controls bar: Search
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'بحث عن منتج في الجرد (اسم، باركود)...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HeadlessBarcodeScannerButton(
                          controller: _searchController,
                          onScanned: (code) {
                            setState(() => _search = code.trim());
                          },
                          tooltip: 'مسح باركود المنتج بالجرد',
                        ),
                        if (_search.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          ),
                      ],
                    ),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim()),
                ),
              ),
            ],
          ),
        ),

        // Virtualized List of Audit Items
        Expanded(
          child: filteredItems.isEmpty
              ? const Center(child: Text('لا توجد منتجات مطابقة'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  itemCount: filteredItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (ctx, i) {
                    final item = filteredItems[i];
                    return _AuditItemRow(
                      item: item,
                      abcClass: _getAbcClass(item),
                      isReadOnly: audit.status != AuditStatus.inProgress,
                      onCountChanged: (newCount) {
                        ref.read(inventoryRepositoryProvider).recordPhysicalCount(
                              auditId: audit.id,
                              productId: item.productId,
                              physicalCount: newCount,
                            );
                        final updatedItems = audit.items.map((it) {
                          if (it.productId == item.productId) {
                            return it.copyWith(physicalCount: newCount);
                          }
                          return it;
                        }).toList();
                        ref.read(activeCycleCountProvider.notifier).state =
                            audit.copyWith(items: updatedItems);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _statItem({
    required String label,
    required String value,
    required IconData icon,
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? const Color(0xFFD4AF37)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AuditItemRow extends StatelessWidget {
  final CycleCountItemEntity item;
  final String? abcClass;
  final bool isReadOnly;
  final ValueChanged<int> onCountChanged;

  const _AuditItemRow({
    required this.item,
    this.abcClass,
    required this.isReadOnly,
    required this.onCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final variance = item.varianceQty;
    final varianceColor = variance == 0
        ? Colors.grey
        : (variance > 0 ? Colors.green : Colors.red);

    Color abcBg;
    String abcLabel;
    switch (abcClass) {
      case 'A':
        abcBg = const Color(0xFFD4AF37);
        abcLabel = 'فئة A • جرد أسبوعي';
        break;
      case 'B':
        abcBg = Colors.blueAccent;
        abcLabel = 'فئة B • نصف شهري';
        break;
      default:
        abcBg = Colors.grey;
        abcLabel = 'فئة C • شهري';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1A16) : Colors.white,
        borderRadius: AppRadius.smAll,
        border: Border.all(
          color: item.hasDiscrepancy
              ? (variance < 0 ? Colors.red.withValues(alpha: 0.4) : Colors.green.withValues(alpha: 0.4))
              : (isDark ? const Color(0x38D4AF37) : const Color(0x28C59B27)),
        ),
      ),
      child: Row(
        children: [
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (abcClass != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        decoration: BoxDecoration(
                          color: abcBg.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: abcBg, width: 0.8),
                        ),
                        child: Text(
                          abcLabel,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFF3D278) : abcBg,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        item.productName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.category} • رصيد النظام: ${item.systemStock} ${item.unit}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Count Stepper & Input
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 22),
                onPressed: isReadOnly || item.physicalCount <= 0
                    ? null
                    : () => onCountChanged(item.physicalCount - 1),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade100,
                  borderRadius: AppRadius.xsAll,
                ),
                child: Text(
                  '${item.physicalCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 22),
                onPressed: isReadOnly
                    ? null
                    : () => onCountChanged(item.physicalCount + 1),
              ),
            ],
          ),

          const SizedBox(width: AppSpacing.md),

          // Variance Indicator
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: varianceColor.withValues(alpha: 0.15),
                    borderRadius: AppRadius.xsAll,
                  ),
                  child: Text(
                    variance == 0 ? 'مطابق' : (variance > 0 ? '+$variance' : '$variance'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: varianceColor,
                    ),
                  ),
                ),
                if (item.hasDiscrepancy)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: DzdPriceTag(
                      centimes: item.varianceCostCentimes,
                      style: TextStyle(fontSize: 11, color: varianceColor),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
