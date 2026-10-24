import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

import '../../../providers/inventory_providers.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';



class LowStockReplenishmentDashboard extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToReceiving;

  const LowStockReplenishmentDashboard({
    super.key,
    this.onNavigateToReceiving,
  });

  @override
  ConsumerState<LowStockReplenishmentDashboard> createState() =>
      _LowStockReplenishmentDashboardState();
}

class _LowStockReplenishmentDashboardState
    extends ConsumerState<LowStockReplenishmentDashboard> {
  String _search = '';
  final Set<String> _selectedProductIds = {};
  bool _isGeneratingPO = false;

  Future<void> _generateDraftPO(List<ProductEntity> lowStock) async {
    final suppliers = await ref.read(suppliersProvider.future);
    if (suppliers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء إضافة مورد أولاً قبل إنشاء أمر الشراء')),
        );
      }
      return;
    }

    String? selectedSupplierId = suppliers.first['id'] as String;
    String selectedSupplierName = suppliers.first['name'] as String;

    final confirmed = await showDialog<bool>(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('توليد مسودة أمر شراء ذكي'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اختر المورد المراد إصدار مسودة الشراء إليه:'),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: selectedSupplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: suppliers.map((s) {
                    return DropdownMenuItem<String>(
                      value: s['id'] as String,
                      child: Text(s['name'] as String),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        selectedSupplierId = val;
                        selectedSupplierName = suppliers
                            .firstWhere((s) => s['id'] == val)['name'] as String;
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'سيتم تضمين ${_selectedProductIds.isEmpty ? lowStock.length : _selectedProductIds.length} صنف بكميات تعويضية مقترحة بناءً على القدرة الاستيعابية ونقاط إعادة الطلب (ROP).',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              GoldButton(
                label: 'إنشاء المسودة',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    final authUser = ref.read(authStateProvider);
    final repo = ref.read(inventoryRepositoryProvider);

    setState(() => _isGeneratingPO = true);

    try {
      final po = await repo.generateDraftPOFromLowStock(
        supplierId: selectedSupplierId!,
        supplierName: selectedSupplierName,
        createdById: authUser?.id ?? 'manager',
        createdByName: authUser?.name ?? 'مدير المخزون',
        selectedProductIds: _selectedProductIds.isNotEmpty
            ? _selectedProductIds.toList()
            : null,
      );

      ref.invalidate(purchaseOrdersListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إنشاء مسودة أمر الشراء [${po.poNumber}] بنجاح!'),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء أمر الشراء: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPO = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final lowStockAsync = ref.watch(lowStockProductsProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0C0A) : const Color(0xFFF8F5EE),
      appBar: AppBar(
        title: const Text('المخزون المنخفض وإعادة التزويد الذكية'),
        backgroundColor: isDark ? const Color(0xFF141210) : const Color(0xFFFBF8F0),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(lowStockProductsProvider),
          ),
        ],
      ),
      body: lowStockAsync.when(
        data: (products) {
          final criticalCount = products.where((p) => p.isCritical || p.isOutOfStock).length;
          final lowCount = products.where((p) => p.isLowStock).length;
          final totalEstReplenishmentCost = products.fold<int>(
            0,
            (sum, p) => sum + (p.suggestedReplenishmentQty * p.costCentimes),
          );

          final filtered = products.where((p) {
            if (_search.isNotEmpty) {
              final q = _search.toLowerCase();
              return p.nameAr.toLowerCase().contains(q) ||
                  p.nameFr.toLowerCase().contains(q) ||
                  p.category.toLowerCase().contains(q) ||
                  p.barcodes.any((b) => b.contains(q));
            }
            return true;
          }).toList();

          return Column(
            children: [
              // KPI Cards Header
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                color: isDark ? const Color(0xFF191714) : Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: _kpiCard(
                        title: 'حرج / نفد',
                        value: '$criticalCount صنف',
                        icon: Icons.error_outline_rounded,
                        color: Colors.red,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _kpiCard(
                        title: 'أوشك على النفاد',
                        value: '$lowCount صنف',
                        icon: Icons.warning_amber_rounded,
                        color: Colors.orange,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _kpiCard(
                        title: 'تكلفة التزويد المقدرة',
                        value: DzdFormatter.formatCentimes(totalEstReplenishmentCost),
                        icon: Icons.monetization_on_outlined,
                        color: const Color(0xFFD4AF37),
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Action & Search Toolbar
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'بحث في الأصناف التي تحتاج تزويد...',
                          prefixIcon: Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _search = v.trim()),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    GoldButton.icon(
                      icon: Icons.post_add_rounded,
                      label: _isGeneratingPO
                          ? 'جاري الإنشاء...'
                          : 'توليد مسودة أمر شراء (${_selectedProductIds.isEmpty ? products.length : _selectedProductIds.length})',
                      onPressed: products.isEmpty || _isGeneratingPO
                          ? null
                          : () => _generateDraftPO(products),
                      compact: true,
                    ),
                  ],
                ),
              ),

              // Products List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.verified_rounded, size: 64, color: Colors.green),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'المخزون في حالة ممتازة!',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text('لا توجد منتجات دون نقطة إعادة الطلب حالياً.'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (ctx, i) {
                          final p = filtered[i];
                          final isSelected = _selectedProductIds.contains(p.id);

                          return Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E1A16) : Colors.white,
                              borderRadius: AppRadius.smAll,
                              border: Border.all(
                                color: p.isCritical
                                    ? Colors.red.withValues(alpha: 0.5)
                                    : (isDark ? const Color(0x38D4AF37) : const Color(0x28C59B27)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedProductIds.add(p.id);
                                      } else {
                                        _selectedProductIds.remove(p.id);
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.nameAr,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _healthBadge(p.healthStatus),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'رصيد حالي: ${p.availableQty} ${p.unit}  •  نقطة الطلب (ROP): ${p.reorderPoint}  •  أقصى سعة: ${p.maxCapacity}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'المقترح: +${p.suggestedReplenishmentQty} ${p.unit}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFFD4AF37),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    DzdPriceTag(
                                      centimes: p.suggestedReplenishmentQty * p.costCentimes,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant,
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
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('خطأ في تحميل المخزون المنخفض: $err')),
      ),
    );
  }

  Widget _healthBadge(StockHealthStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case StockHealthStatus.outOfStock:
      case StockHealthStatus.critical:
        bg = Colors.red.withValues(alpha: 0.15);
        fg = Colors.red;
        label = status.labelAr;
        break;
      case StockHealthStatus.lowStock:
        bg = Colors.orange.withValues(alpha: 0.15);
        fg = Colors.orange;
        label = status.labelAr;
        break;
      default:
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green;
        label = status.labelAr;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.xsAll,
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1A16) : const Color(0xFFFBF8F0),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
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
