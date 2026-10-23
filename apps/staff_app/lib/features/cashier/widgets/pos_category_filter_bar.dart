import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Dynamic category chip bar for the POS catalog.
///
/// [categories] is the list of raw category strings fetched from the DB
/// (empty string "" is treated as "الكل" / All and always appears first).
/// The caller owns the full list; this widget renders it as animated chips.
class PosCategoryFilterBar extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  /// Dynamic list derived from actual product categories.
  /// Pass an empty list while loading — only the "الكل" chip will show.
  final List<String> categories;

  const PosCategoryFilterBar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = context.windowClass == WindowClass.compact;
    final h = isCompact ? 48.0 : 38.0;

    // "الكل" is always first, then the sorted distinct categories from the DB.
    final items = <String>['', ...categories];

    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final cat = items[i];
          final label = cat.isEmpty ? 'الكل' : cat;
          final icon = _iconForCategory(cat);
          final sel = selectedCategory == cat;
          return _PosCategoryChip(
            label: label,
            icon: icon,
            selected: sel,
            isCompact: isCompact,
            onTap: () => onCategorySelected(cat),
          );
        },
      ),
    );
  }

  /// Returns a best-effort icon for common Arabic category names.
  /// Falls back to [Icons.category_rounded] for unknown categories.
  static IconData _iconForCategory(String cat) {
    if (cat.isEmpty) return Icons.apps_rounded;
    final lower = cat.toLowerCase();
    if (lower.contains('مشروب') ||
        lower.contains('عصير') ||
        lower.contains('ماء')) {
      return Icons.local_drink_rounded;
    }
    if (lower.contains('غذائ') ||
        lower.contains('معلب') ||
        lower.contains('بقال')) {
      return Icons.kitchen_rounded;
    }
    if (lower.contains('لبن') ||
        lower.contains('ألبان') ||
        lower.contains('بيض')) {
      return Icons.egg_alt_rounded;
    }
    if (lower.contains('حلو') ||
        lower.contains('بسكو') ||
        lower.contains('شوكولا')) {
      return Icons.cookie_rounded;
    }
    if (lower.contains('منظف') || lower.contains('تنظيف')) {
      return Icons.cleaning_services_rounded;
    }
    if (lower.contains('عناية') ||
        lower.contains('صحي') ||
        lower.contains('نظافة')) {
      return Icons.soap_rounded;
    }
    if (lower.contains('توابل') || lower.contains('بهار')) {
      return Icons.grain_rounded;
    }
    if (lower.contains('خضر') ||
        lower.contains('فاكه') ||
        lower.contains('فواكه')) {
      return Icons.eco_rounded;
    }
    if (lower.contains('لحم') ||
        lower.contains('دجاج') ||
        lower.contains('سمك')) {
      return Icons.set_meal_rounded;
    }
    return Icons.category_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PosCategoryChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool isCompact;
  final VoidCallback onTap;

  const _PosCategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isCompact,
    required this.onTap,
  });

  @override
  State<_PosCategoryChip> createState() => _PosCategoryChipState();
}

class _PosCategoryChipState extends State<_PosCategoryChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final cs = Theme.of(context).colorScheme;
    final brand = context.roleTheme.roleBrandColor;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: widget.isCompact ? AppSpacing.md : AppSpacing.sm + 2,
            vertical: 0,
          ),
          decoration: BoxDecoration(
            gradient: sel
                ? LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [
                      Color.lerp(brand, Colors.white, 0.30)!,
                      brand,
                      Color.lerp(brand, Colors.black, 0.16)!,
                    ],
                  )
                : null,
            color: sel ? null : cs.surfaceContainerLow,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: sel ? brand : brand.withValues(alpha: 0.22),
              width: sel ? 1.5 : 1.0,
            ),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: brand.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: widget.isCompact ? 16 : 14,
                color: sel ? cs.onPrimary : brand.withValues(alpha: 0.70),
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.isCompact ? 13 : 12,
                  fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                  color: sel ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
