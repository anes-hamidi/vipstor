import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class PosCategory {
  final String id;
  final String labelAr;
  final IconData icon;

  const PosCategory({
    required this.id,
    required this.labelAr,
    required this.icon,
  });
}

class PosCategoryFilterBar extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  const PosCategoryFilterBar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  static const List<PosCategory> categories = [
    PosCategory(id: '', labelAr: 'جميع المنتجات', icon: Icons.apps_rounded),
    PosCategory(id: 'beverages', labelAr: 'مشروبات وعصائر', icon: Icons.local_drink_rounded),
    PosCategory(id: 'groceries', labelAr: 'مواد غذائية عامة', icon: Icons.kitchen_rounded),
    PosCategory(id: 'dairy', labelAr: 'ألبان وأجبان', icon: Icons.egg_alt_rounded),
    PosCategory(id: 'sweets', labelAr: 'حلويات وبسكويت', icon: Icons.cookie_rounded),
    PosCategory(id: 'cleaning', labelAr: 'منظفات ومواد تنظيف', icon: Icons.cleaning_services_rounded),
    PosCategory(id: 'hygiene', labelAr: 'عناية شخصية', icon: Icons.soap_rounded),
    PosCategory(id: 'spices', labelAr: 'توابل وبقوليات', icon: Icons.grain_rounded),
    PosCategory(id: 'other', labelAr: 'أخرى ومتنوعات', icon: Icons.category_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategory == cat.id;

          return FilterChip(
            selected: isSelected,
            avatar: Icon(
              cat.icon,
              size: 16,
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            ),
            label: Text(cat.labelAr),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
            backgroundColor: colorScheme.surfaceContainer,
            selectedColor: colorScheme.primary,
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.pillAll,
              side: BorderSide(
                color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            onSelected: (_) => onCategorySelected(cat.id),
          );
        },
      ),
    );
  }
}
