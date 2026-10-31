import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import '../../common/widgets/headless_barcode_scanner_button.dart';
import '../../common/services/headless_barcode_scanner_service.dart';
import 'pin_confirm_dialog.dart';

/// Cycle-count workspace with live variance calculation, direct count entry,
/// auditable history, and PIN-protected reconciliation.
class CycleCountAuditSheet extends ConsumerStatefulWidget {
  const CycleCountAuditSheet({super.key});

  @override
  ConsumerState<CycleCountAuditSheet> createState() =>
      _CycleCountAuditSheetState();
}

class _CycleCountAuditSheetState extends ConsumerState<CycleCountAuditSheet> {
  final _searchController = TextEditingController();
  final _reconciliationNotesCtrl = TextEditingController();
  String _search = '';
  bool _onlyDiscrepancies = false;
  String _abcFilter = 'all';
  bool _isReconciling = false;

  @override
  void dispose() {
    HeadlessBarcodeScannerService.instance.stopScanning();
    _searchController.dispose();
    _reconciliationNotesCtrl.dispose();
    super.dispose();
  }

  String _getAbcClass(CycleCountItemEntity item) {
    final value = item.systemStock * item.unitCostCentimes;
    if (item.unitCostCentimes >= 500000 || value >= 5000000) return 'A';
    if (item.unitCostCentimes >= 100000 || value >= 1000000) return 'B';
    return 'C';
  }

