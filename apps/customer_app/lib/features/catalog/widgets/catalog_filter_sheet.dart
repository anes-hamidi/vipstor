import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../core/catalog_ranking.dart';

/// Result of the sort/filter sheet.
class CatalogFilterSelection {
  final CatalogSort sort;
  final bool onlyAvailable;

  const CatalogFilterSelection({
    required this.sort,
    required this.onlyAvailable,
  });
}

/// Opens the single sort and availability sheet used by the storefront.
Future<CatalogFilterSelection?> showCatalogFilterSheet(
  BuildContext context, {
  required CatalogSort sort,
  required bool onlyAvailable,
}) {
  return showModalBottomSheet<CatalogFilterSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _CatalogFilterSheet(
      initialSort: sort,
      initialOnlyAvailable: onlyAvailable,
    ),
  );
}

class _CatalogFilterSheet extends StatefulWidget {
  final CatalogSort initialSort;
  final bool initialOnlyAvailable;

  const _CatalogFilterSheet({
    required this.initialSort,
    required this.initialOnlyAvailable,
  });

  @override
  State<_CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<_CatalogFilterSheet> {
  late CatalogSort _sort = widget.initialSort;
  late bool _onlyAvailable = widget.initialOnlyAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ترتيب وتصفية',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'اختر طريقة العرض المناسبة لك',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'الترتيب',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: CatalogSort.values.map((value) {
                  final selected = _sort == value;
                  return ChoiceChip(
                    label: Text(value.label),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _sort = value),
                    selectedColor: scheme.secondaryContainer,
                    backgroundColor: scheme.surfaceContainerLow,
                    side: BorderSide(
                      color:
                          selected ? Colors.transparent : scheme.outlineVariant,
                    ),
                    shape: const StadiumBorder(),
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: AppSpacing.lg),
              Divider(color: scheme.outlineVariant, height: 1),
              SwitchListTile.adaptive(
                value: _onlyAvailable,
                onChanged: (value) => setState(() => _onlyAvailable = value),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'المتوفر فقط',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'إخفاء المنتجات التي نفدت كميتها',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                secondary: Icon(
                  Icons.inventory_2_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _sort = CatalogSort.recommended;
                        _onlyAvailable = false;
                      }),
                      child: const Text('إعادة تعيين'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.secondary,
                        foregroundColor: scheme.onSecondary,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(
                        CatalogFilterSelection(
                          sort: _sort,
                          onlyAvailable: _onlyAvailable,
                        ),
                      ),
                      child: const Text('تطبيق'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}
