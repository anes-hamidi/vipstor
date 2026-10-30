import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../core/catalog_ranking.dart';

/// Search input plus the single entry point for sorting and availability.
class CatalogSearchRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;
  final int activeFilterCount;

  const CatalogSearchRow({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFilter,
    required this.activeFilterCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              return TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم المنتج أو الباركود',
                  isDense: true,
                  contentPadding:
                      const EdgeInsetsDirectional.symmetric(vertical: 15),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: onClear,
                        ),
                  fillColor: isDark
                      ? scheme.surfaceContainerLow
                      : scheme.surfaceContainerLowest,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FilterButton(
          activeCount: activeFilterCount,
          onTap: onFilter,
        ),
      ],
    );
  }
}

/// Result count and the currently active filters, kept to one quiet line.
class CatalogResultsBar extends StatelessWidget {
  final int count;
  final String? category;
  final CatalogSort sort;
  final bool onlyAvailable;

  const CatalogResultsBar({
    super.key,
    required this.count,
    required this.category,
    required this.sort,
    required this.onlyAvailable,
  });

  String get _summary {
    final parts = <String>[];
    if (category != null && category!.isNotEmpty) parts.add(category!);
    if (sort != CatalogSort.recommended) parts.add(sort.label);
    if (onlyAvailable) parts.add('المتوفر فقط');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Text(
          '$count منتج',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_summary.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _FilterButton({
    required this.activeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final active = activeCount > 0;
    final background = active
        ? scheme.secondaryContainer
        : (isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest);
    final foreground =
        active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    return Tooltip(
      message: 'ترتيب وتصفية',
      child: Material(
        color: background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(
            color: active ? Colors.transparent : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Badge.count(
                count: activeCount,
                isLabelVisible: active,
                backgroundColor: scheme.secondary,
                textColor: scheme.onSecondary,
                child: Icon(Icons.tune_rounded, size: 21, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
