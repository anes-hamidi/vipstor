import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dedicated Money input field storing integer centimes according to UX/UI Design Rules Section 6.2.
class MoneyField extends StatefulWidget {
  final int initialCentimes;
  final ValueChanged<int> onChanged;
  final String labelText;
  final String? hintText;
  final String? helperText;
  final bool allowNegative;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? Function(int centimes)? validator;

  const MoneyField({
    super.key,
    required this.initialCentimes,
    required this.onChanged,
    required this.labelText,
    this.hintText = '0.00',
    this.helperText,
    this.allowNegative = false,
    this.autofocus = false,
    this.focusNode,
    this.validator,
  });

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  late TextEditingController _controller;
  late FocusNode _internalFocusNode;

  @override
  void initState() {
    super.initState();
    final dzd = (widget.initialCentimes / 100.0).toStringAsFixed(2);
    _controller = TextEditingController(text: widget.initialCentimes > 0 ? dzd : '');
    _internalFocusNode = widget.focusNode ?? FocusNode();
    _internalFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_internalFocusNode.hasFocus) {
      // Format to clean 2 decimal representation on blur
      final text = _controller.text.replaceAll(' ', '').trim();
      final parsed = double.tryParse(text) ?? 0.0;
      final centimes = (parsed * 100).round();
      if (centimes > 0) {
        _controller.text = (centimes / 100.0).toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _internalFocusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _internalFocusNode,
      autofocus: widget.autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        helperText: widget.helperText,
        prefixIcon: const Icon(Icons.payments_outlined, size: 20),
        suffixText: 'دج (DZD)',
        suffixStyle: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      onChanged: (val) {
        final clean = val.replaceAll(' ', '').trim();
        final doubleVal = double.tryParse(clean) ?? 0.0;
        final centimes = (doubleVal * 100).round();
        widget.onChanged(centimes);
      },
      validator: (val) {
        final clean = (val ?? '').replaceAll(' ', '').trim();
        final doubleVal = double.tryParse(clean) ?? 0.0;
        final centimes = (doubleVal * 100).round();
        if (widget.validator != null) {
          return widget.validator!(centimes);
        }
        return null;
      },
    );
  }
}
