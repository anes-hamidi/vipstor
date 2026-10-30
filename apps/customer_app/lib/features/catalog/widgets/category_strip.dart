import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Horizontal category selector.
///
/// Counts are intentionally left to the results bar: a row of chips should be
/// scannable, not a second data table.
class CategoryStrip extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const CategoryStrip({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          0,
        ),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final value = isAll ? null : categories[index - 1];
          final isSelected = value == selected;
          return _CategoryChip(
            label: isAll ? 'الكل' : value!,
            selected: isSelected,
            onTap: () => onSelected(isSelected ? null : value),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Align(
        alignment: Alignment.center,
        child: Material(
          color: selected
              ? scheme.secondary
              : (isDark
                  ? scheme.surfaceContainerLow
                  : scheme.surfaceContainerLowest),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.pillAll,
            side: BorderSide(
              color: selected ? Colors.transparent : scheme.outlineVariant,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.pillAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? scheme.onSecondary
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
