import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import 'cycle_count_audit_sheet.dart';
import 'stock_adjustment_dialog.dart';
import 'stock_transfer_dialog.dart';

enum _OpsSection { adjustments, transfers, audits }

/// Inventory operations hub: adjustment audit trail, internal transfer
/// workflow, and cycle-count history in one workspace.
class StockOperationsView extends ConsumerStatefulWidget {
  const StockOperationsView({super.key});

  @override
  ConsumerState<StockOperationsView> createState() =>
      _StockOperationsViewState();
}

class _StockOperationsViewState extends ConsumerState<StockOperationsView> {
  final _searchController = TextEditingController();
  _OpsSection _section = _OpsSection.adjustments;
  String _search = '';
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAdjustment() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const StockAdjustmentDialog(),
    );
    if (!mounted) return;
    ref.invalidate(stockAdjustmentHistoryProvider);
    ref.invalidate(liveProductsProvider);
    ref.invalidate(lowStockProductsProvider);
  }

  Future<void> _openTransfer() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const StockTransferDialog(),
    );
    if (!mounted) return;
    ref.invalidate(stockTransfersProvider);
  }

  Future<void> _openCycleCount() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      builder: (_) => const CycleCountAuditSheet(),
    );
    if (!mounted) return;
    ref.invalidate(auditHistoryProvider);
    ref.invalidate(activeCycleCountProvider);
    ref.invalidate(liveProductsProvider);
    ref.invalidate(lowStockProductsProvider);
    ref.invalidate(stockAdjustmentHistoryProvider);
  }

  Future<void> _updateTransfer(
    StockTransferEntity transfer,
    TransferStatus status,
  ) async {
    final user = ref.read(authStateProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).updateTransferStatus(
            transferId: transfer.id,
            status: status,
            userId: user.id,
            userName: user.name,
          );
      ref.invalidate(stockTransfersProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تحديث النقل [${transfer.transferNumber}] إلى: ${status.labelAr}',
          ),
          backgroundColor: context.appColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث حالة النقل: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showAdjustmentDetails(StockAdjustmentEntity adjustment) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFFB8860B)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(adjustment.referenceNumber)),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Chip(
                        label: Text(adjustment.reason.labelAr),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        avatar: const Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                        ),
                        label: Text(adjustment.adjustedByName),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        avatar: const Icon(Icons.event_outlined, size: 15),
                        label: Text(_dateTime(adjustment.createdAt)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...adjustment.items.map(
                    (item) => Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${item.oldStock} ← ${item.newStock} ${item.unit}'
                                  '${item.batchNumber != null ? ' • دفعة ${item.batchNumber}' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          _qtyDelta(item.qtyChange, theme),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            DzdFormatter.formatCentimes(
                              item.totalCostImpactCentimes,
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB8860B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (adjustment.notes != null && adjustment.notes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'ملاحظات: ${adjustment.notes}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _showTransferDetails(StockTransferEntity transfer) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Row(
            children: [
              const Icon(
                Icons.swap_horiz_rounded,
                color: Color(0xFFB8860B),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(transfer.transferNumber)),
              StatusBadge(
                type: _transferBadge(transfer.status),
                customLabel: transfer.status.labelAr,
                compact: true,
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${transfer.sourceLocationName} ← ${transfer.targetLocationName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${transfer.items.length} أصناف • ${transfer.totalQuantity} وحدة • ${DzdFormatter.formatCentimes(transfer.totalCostCentimes)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...transfer.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '${item.quantity} ${item.unit}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (transfer.notes != null && transfer.notes!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'ملاحظات: ${transfer.notes}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _showAuditDetails(CycleCountAuditEntity audit) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final discrepancies =
            audit.items.where((it) => it.hasDiscrepancy).toList();
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: Color(0xFFB8860B)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(audit.auditNumber)),
              StatusBadge(
                type: _auditBadge(audit.status),
                customLabel: audit.status.labelAr,
                compact: true,
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Chip(
                        label: Text(
                          '${audit.accuracyRate.toStringAsFixed(1)}% دقة',
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        label: Text('${audit.discrepantItemsCount} فروقات'),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        label: Text('${audit.totalItemsCount} صنف'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (discrepancies.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'كل الكميات مطابقة — لا توجد فروقات في هذا الجرد.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...discrepancies.map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'النظام: ${item.systemStock} • الفعلي: ${item.physicalCount}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            _qtyDelta(item.varianceQty, theme),
                          ],
                        ),
                      ),
                    ),
                  if (audit.reconciledByName != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'اعتمد الجرد: ${audit.reconciledByName} • ${audit.reconciledAt == null ? '' : _dateTime(audit.reconciledAt!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (audit.reconciliationNotes != null &&
                      audit.reconciliationNotes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'ملاحظات التسوية: ${audit.reconciliationNotes}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final adjustmentsAsync = ref.watch(stockAdjustmentHistoryProvider);
    final transfersAsync = ref.watch(stockTransfersProvider);
    final auditsAsync = ref.watch(auditHistoryProvider);

    final adjustments =
        adjustmentsAsync.value ?? const <StockAdjustmentEntity>[];
    final transfers = transfersAsync.value ?? const <StockTransferEntity>[];
    final audits = auditsAsync.value ?? const <CycleCountAuditEntity>[];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(stockAdjustmentHistoryProvider);
        ref.invalidate(stockTransfersProvider);
        ref.invalidate(auditHistoryProvider);
        await Future.wait([
          ref.read(stockAdjustmentHistoryProvider.future),
          ref.read(stockTransfersProvider.future),
          ref.read(auditHistoryProvider.future),
        ]);
      },
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _header(),
          AppSpacing.gapLg,
          _metrics(adjustments, transfers, audits),
          AppSpacing.gapLg,
          _sectionSelector(),
          AppSpacing.gapMd,
          if (_section != _OpsSection.audits) _searchField(),
          if (_section != _OpsSection.audits) AppSpacing.gapMd,
          switch (_section) {
            _OpsSection.adjustments => _adjustmentsSection(
                adjustmentsAsync,
                adjustments,
              ),
            _OpsSection.transfers => _transfersSection(
                transfersAsync,
                transfers,
              ),
            _OpsSection.audits => _auditsSection(auditsAsync, audits),
          },
        ],
      ),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    final isCompact = context.isCompact;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2F80ED).withValues(alpha: 0.10),
            theme.colorScheme.surfaceContainerLowest,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: const Color(0xFF2F80ED).withValues(alpha: 0.20),
        ),
      ),
      child: Flex(
        direction: isCompact ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment:
            isCompact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2F80ED), Color(0xFF1C5FBF)],
                  ),
                  borderRadius: AppRadius.mdAll,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2F80ED).withValues(alpha: 0.28),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.warehouse_rounded,
                  size: 24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'العمليات المخزنية',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'سجل التسويات، حركة النقل الداخلي، وجرد دوري موثّق برمز PIN.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isCompact) AppSpacing.gapMd else const Spacer(),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                onPressed: _openAdjustment,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('تسوية'),
              ),
              OutlinedButton.icon(
                onPressed: _openTransfer,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('نقل'),
              ),
              GoldButton.icon(
                icon: Icons.fact_check_outlined,
                label: 'جرد دوري',
                compact: true,
                onPressed: _openCycleCount,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metrics(
    List<StockAdjustmentEntity> adjustments,
    List<StockTransferEntity> transfers,
    List<CycleCountAuditEntity> audits,
  ) {
    final activeTransfers =
        transfers.where((t) => t.isPending || t.isInTransit).length;
    final adjustmentValue = adjustments.fold<int>(
      0,
      (sum, a) => sum + a.totalCostImpactCentimes,
    );
    final latestAudit = audits.isEmpty
        ? null
        : (audits.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)))
            .first;

    final metrics = [
      _OpsMetric(
        label: 'تسويات مسجلة',
        value: '${adjustments.length}',
        subtitle: adjustments.isEmpty
            ? null
            : 'قيمة ${DzdFormatter.formatCentimes(adjustmentValue)}',
        icon: Icons.tune_rounded,
        color: const Color(0xFF2F80ED),
      ),
      _OpsMetric(
        label: 'نقل داخلي نشط',
        value: '$activeTransfers',
        subtitle: '${transfers.length} حركة إجمالاً',
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFFF2994A),
      ),
      _OpsMetric(
        label: 'جرد دوري',
        value: '${audits.length}',
        subtitle:
            '${audits.where((a) => a.status == AuditStatus.inProgress).length} قيد التنفيذ',
        icon: Icons.fact_check_outlined,
        color: const Color(0xFF27AE60),
      ),
      _OpsMetric(
        label: 'أحدث دقة جرد',
        value: latestAudit == null
            ? '—'
            : '${latestAudit.accuracyRate.toStringAsFixed(1)}%',
        subtitle: latestAudit?.auditNumber,
        icon: Icons.verified_outlined,
        color: const Color(0xFFD4AF37),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        const spacing = AppSpacing.md;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              metrics.map((m) => SizedBox(width: width, child: m)).toList(),
        );
      },
    );
  }

  Widget _sectionSelector() {
    final theme = Theme.of(context);
    final entries = [
      (_OpsSection.adjustments, 'سجل التسويات', Icons.tune_rounded),
      (_OpsSection.transfers, 'حركات النقل', Icons.swap_horiz_rounded),
      (_OpsSection.audits, 'سجل الجرد', Icons.fact_check_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: entries.map((entry) {
          final selected = _section == entry.$1;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
            child: Material(
              color: selected
                  ? const Color(0xFFD4AF37)
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.pillAll,
              child: InkWell(
                onTap: () => setState(() => _section = entry.$1),
                borderRadius: AppRadius.pillAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 9,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entry.$3,
                        size: 16,
                        color: selected
                            ? const Color(0xFF1A1400)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        entry.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: selected
                              ? const Color(0xFF1A1400)
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        isDense: true,
        hintText: _section == _OpsSection.adjustments
            ? 'بحث برقم المرجع، الصنف، المسؤول...'
            : 'بحث برقم النقل، الموقع، الصنف...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح البحث',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
              ),
      ),
      onChanged: (value) => setState(() => _search = value),
    );
  }

  Widget _adjustmentsSection(
    AsyncValue<List<StockAdjustmentEntity>> async,
    List<StockAdjustmentEntity> adjustments,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxl),
        child: AppLoadingView(message: 'جاري تحميل سجل التسويات...'),
      );
    }
    if (async.hasError && !async.hasValue) {
      return AppErrorView(
        message: '${async.error}',
        onRetry: () => ref.invalidate(stockAdjustmentHistoryProvider),
      );
    }

    final query = _search.trim().toLowerCase();
    final filtered = adjustments.where((a) {
      if (query.isEmpty) return true;
      return a.referenceNumber.toLowerCase().contains(query) ||
          a.adjustedByName.toLowerCase().contains(query) ||
          a.reason.labelAr.contains(query) ||
          a.items.any((it) => it.productName.toLowerCase().contains(query));
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxl),
        child: AppEmptyView(
          icon: Icons.tune_outlined,
          title: 'لا توجد تسويات مخزنية',
          description:
              'سجّل أول تسوية للمخزون (تالف، منتهي الصلاحية، استهلاك داخلي...) لتظهر هنا في سجل موثّق.',
          actionLabel: 'تسوية مخزون',
          onAction: _openAdjustment,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filtered.map((adjustment) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: LuxuryCard(
            onTap: () => _showAdjustmentDetails(adjustment),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F80ED).withValues(alpha: 0.12),
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: Color(0xFF2F80ED),
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
                              adjustment.referenceNumber,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Chip(
                            label: Text(adjustment.reason.labelAr),
                            visualDensity: VisualDensity.compact,
                            labelStyle: const TextStyle(fontSize: 9.5),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${adjustment.totalItemsCount} أصناف • ${adjustment.totalQuantityChanged} وحدة • ${adjustment.adjustedByName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _dateTime(adjustment.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 9.5,
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
                      DzdFormatter.formatCentimes(
                        adjustment.totalCostImpactCentimes,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFFB8860B),
                      ),
                    ),
                    Text(
                      '${adjustment.totalQuantityChanged} وحدة',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurfaceVariant,
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
      }).toList(),
    );
  }

  Widget _transfersSection(
    AsyncValue<List<StockTransferEntity>> async,
    List<StockTransferEntity> transfers,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxl),
        child: AppLoadingView(message: 'جاري تحميل حركات النقل...'),
      );
    }
    if (async.hasError && !async.hasValue) {
      return AppErrorView(
        message: '${async.error}',
        onRetry: () => ref.invalidate(stockTransfersProvider),
      );
    }

    final query = _search.trim().toLowerCase();
    final filtered = transfers.where((t) {
      if (query.isEmpty) return true;
      return t.transferNumber.toLowerCase().contains(query) ||
          t.sourceLocationName.contains(query) ||
          t.targetLocationName.contains(query) ||
          t.requestedByName.contains(query) ||
          t.items.any((it) => it.productName.toLowerCase().contains(query));
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxl),
        child: AppEmptyView(
          icon: Icons.swap_horiz_rounded,
          title: 'لا توجد حركات نقل داخلي',
          description:
              'انقل المخزون بين المستودع المركزي وصالة العرض وسجّل حالة كل حركة حتى الاستلام.',
          actionLabel: 'نقل مخزون جديد',
          onAction: _openTransfer,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filtered.map((transfer) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: LuxuryCard(
            onTap: () => _showTransferDetails(transfer),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2994A).withValues(alpha: 0.12),
                        borderRadius: AppRadius.mdAll,
                      ),
                      child: Icon(
                        transfer.isCancelled
                            ? Icons.cancel_outlined
                            : Icons.swap_horiz_rounded,
                        size: 19,
                        color: const Color(0xFFF2994A),
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
                                  transfer.transferNumber,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              StatusBadge(
                                type: _transferBadge(transfer.status),
                                customLabel: transfer.status.labelAr,
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${transfer.sourceLocationName} ← ${transfer.targetLocationName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10.5,
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
                          '${transfer.totalQuantity} وحدة',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          DzdFormatter.formatCentimes(
                            transfer.totalCostCentimes,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 9.5,
                            color: const Color(0xFFB8860B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${transfer.requestedByName} • ${_dateTime(transfer.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 9.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (transfer.isPending)
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _updateTransfer(
                                  transfer,
                                  TransferStatus.inTransit,
                                ),
                        icon:
                            const Icon(Icons.local_shipping_outlined, size: 14),
                        label: const Text('بدء النقل'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                    if (transfer.isInTransit)
                      GoldButton.icon(
                        icon: Icons.task_alt_rounded,
                        label: 'تأكيد الاستلام',
                        compact: true,
                        height: 32,
                        onPressed: _busy
                            ? null
                            : () => _updateTransfer(
                                  transfer,
                                  TransferStatus.completed,
                                ),
                      ),
                    if (transfer.isPending || transfer.isInTransit) ...[
                      const SizedBox(width: AppSpacing.xs),
                      IconButton(
                        tooltip: 'إلغاء النقل',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: Colors.red,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _updateTransfer(
                                  transfer,
                                  TransferStatus.cancelled,
                                ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _auditsSection(
    AsyncValue<List<CycleCountAuditEntity>> async,
    List<CycleCountAuditEntity> audits,
  ) {
    if (async.isLoading && !async.hasValue) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxl),
        child: AppLoadingView(message: 'جاري تحميل سجل الجرد...'),
      );
    }
    if (async.hasError && !async.hasValue) {
      return AppErrorView(
        message: '${async.error}',
        onRetry: () => ref.invalidate(auditHistoryProvider),
      );
    }

    final sorted = audits.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxl),
        child: AppEmptyView(
          icon: Icons.fact_check_outlined,
          title: 'لا توجد جلسات جرد دوري',
          description:
              'ابدأ جرداً دورياً، أدخل الكميات الفعلية، ثم اعتمد التسوية برمز PIN لتحديث المخزون.',
          actionLabel: 'بدء جرد دوري',
          onAction: _openCycleCount,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sorted.map((audit) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: LuxuryCard(
            onTap: () => _showAuditDetails(audit),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF27AE60).withValues(alpha: 0.12),
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Icon(
                    audit.status == AuditStatus.reconciled
                        ? Icons.verified_rounded
                        : Icons.fact_check_outlined,
                    size: 20,
                    color: const Color(0xFF27AE60),
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
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          StatusBadge(
                            type: _auditBadge(audit.status),
                            customLabel: audit.status.labelAr,
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${audit.locationName} • ${audit.countedByName} • ${_dateTime(audit.startedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '${audit.accuracyRate.toStringAsFixed(1)}% دقة',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: audit.accuracyRate >= 98
                                  ? const Color(0xFF27AE60)
                                  : audit.accuracyRate >= 90
                                      ? const Color(0xFFF2994A)
                                      : Colors.red,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${audit.discrepantItemsCount}/${audit.totalItemsCount} فروقات',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
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
                      DzdFormatter.formatCentimes(
                        audit.netCostVarianceCentimes.abs(),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9.5,
                        color: theme.colorScheme.onSurfaceVariant,
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
      }).toList(),
    );
  }

  Widget _qtyDelta(int delta, ThemeData theme) {
    final positive = delta >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (positive ? const Color(0xFF27AE60) : Colors.red)
            .withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        '${positive ? '+' : ''}$delta',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: positive ? const Color(0xFF27AE60) : Colors.red,
        ),
      ),
    );
  }

  StatusBadgeType _transferBadge(TransferStatus status) {
    return switch (status) {
      TransferStatus.pending => StatusBadgeType.pending,
      TransferStatus.inTransit => StatusBadgeType.processing,
      TransferStatus.completed => StatusBadgeType.completed,
      TransferStatus.cancelled => StatusBadgeType.cancelled,
    };
  }

  StatusBadgeType _auditBadge(AuditStatus status) {
    return switch (status) {
      AuditStatus.inProgress => StatusBadgeType.processing,
      AuditStatus.reconciled => StatusBadgeType.completed,
      AuditStatus.cancelled => StatusBadgeType.cancelled,
    };
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

class _OpsMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _OpsMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
