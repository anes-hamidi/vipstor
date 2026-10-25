import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';
import '../models/pos_models.dart';

/// A responsive, high-fidelity screen for adding custom, unlisted, or ad-hoc items to the POS ticket.
class CustomItemDialog extends StatefulWidget {
  const CustomItemDialog({super.key});

  /// Opens the custom item creation screen as a dedicated fullscreen screen route.
  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CustomItemDialog(),
      ),
    );
  }

  @override
  State<CustomItemDialog> createState() => _CustomItemDialogState();
}

class _CustomItemDialogState extends State<CustomItemDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  PosItemUnit _selectedUnit = PosItemUnit.piece;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final name = _nameController.text.trim();
    final priceVal =
        double.tryParse(_priceController.text.replaceAll(' ', '').trim()) ?? 0;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 1;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى كتابة وصف أو اسم المنتج'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (priceVal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى تحديد سعر بيع صحيح'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'name': name,
      'priceCentimes': (priceVal * 100).round(),
      'qty': qty > 0 ? qty : 1,
      'unit': _selectedUnit,
    });
  }

  void _adjustQty(int delta) {
    final current = int.tryParse(_qtyController.text.trim()) ?? 1;
    final updated = (current + delta).clamp(1, 9999);
    setState(() {
      _qtyController.text = updated.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = context.appColors;
    final role = context.roleTheme;
    final brand = role.roleBrandColor;

    final priceVal =
        double.tryParse(_priceController.text.replaceAll(' ', '').trim()) ?? 0;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 1;
    final lineTotalCentimes = ((priceVal * 100).round() * qty);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 2,
            backgroundColor: colorScheme.surfaceContainer,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'رجوع [Esc]',
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: role.badgeBackground,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: brand.withValues(alpha: 0.30)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.add_shopping_cart_rounded,
                        size: 20, color: role.badgeText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إضافة منتج يدوي / غير مسجل',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    Text(
                      'إدراج صنف أو خدمة استثنائية بالوصل مع تحديد السعر والكمية',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'اسم / وصف المنتج أو الخدمة *',
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                        border:
                            const OutlineInputBorder(borderRadius: AppRadius.mdAll),
                      ),
                    ),
                    AppSpacing.gapLg,
                    TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'سعر الوحدة (دج) *',
                        suffixText: 'دج',
                        prefixIcon: const Icon(Icons.payments_outlined, size: 28),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                        border:
                            const OutlineInputBorder(borderRadius: AppRadius.mdAll),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    AppSpacing.gapMd,
                    // Fast Price presets
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [100, 200, 500, 1000, 2000, 5000].map((val) {
                        return ActionChip(
                          label: Text('$val دج'),
                          onPressed: () {
                            setState(() {
                              _priceController.text = val.toString();
                            });
                          },
                        );
                      }).toList(),
                    ),
                    AppSpacing.gapLg,
                    Row(
                      children: [
                        // Quantity with Stepper controls
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.xs),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: AppRadius.mdAll,
                              border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.remove, size: 16),
                                  onPressed: () => _adjustQty(-1),
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(40, 40),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _qtyController,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.add, size: 16),
                                  onPressed: () => _adjustQty(1),
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(40, 40),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        // Unit Selector
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<PosItemUnit>(
                            isExpanded: true,
                            initialValue: _selectedUnit,
                            decoration: InputDecoration(
                              labelText: 'الوحدة',
                              filled: true,
                              fillColor: colorScheme.surfaceContainerLow,
                              border: const OutlineInputBorder(
                                  borderRadius: AppRadius.mdAll),
                            ),
                            items: PosItemUnit.values.map((u) {
                              return DropdownMenuItem(
                                  value: u,
                                  child: Text(u.label,
                                      overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (u) {
                              if (u != null) setState(() => _selectedUnit = u);
                            },
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.gapXl,
                    // Line Total Preview Card
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: colors.successContainer.withValues(alpha: 0.3),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color: colors.success.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'المجموع الإجمالي للبند:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          DzdPriceTag(
                            centimes: lineTotalCentimes,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapXl,
                    GoldButton.icon(
                      onPressed: _handleSubmit,
                      icon: Icons.add_shopping_cart_rounded,
                      label: 'إضافة البند إلى وصل البيع [Enter]',
                    ),
                    AppSpacing.gapSm,
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء والعودة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
