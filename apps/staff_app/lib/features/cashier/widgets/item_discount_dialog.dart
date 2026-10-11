import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import '../models/pos_models.dart';

class ItemDiscountDialog extends StatefulWidget {
  final PosCartItem item;

  const ItemDiscountDialog({super.key, required this.item});

  @override
  State<ItemDiscountDialog> createState() => _ItemDiscountDialogState();
}

class _ItemDiscountDialogState extends State<ItemDiscountDialog> {
  late TextEditingController _percentController;
  late TextEditingController _fixedController;
  bool _isPercentageMode = true;

  @override
  void initState() {
    super.initState();
    _percentController = TextEditingController(
      text: widget.item.discountPercent > 0 ? widget.item.discountPercent.toStringAsFixed(1) : '',
    );
    _fixedController = TextEditingController(
      text: widget.item.manualDiscountCentimes > 0 ? (widget.item.manualDiscountCentimes / 100).toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _percentController.dispose();
    _fixedController.dispose();
    super.dispose();
  }

  void _apply() {
    if (_isPercentageMode) {
      final p = double.tryParse(_percentController.text.trim()) ?? 0.0;
      Navigator.pop(context, {'percent': p, 'fixed': 0});
    } else {
      final f = double.tryParse(_fixedController.text.trim()) ?? 0.0;
      Navigator.pop(context, {'percent': 0.0, 'fixed': (f * 100).round()});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.discount_outlined),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'تخفيض: ${widget.item.nameAr}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: true, label: Text('نسبة مئوية (%)')),
              ButtonSegment<bool>(value: false, label: Text('مبلغ ثابت (دج)')),
            ],
            selected: {_isPercentageMode},
            onSelectionChanged: (set) => setState(() => _isPercentageMode = set.first),
          ),
          AppSpacing.gapLg,
          if (_isPercentageMode)
            TextField(
              controller: _percentController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'نسبة التخفيض (%)',
                prefixIcon: Icon(Icons.percent),
                hintText: 'مثال: 5 أو 10',
              ),
            )
          else
            TextField(
              controller: _fixedController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'قيمة التخفيض المباشر للوحدة (دج)',
                prefixIcon: Icon(Icons.money_off),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('تطبيق التخفيض'),
        ),
      ],
    );
  }
}
