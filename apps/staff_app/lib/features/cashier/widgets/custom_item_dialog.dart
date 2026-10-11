import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import '../models/pos_models.dart';

class CustomItemDialog extends StatefulWidget {
  const CustomItemDialog({super.key});

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
    final priceVal = double.tryParse(_priceController.text.replaceAll(' ', '').trim()) ?? 0;
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_box_outlined),
          SizedBox(width: AppSpacing.sm),
          Text('إضافة منتج غير مسجل / يدوي'),
        ],
      ),
      content: ContentConstrainedBox.form(
        maxWidth: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم / وصف المنتج *',
                prefixIcon: Icon(Icons.edit_note),
              ),
            ),
            AppSpacing.gapMd,
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'سعر الوحدة (دج) *',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            AppSpacing.gapMd,
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الكمية',
                      prefixIcon: Icon(Icons.format_list_numbered),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<PosItemUnit>(
                    initialValue: _selectedUnit,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                    items: PosItemUnit.values.map((u) {
                      return DropdownMenuItem(value: u, child: Text(u.label));
                    }).toList(),
                    onChanged: (u) {
                      if (u != null) setState(() => _selectedUnit = u);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _handleSubmit,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('إضافة إلى الوصل'),
        ),
      ],
    );
  }
}
