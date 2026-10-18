import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import '../services/pdf_invoice_service.dart';

class PurchaseDetailsDialog extends StatelessWidget {
  final PurchaseEntity purchase;

  const PurchaseDetailsDialog({super.key, required this.purchase});

  static Future<void> show(BuildContext context, PurchaseEntity purchase) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PurchaseDetailsDialog(purchase: purchase),
    );
  }

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? AppSpacing.md : AppSpacing.xxl,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 850),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141210) : const Color(0xFFFCFAF5),
            borderRadius: AppRadius.xlAll,
            border: Border.all(
              color: isDark
                  ? const Color(0x38D4AF37)
                  : const Color(0xFFD4AF37).withValues(alpha: 0.35),
            ),
            boxShadow: const [AppShadows.goldGlowSm],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────
              _buildHeader(context, theme, cs, isDark),
              const Divider(height: 1),

              // ── Content ─────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Supplier & Relative User Metadata Row
                      _buildMetadataGrid(context, theme, cs, isDark, isCompact),
                      AppSpacing.gapLg,

                      // Items Breakdown Section
                      _buildItemsSection(context, theme, cs, isDark),
                      AppSpacing.gapLg,

                      // Financial Summary
                      _buildFinancialSummary(context, theme, cs, isDark),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),

              // ── Action Footer ───────────────────────────────────────
              _buildFooter(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, ThemeData theme, ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1915)
            : const Color(0xFFF6F2E7),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: const BoxDecoration(
              gradient: AppGradients.gold,
              shape: BoxShape.circle,
              boxShadow: [AppShadows.goldGlowSm],
            ),
            child: const Icon(Icons.receipt_long_rounded,
                size: 22, color: Color(0xFF1A1400)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'فاتورة استلام: ${purchase.invoiceNo}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    StatusBadge(
                      type: _statusToBadge(purchase.status),
                      customLabel: _statusLabel(purchase.status),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'تاريخ الفاتورة: ${_formatDate(purchase.invoiceDate)}${purchase.postedAt != null ? '  •  الترحيل: ${_formatDate(purchase.postedAt!)}' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataGrid(BuildContext context, ThemeData theme,
      ColorScheme cs, bool isDark, bool isCompact) {
    final supplierCard = _buildInfoCard(
      context: context,
      title: 'بيانات المورد',
      icon: Icons.storefront_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            purchase.supplierName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFFD4AF37),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'معرّف المورد: ${purchase.supplierId.substring(0, 8)}...',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
      isDark: isDark,
    );

    final userCard = _buildInfoCard(
      context: context,
      title: 'المستخدم المسؤول (مسجّل الاستلام)',
      icon: Icons.person_pin_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                purchase.createdByName ?? 'مستخدم غير محدد',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                  borderRadius: AppRadius.pillAll,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  _roleLabel(purchase.createdByRole),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB8860B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (purchase.createdByPhone != null &&
              purchase.createdByPhone!.isNotEmpty)
            Row(
              children: [
                Icon(Icons.phone_outlined,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  purchase.createdByPhone!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            )
          else
            Text(
              'معرّف المستخدم: ${purchase.createdById != null && purchase.createdById!.length > 8 ? purchase.createdById!.substring(0, 8) : (purchase.createdById ?? 'تلقائي')}',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
      isDark: isDark,
    );

    if (isCompact) {
      return Column(
        children: [
          supplierCard,
          AppSpacing.gapMd,
          userCard,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: supplierCard),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: userCard),
      ],
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget content,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1814) : const Color(0xFFF9F6EE),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: isDark ? const Color(0x2BD4AF37) : const Color(0x1FD4AF37),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFFD4AF37)),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF9A7B2C),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          content,
        ],
      ),
    );
  }

  Widget _buildItemsSection(
      BuildContext context, ThemeData theme, ColorScheme cs, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'السلع والمنتجات المستلمة (${purchase.items.length})',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'إجمالي الوحدات: ${purchase.totalQuantity}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        AppSpacing.gapSm,
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF191713) : Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: isDark
                  ? const Color(0x38D4AF37)
                  : const Color(0xFFE5DECE),
            ),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: purchase.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final it = purchase.items[i];
                final lineCost = it.lineCostCentimes;
                final margin = it.grossMarginPercent;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'الكمية: ${it.quantity} ${it.unit ?? 'قطعة'}  •  سعر الشراء: ${DzdFormatter.formatCentimes(it.unitCostCentimes)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Margin chip
                      if (it.sellingPriceCentimes > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: margin >= 0
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.red.withValues(alpha: 0.15),
                            borderRadius: AppRadius.smAll,
                          ),
                          child: Text(
                            'هامش ${margin.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: margin >= 0
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ),
                      const SizedBox(width: AppSpacing.md),
                      // Line total
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          DzdPriceTag(
                            centimes: lineCost,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (it.sellingPriceCentimes > 0)
                            Text(
                              'بيع: ${DzdFormatter.formatCentimes(it.sellingPriceCentimes)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialSummary(
      BuildContext context, ThemeData theme, ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF221F1A) : const Color(0xFFF3ECE0),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('إجمالي تكلفة المشتريات (المبلغ المدفوع):',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              DzdPriceTag.lg(
                centimes: purchase.totalAmountCentimes,
                gold: true,
              ),
            ],
          ),
          if (purchase.totalPotentialRevenueCentimes > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'القيمة المتوقعة عند البيع بالتجزئة:',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                DzdPriceTag(
                  centimes: purchase.totalPotentialRevenueCentimes,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الربح الإجمالي المتوقع (+${purchase.overallGrossMarginPercent.toStringAsFixed(1)}%):',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                DzdPriceTag(
                  centimes: purchase.estimatedGrossProfitCentimes,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('إغلاق النافذة'),
          ),
          GoldButton.icon(
            icon: Icons.print_rounded,
            label: 'طباعة وصل الاستلام',
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
          ),
        ],
      ),
    );
  }
}
