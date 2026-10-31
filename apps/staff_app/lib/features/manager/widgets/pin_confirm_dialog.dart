import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

/// Shared 4-digit PIN confirmation used by every sensitive inventory action.
///
/// The inventory RPCs (`rpc_adjust_stock`) re-verify this PIN server-side, so
/// the dialog only collects the secret; it never grants authority by itself.
class PinConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;

  const PinConfirmDialog({
    super.key,
    this.title = 'تأكيد هوية المسؤول',
    this.message = 'أدخل رمز PIN لتأكيد العملية',
    this.confirmLabel = 'تأكيد',
  });

  static Future<String?> show(
    BuildContext context, {
    String title = 'تأكيد هوية المسؤول',
    String message = 'أدخل رمز PIN لتأكيد العملية',
    String confirmLabel = 'تأكيد',
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends State<PinConfirmDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.length == 4) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded, color: Color(0xFFD4AF37)),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 12,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: 'PIN',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'إظهار' : 'إخفاء',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(
            'إلغاء',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, __) => FilledButton(
            onPressed: value.text.length == 4 ? _submit : null,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