  Future<void> _startNewAudit() async {
    final authUser = ref.read(authStateProvider);
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      final audit = await repo.startCycleCount(
        locationId: 'loc_main',
        locationName: 'المستودع الرئيسي',
        userId: authUser?.id ?? 'manager',
        userName: authUser?.name ?? 'مدير المخزون',
      );
      ref.read(activeCycleCountProvider.notifier).state = audit;
      ref.invalidate(auditHistoryProvider);
      setState(() {
        _search = '';
        _searchController.clear();
        _abcFilter = 'all';
        _onlyDiscrepancies = false;
      });
    } catch (e) {
      _showError('تعذر بدء الجرد: $e');
    }
  }

  void _openHistoryAudit(CycleCountAuditEntity audit) {
    ref.read(activeCycleCountProvider.notifier).state = audit;
    setState(() {
      _search = '';
      _searchController.clear();
      _abcFilter = 'all';
      _onlyDiscrepancies = false;
    });
  }

  Future<void> _recordCount(
    CycleCountAuditEntity audit,
    CycleCountItemEntity item,
    int count,
  ) async {
    if (count < 0) return;
    await ref.read(inventoryRepositoryProvider).recordPhysicalCount(
          auditId: audit.id,
          productId: item.productId,
          physicalCount: count,
        );

    final current = ref.read(activeCycleCountProvider) ?? audit;
    ref.read(activeCycleCountProvider.notifier).state = current.copyWith(
      items: current.items
          .map(
            (it) => it.productId == item.productId
                ? it.copyWith(
                    physicalCount: count,
                    countedAt: DateTime.now(),
                  )
                : it,
          )
          .toList(),
    );
  }

  Future<void> _promptCount(
    CycleCountAuditEntity audit,
    CycleCountItemEntity item,
  ) async {
    final controller = TextEditingController(text: '${item.physicalCount}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.productName,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'رصيد النظام: ${item.systemStock} ${item.unit}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'الكمية الفعلية المعدودة',
                suffixText: item.unit,
              ),
              onSubmitted: (value) => Navigator.of(ctx).pop(
                int.tryParse(value) ?? item.physicalCount,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              int.tryParse(controller.text) ?? item.physicalCount,
            ),
            child: const Text('حفظ الكمية'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result != null && mounted) {
      await _recordCount(audit, item, result);
    }
  }

  Future<void> _reconcileAudit(CycleCountAuditEntity audit) async {
    _reconciliationNotesCtrl.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.verified_user_outlined,
          color: Color(0xFFD4AF37),
        ),
        title: const Text('اعتماد تسوية الجرد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سيتم ترحيل فروقات ${audit.discrepantItemsCount} صنف إلى سجل المخزون السحابي بعد التحقق من رمز PIN.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'صافي أثر التكلفة: ${DzdFormatter.formatCentimes(audit.netCostVarianceCentimes)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: audit.netCostVarianceCentimes < 0
                    ? Colors.red
                    : const Color(0xFF27AE60),
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
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.lock_outline_rounded, size: 16),
            label: const Text('متابعة للتأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final pin = await PinConfirmDialog.show(
      context,
      message:
          'أدخل رمز PIN لتأكيد اعتماد الجرد وترحيل الفروقات إلى سجل المخزون',
      confirmLabel: 'اعتماد الجرد',
    );
    if (pin == null || pin.isEmpty || !mounted) return;

    final authUser = ref.read(authStateProvider);
    final repo = ref.read(inventoryRepositoryProvider);

    setState(() => _isReconciling = true);
    try {
      final reconciled = await repo.reconcileAudit(
        auditId: audit.id,
        userId: authUser?.id ?? 'manager',
        userName: authUser?.name ?? 'مدير المخزون',
        callerPin: pin,
        reconciliationNotes: _reconciliationNotesCtrl.text.trim(),
      );

      ref.read(activeCycleCountProvider.notifier).state = reconciled;
      ref.invalidate(liveProductsProvider);
      ref.invalidate(lowStockProductsProvider);
      ref.invalidate(auditHistoryProvider);
      ref.invalidate(stockAdjustmentHistoryProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت تسوية الجرد [${reconciled.auditNumber}] بنجاح.'),
          backgroundColor: context.appColors.success,
        ),
      );
    } catch (e) {
      _showError('فشل اعتماد الجرد: $e');
    } finally {
      if (mounted) setState(() => _isReconciling = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audit = ref.watch(activeCycleCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('الجرد الدوري والمطابقة'),
            if (audit != null)
              Text(
                '${audit.auditNumber} • ${audit.locationName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: [
          if (audit != null)
            IconButton(
              tooltip: 'سجل الجرد',
              icon: const Icon(Icons.history_rounded),
              onPressed: () {
                ref.read(activeCycleCountProvider.notifier).state = null;
                ref.invalidate(auditHistoryProvider);
              },
            ),
        ],
      ),
      body: audit == null
          ? _buildNoActiveAuditView()
          : _buildActiveAuditView(audit),
    );
  }

  Widget _buildNoActiveAuditView() {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(auditHistoryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(auditHistoryProvider);
        await ref.read(auditHistoryProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF27AE60).withValues(alpha: 0.10),
                  theme.colorScheme.surfaceContainerLowest,
                ],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              borderRadius: AppRadius.lgAll,
              border: Border.all(
                color: const Color(0xFF27AE60).withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: const Color(0xFF27AE60).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF27AE60).withValues(alpha: 0.30),
                    ),
                  ),
                  child: const Icon(
                    Icons.fact_check_outlined,
                    size: 32,
                    color: Color(0xFF27AE60),
                  ),
                ),
                AppSpacing.gapMd,
                Text(
                  'جرد المخزون الدوري',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                AppSpacing.gapXs,
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Text(
                    'ابدأ جلسة جرد دون إيقاف البيع. أدخل الكميات الفعلية، راجع الفروقات، ثم اعتمد التسوية برمز PIN لترحيلها إلى السجل السحابي.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                AppSpacing.gapLg,
                GoldButton.icon(
                  icon: Icons.play_arrow_rounded,
                  label: 'بدء دورة جرد جديدة',
                  onPressed: _startNewAudit,
                ),
              ],
            ),
          ),
          AppSpacing.gapLg,
          Row(
            children: [
              const Expanded(
                child: SectionHeader(title: 'سجل الجرد السابق', dense: true),
              ),
              IconButton(
                tooltip: 'تحديث السجل',
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: () => ref.invalidate(auditHistoryProvider),
              ),
            ],
          ),
          AppSpacing.gapSm,
          historyAsync.when(
            skipLoadingOnRefresh: true,
            loading: () => const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xl),
              child: AppLoadingView(message: 'جاري تحميل سجل الجرد...'),
            ),
            error: (error, _) => AppErrorView(
              message: '$error',
              onRetry: () => ref.invalidate(auditHistoryProvider),
            ),
            data: (audits) {
              if (audits.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 34,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.45),
                      ),
                      AppSpacing.gapSm,
                      Text(
                        'لا توجد جلسات جرد سابقة بعد.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final sorted = audits.toList()
                ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
              return Column(
                children:
                    sorted.map((audit) => _historyCard(audit, theme)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _historyCard(CycleCountAuditEntity audit, ThemeData theme) {
    final badge = switch (audit.status) {
      AuditStatus.inProgress => StatusBadgeType.processing,
      AuditStatus.reconciled => StatusBadgeType.completed,
      AuditStatus.cancelled => StatusBadgeType.cancelled,
    };
    final accuracyColor = audit.accuracyRate >= 98
        ? const Color(0xFF27AE60)
        : audit.accuracyRate >= 90
            ? const Color(0xFFF2994A)
            : Colors.red;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: LuxuryCard(
        onTap: () => _openHistoryAudit(audit),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accuracyColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.mdAll,
              ),
              child: Icon(
                audit.status == AuditStatus.reconciled
                    ? Icons.verified_rounded
                    : Icons.fact_check_outlined,
                color: accuracyColor,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          audit.auditNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      StatusBadge(
                        type: badge,
                        customLabel: audit.status.labelAr,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${audit.countedByName} • ${_dateTime(audit.startedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${audit.accuracyRate.toStringAsFixed(1)}% دقة • ${audit.discrepantItemsCount}/${audit.totalItemsCount} فروقات',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${audit.netVarianceQuantity >= 0 ? '+' : ''}${audit.netVarianceQuantity}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: audit.netVarianceQuantity == 0
                        ? theme.colorScheme.onSurfaceVariant
                        : audit.netVarianceQuantity > 0
                            ? const Color(0xFF27AE60)
                            : Colors.red,
                  ),
                ),
                Text(
                  audit.status == AuditStatus.inProgress ? 'استئناف' : 'عرض',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xFFB8860B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Icon(
              Icons.chevron_left_rounded,
              size: 20,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAuditView(CycleCountAuditEntity audit) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 680;
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

    final counted = audit.items.where((it) => it.countedAt != null).length;
    final progress = audit.items.isEmpty ? 0.0 : counted / audit.items.length;
    final isReadOnly = audit.status != AuditStatus.inProgress;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LuxuryCard(
                  goldAccent: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isReadOnly
                                  ? 'نتيجة الجرد ${audit.auditNumber}'
                                  : 'جلسة جرد نشطة — ${audit.auditNumber}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!isReadOnly)
                            GoldButton.icon(
                              icon: Icons.done_all_rounded,
                              label: _isReconciling
                                  ? 'جاري الاعتماد...'
                                  : 'تسوية واعتماد',
                              compact: true,
                              height: 36,
                              onPressed: _isReconciling
                                  ? null
                                  : () => _reconcileAudit(audit),
                            ),
                        ],
                      ),
                      AppSpacing.gapSm,
                      if (!isReadOnly) ...[
                        Row(
                          children: [
                            Text(
                              'تم جرد $counted من ${audit.items.length} صنف',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${(progress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB8860B),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: AppRadius.pillAll,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFFD4AF37),
                            ),
                          ),
                        ),
                        AppSpacing.gapSm,
                      ],
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _statItem(
                            label: 'إجمالي',
                            value: '${audit.totalItemsCount}',
                            icon: Icons.inventory_2_outlined,
                          ),
                          _statItem(
                            label: 'مطابق',
                            value: '${audit.matchedItemsCount}',
                            icon: Icons.check_circle_outline,
                            color: const Color(0xFF27AE60),
                          ),
                          _statItem(
                            label: 'فروقات',
                            value: '${audit.discrepantItemsCount}',
                            icon: Icons.warning_amber_rounded,
                            color: audit.discrepantItemsCount > 0
                                ? const Color(0xFFF2994A)
                                : const Color(0xFF27AE60),
                          ),
                          _statItem(
                            label: 'الدقة',
                            value: '${audit.accuracyRate.toStringAsFixed(1)}%',
                            icon: Icons.analytics_outlined,
                            color: const Color(0xFFD4AF37),
                          ),
                          _statItem(
                            label: 'أثر التكلفة',
                            value: DzdFormatter.formatCentimes(
                              audit.netCostVarianceCentimes,
                            ),
                            icon: Icons.attach_money_rounded,
                            color: audit.netCostVarianceCentimes < 0
                                ? Colors.red
                                : const Color(0xFF27AE60),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapSm,
                if (!isReadOnly)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'بحث عن منتج (اسم، فئة، باركود)...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HeadlessBarcodeScannerButton(
                              controller: _searchController,
                              onScanned: (code) =>
                                  setState(() => _search = code.trim()),
                              tooltip: 'مسح باركود المنتج بالجرد',
                            ),
                            if (_search.isNotEmpty)
                              IconButton(
                                tooltip: 'مسح البحث',
                                icon: const Icon(
                                  Icons.clear_rounded,
                                  size: 16,
                                ),
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(
                        label: 'الكل',
                        selected: _abcFilter == 'all',
                        onSelected: (_) => setState(() => _abcFilter = 'all'),
                      ),
                      _filterChip(
                        label: 'A • أسبوعي',
                        selected: _abcFilter == 'A',
                        color: const Color(0xFFD4AF37),
                        onSelected: (_) => setState(() => _abcFilter = 'A'),
                      ),
                      _filterChip(
                        label: 'B • نصف شهري',
                        selected: _abcFilter == 'B',
                        color: const Color(0xFF2F80ED),
                        onSelected: (_) => setState(() => _abcFilter = 'B'),
                      ),
                      _filterChip(
                        label: 'C • شهري',
                        selected: _abcFilter == 'C',
                        color: Colors.grey,
                        onSelected: (_) => setState(() => _abcFilter = 'C'),
                      ),
                      _filterChip(
                        label: 'الفروقات فقط (${audit.discrepantItemsCount})',
                        selected: _onlyDiscrepancies,
                        color: const Color(0xFFF2994A),
                        onSelected: (selected) =>
                            setState(() => _onlyDiscrepancies = selected),
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapSm,
              ],
            ),
          ),
        ),
        if (filteredItems.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('لا توجد منتجات مطابقة للفلتر')),
          )
        else
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xxl,
            ),
            sliver: SliverList.separated(
              itemCount: filteredItems.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (ctx, i) {
                final item = filteredItems[i];
                return _AuditItemRow(
                  item: item,
                  abcClass: _getAbcClass(item),
                  isReadOnly: isReadOnly,
                  compact: isCompact,
                  onCountChanged: (newCount) =>
                      _recordCount(audit, item, newCount),
                  onEditCount: () => _promptCount(audit, item),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    Color? color,
  }) {
    final effective = color ?? const Color(0xFFD4AF37);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: FilterChip(
        selected: selected,
        showCheckmark: false,
        label: Text(label),
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? const Color(0xFF1A1400) : null,
        ),
        avatar: color == null
            ? null
            : CircleAvatar(
                radius: 5,
                backgroundColor: effective,
              ),
        selectedColor: effective.withValues(alpha: 0.85),
        onSelected: onSelected,
      ),
    );
  }

  Widget _statItem({
    required String label,
    required String value,
    required IconData icon,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? const Color(0xFFD4AF37)),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _dateTime(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$minute';
  }
}

class _AuditItemRow extends StatelessWidget {
  final CycleCountItemEntity item;
  final String? abcClass;
  final bool isReadOnly;
  final bool compact;
  final ValueChanged<int> onCountChanged;
  final VoidCallback onEditCount;

  const _AuditItemRow({
    required this.item,
    this.abcClass,
    required this.isReadOnly,
    required this.compact,
    required this.onCountChanged,
    required this.onEditCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variance = item.varianceQty;
    final varianceColor = variance == 0
        ? theme.colorScheme.onSurfaceVariant
        : (variance > 0 ? const Color(0xFF27AE60) : Colors.red);

    final (abcColor, abcLabel) = switch (abcClass) {
      'A' => (const Color(0xFFD4AF37), 'A • أسبوعي'),
      'B' => (const Color(0xFF2F80ED), 'B • نصف شهري'),
      _ => (Colors.grey, 'C • شهري'),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: item.hasDiscrepancy
              ? varianceColor.withValues(alpha: 0.40)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _info(theme, abcColor, abcLabel),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    _stepper(theme),
                    const Spacer(),
                    _variance(theme, variance, varianceColor),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: _info(theme, abcColor, abcLabel)),
                _stepper(theme),
                const SizedBox(width: AppSpacing.md),
                _variance(theme, variance, varianceColor),
              ],
            ),
    );
  }

  Widget _info(ThemeData theme, Color abcColor, String abcLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsetsDirectional.only(end: 6),
              decoration: BoxDecoration(
                color: abcColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: abcColor, width: 0.8),
              ),
              child: Text(
                abcLabel,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                  color: abcColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                item.productName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${item.category} • رصيد النظام: ${item.systemStock} ${item.unit}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _stepper(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'إنقاص',
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 21),
          onPressed: isReadOnly || item.physicalCount <= 0
              ? null
              : () => onCountChanged(item.physicalCount - 1),
        ),
        InkWell(
          onTap: isReadOnly ? null : onEditCount,
          borderRadius: AppRadius.xsAll,
          child: Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isReadOnly
                  ? theme.colorScheme.surfaceContainerHigh
                  : const Color(0xFFD4AF37).withValues(alpha: 0.12),
              borderRadius: AppRadius.xsAll,
              border: Border.all(
                color: isReadOnly
                    ? theme.colorScheme.outlineVariant
                    : const Color(0xFFD4AF37).withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.physicalCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (!isReadOnly) ...[
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.edit_outlined,
                    size: 11,
                    color: Color(0xFFB8860B),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'زيادة',
          icon: const Icon(Icons.add_circle_outline_rounded, size: 21),
          onPressed:
              isReadOnly ? null : () => onCountChanged(item.physicalCount + 1),
        ),
      ],
    );
  }

  Widget _variance(ThemeData theme, int variance, Color varianceColor) {
    return SizedBox(
      width: compact ? null : 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: varianceColor.withValues(alpha: 0.13),
              borderRadius: AppRadius.xsAll,
            ),
            child: Text(
              variance == 0
                  ? 'مطابق'
                  : (variance > 0 ? '+$variance' : '$variance'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
                color: varianceColor,
              ),
            ),
          ),
          if (item.hasDiscrepancy)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                DzdFormatter.formatCentimes(item.varianceCostCentimes),
                style: TextStyle(fontSize: 10, color: varianceColor),
              ),
            ),
        ],
      ),
    );
  }
}
