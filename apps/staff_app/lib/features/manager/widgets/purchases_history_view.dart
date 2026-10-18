import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../services/pdf_invoice_service.dart';
import 'purchase_details_dialog.dart';

class PurchasesHistoryView extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToReceiving;

  const PurchasesHistoryView({super.key, this.onNavigateToReceiving});

  @override
  ConsumerState<PurchasesHistoryView> createState() =>
      _PurchasesHistoryViewState();
}

class _PurchasesHistoryViewState extends ConsumerState<PurchasesHistoryView> {
  String _searchQuery = '';
  PurchaseStatus? _filterStatus;
  bool _sortNewest = true;

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $h:$min';
  }

  String _roleLabel(String? role) {
    switch (role?.toLowerCase()) {
      case 'manager':
        return 'مدير المخزن';
      case 'moderator':
        return 'المشرف العام';
      case 'cashier':
        return 'أمين الصندوق';
      case 'driver':
        return 'سائق التوصيل';
      default:
        return 'موظف';
    }
  }

  StatusBadgeType _statusToBadge(PurchaseStatus status) {
    switch (status) {
      case PurchaseStatus.posted:
        return StatusBadgeType.posted;
      case PurchaseStatus.draft:
        return StatusBadgeType.draft;
      case PurchaseStatus.cancelled:
        return StatusBadgeType.cancelled;
    }
  }

  String _statusLabel(PurchaseStatus status) {
    switch (status) {
      case PurchaseStatus.posted:
        return 'مرحّلة للمخزون';
      case PurchaseStatus.draft:
        return 'مسودة';
      case PurchaseStatus.cancelled:
        return 'ملغاة';
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(purchasesListProvider);
    final staffAsync = ref.watch(staffMembersProvider);
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(purchasesListProvider);
        ref.invalidate(suppliersProvider);
      },
      child: purchasesAsync.when(
        data: (purchases) {
          // Resolve any missing user names via staff members cache
          final staffMap = <String, Map<String, dynamic>>{};
          staffAsync.whenData((members) {
            for (final m in members) {
              staffMap[m['id'] as String] = m;
            }
          });

          final enhancedPurchases = purchases.map((p) {
            if (p.createdByName == null && p.createdById != null) {
              final staff = staffMap[p.createdById];
              if (staff != null) {
                return PurchaseEntity(
                  id: p.id,
                  supplierId: p.supplierId,
                  supplierName: p.supplierName,
                  invoiceNo: p.invoiceNo,
                  invoiceDate: p.invoiceDate,
                  status: p.status,
                  totalAmountCentimes: p.totalAmountCentimes,
                  items: p.items,
                  postedAt: p.postedAt,
                  createdById: p.createdById,
                  createdByName: staff['name'] as String?,
                  createdByPhone: staff['phone'] as String?,
                  createdByRole: staff['role'] as String?,
                  createdAt: p.createdAt,
                );
              }
            }
            return p;
          }).toList();

          return _buildContent(enhancedPurchases, theme, isCompact);
        },
        loading: () => const AppLoadingView(message: 'جاري تحميل سجل المشتريات...'),
        error: (err, _) => AppErrorView(
          message: 'تعذر تحميل سجل المشتريات: $err',
          onRetry: () => ref.invalidate(purchasesListProvider),
        ),
      ),
    );
  }

  Widget _buildContent(
      List<PurchaseEntity> purchases, ThemeData theme, bool isCompact) {
    // KPI calculations over all purchases
    final totalSpend =
        purchases.fold<int>(0, (sum, p) => sum + p.totalAmountCentimes);
    final totalInvoices = purchases.length;
    final postedCount = purchases.where((p) => p.isPosted).length;
    final uniqueSuppliers = purchases.map((p) => p.supplierId).toSet().length;

    // Filter by search query and status
    var filtered = purchases.where((p) {
      if (_filterStatus != null && p.status != _filterStatus) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final matchInvoice = p.invoiceNo.toLowerCase().contains(q);
        final matchSupplier = p.supplierName.toLowerCase().contains(q);
        final matchUser = (p.createdByName ?? '').toLowerCase().contains(q);
        final matchPhone = (p.createdByPhone ?? '').contains(q);
        return matchInvoice || matchSupplier || matchUser || matchPhone;
      }
      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      final dateA = a.createdAt ?? a.invoiceDate;
      final dateB = b.createdAt ?? b.invoiceDate;
      return _sortNewest ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
    });

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // ── Top Title Row ──────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سجل فواتير واستلامات المشتريات',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'تتبع جميع الفواتير المستلمة، الموردين، والمستخدم المسؤول عن الترحيل للمخزون.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onNavigateToReceiving != null)
              GoldButton.icon(
                icon: Icons.add_circle_outline_rounded,
                label: 'استلام فاتورة جديدة',
                compact: true,
                onPressed: widget.onNavigateToReceiving,
              ),
          ],
        ),
        AppSpacing.gapLg,

        // ── KPI Summary Cards ──────────────────────────────────
        _buildKpis(totalSpend, totalInvoices, postedCount, uniqueSuppliers, isCompact),
        AppSpacing.gapLg,

        // ── Search & Filter Controls ───────────────────────────
        _buildFilterBar(theme, isCompact),
        AppSpacing.gapMd,

        // ── Invoices List ──────────────────────────────────────
        if (purchases.isEmpty)
          AppEmptyView(
            icon: Icons.receipt_long_outlined,
            title: 'لا توجد فواتير شراء سابقة',
            description: 'ابدأ باستلام وترحيل أول فاتورة مورد لإضافتها للمخزون.',
            actionLabel: 'استلام فاتورة الآن',
            onAction: widget.onNavigateToReceiving,
          )
        else if (filtered.isEmpty)
          AppEmptyView(
            icon: Icons.search_off_rounded,
            title: 'لا توجد نتائج مطابقة لبحثك',
            description: 'جرّب تغيير عبارة البحث أو إعادة تعيين عوامل التصفية.',
            actionLabel: 'إعادة تعيين الفلاتر',
            onAction: () {
              setState(() {
                _searchQuery = '';
                _filterStatus = null;
              });
            },
          )
        else
          ...filtered.map((purchase) => _buildPurchaseCard(purchase, theme, isCompact)),
      ],
    );
  }

  Widget _buildKpis(int totalSpend, int totalInvoices, int postedCount,
      int uniqueSuppliers, bool isCompact) {
    final kpiSpend = KpiCard(
      title: 'إجمالي المشتريات',
      value: DzdFormatter.formatCentimes(totalSpend),
      subtitle: '$postedCount فاتورة مرحّلة للمخزن',
      icon: Icons.account_balance_wallet_rounded,
      accentColor: const Color(0xFFD4AF37),
    );

    final kpiCount = KpiCard(
      title: 'عدد الفواتير',
      value: '$totalInvoices',
      subtitle: '$uniqueSuppliers موردين مختلفين',
      icon: Icons.receipt_long_rounded,
    );

    final kpiPosted = KpiCard(
      title: 'مرحّلة للمخزون',
      value: '$postedCount',
      subtitle: '${totalInvoices - postedCount} قيد المراجعة/مسودة',
      icon: Icons.check_circle_rounded,
    );

    if (isCompact) {
      return Column(
        children: [
          kpiSpend,
          AppSpacing.gapSm,
          Row(
            children: [
              Expanded(child: kpiCount),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: kpiPosted),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 2, child: kpiSpend),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: kpiCount),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: kpiPosted),
      ],
    );
  }

  Widget _buildFilterBar(ThemeData theme, bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'بحث برقم الفاتورة، اسم المورد، أو اسم المستخدم المسؤول...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: _sortNewest ? 'الترتيب: الأحدث أولاً' : 'الترتيب: الأقدم أولاً',
              icon: Icon(
                _sortNewest ? Icons.south_rounded : Icons.north_rounded,
                color: const Color(0xFFD4AF37),
              ),
              onPressed: () => setState(() => _sortNewest = !_sortNewest),
            ),
            IconButton(
              tooltip: 'تحديث السجل',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(purchasesListProvider),
            ),
          ],
        ),
        AppSpacing.gapSm,
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _statusChip(null, 'الكل'),
              const SizedBox(width: AppSpacing.xs),
              _statusChip(PurchaseStatus.posted, 'مرحّلة للمخزون'),
              const SizedBox(width: AppSpacing.xs),
              _statusChip(PurchaseStatus.draft, 'مسودة'),
              const SizedBox(width: AppSpacing.xs),
              _statusChip(PurchaseStatus.cancelled, 'ملغاة'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusChip(PurchaseStatus? status, String label) {
    final isSelected = _filterStatus == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterStatus = status),
      selectedColor: const Color(0xFFD4AF37).withValues(alpha: 0.22),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? const Color(0xFFB8860B) : null,
      ),
      side: BorderSide(
        color: isSelected
            ? const Color(0xFFD4AF37)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  Widget _buildPurchaseCard(
      PurchaseEntity purchase, ThemeData theme, bool isCompact) {
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final dateDisplay = _formatDate(purchase.createdAt ?? purchase.invoiceDate);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: LuxuryCard(
        goldAccent: purchase.isPosted,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Row: Invoice number, Date, Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: const Icon(Icons.receipt_rounded,
                      size: 16, color: Color(0xFFB8860B)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        purchase.invoiceNo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateDisplay,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                StatusBadge(
                  type: _statusToBadge(purchase.status),
                  customLabel: _statusLabel(purchase.status),
                ),
              ],
            ),
            const Divider(height: AppSpacing.lg),

            // Middle: Supplier Info & Relative User
            isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _supplierRow(purchase, cs),
                      AppSpacing.gapSm,
                      _relativeUserRow(purchase, cs, isDark),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _supplierRow(purchase, cs)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _relativeUserRow(purchase, cs, isDark)),
                    ],
                  ),
            const SizedBox(height: AppSpacing.md),

            // Bottom Summary & Actions Row
            Row(
              children: [
                // Item count & margin
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${purchase.items.length} أصناف (${purchase.totalQuantity} وحدة)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (purchase.overallGrossMarginPercent > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.14),
                            borderRadius: AppRadius.pillAll,
                          ),
                          child: Text(
                            'هامش +${purchase.overallGrossMarginPercent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Total price
                DzdPriceTag.lg(
                  centimes: purchase.totalAmountCentimes,
                  gold: true,
                ),
              ],
            ),
            AppSpacing.gapSm,

            // Buttons row
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final itemsPayload = purchase.items
                        .map((it) => {
                              'product_name': it.productName,
                              'qty': it.quantity,
                              'unit': it.unit,
                              'unit_cost': it.unitCostCentimes,
                            })
                        .toList();

                    PdfInvoiceService.printPurchaseReceivingVoucher(
                      invoiceNo: purchase.invoiceNo,
                      supplierName: purchase.supplierName,
                      items: itemsPayload,
                      totalCentimes: purchase.totalAmountCentimes,
                      receivedByName: purchase.createdByName ?? 'مسؤول المخزن',
                    );
                  },
                  icon: const Icon(Icons.print_outlined, size: 15),
                  label: const Text('طباعة الوصل', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 6),
                  ),
                ),
                GoldButton.icon(
                  icon: Icons.visibility_outlined,
                  label: 'تفاصيل الفاتورة',
                  compact: true,
                  onPressed: () =>
                      PurchaseDetailsDialog.show(context, purchase),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _supplierRow(PurchaseEntity purchase, ColorScheme cs) {
    return Row(
      children: [
        Icon(Icons.storefront_outlined, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            purchase.supplierName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _relativeUserRow(
      PurchaseEntity purchase, ColorScheme cs, bool isDark) {
    final userName = purchase.createdByName ?? 'مستخدم النظام';
    final role = _roleLabel(purchase.createdByRole);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF221F1A)
            : const Color(0xFFF4EFE6),
        borderRadius: AppRadius.smAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_pin_rounded,
              size: 14, color: Color(0xFFD4AF37)),
          const SizedBox(width: 4),
          Text(
            'المسؤول: ',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              userName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($role)',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF9A7B2C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
