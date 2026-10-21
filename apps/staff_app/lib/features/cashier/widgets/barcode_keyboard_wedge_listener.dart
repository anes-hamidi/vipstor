import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hardware Keyboard Wedge Isolation Widget.
///
/// Wraps the POS layout with an invisible raw keyboard listener using
/// [HardwareKeyboard.instance.addHandler]. It intercepts hardware barcode
/// scanners (USB/Bluetooth HID keyboard wedge mode) and prevents prefixes,
/// barcode digits, and suffixes from polluting focused text inputs
/// (e.g., search bar, quantity, discount, customer fields).
///
/// Mechanism:
/// 1. Inter-keystroke timing detection: Hardware scanners emit keystrokes at
///    super-human speed (< 45ms per character, typically 10-25ms).
/// 2. Prefix interception: Common barcode prefixes (STX, non-printable control
///    characters, etc.) are swallowed before reaching text editing clients.
/// 3. Suffix interception: Suffixes (Enter, Tab, \n, \r) are swallowed and used
///    to cleanly dispatch the accumulated barcode to [onBarcodeScanned].
/// 4. Text rollback: If a text field was focused when the scan started, the
///    first burst character is rolled back from the [EditableTextState]
///    immediately upon burst confirmation.
class BarcodeKeyboardWedgeListener extends StatefulWidget {
  final Widget child;
  final ValueChanged<String> onBarcodeScanned;
  final Duration maxInterKeyDelay;
  final int minBarcodeLength;
  final bool enabled;

  const BarcodeKeyboardWedgeListener({
    super.key,
    required this.child,
    required this.onBarcodeScanned,
    this.maxInterKeyDelay = const Duration(milliseconds: 45),
    this.minBarcodeLength = 3,
    this.enabled = true,
  });

  @override
  State<BarcodeKeyboardWedgeListener> createState() =>
      _BarcodeKeyboardWedgeListenerState();
}

class _BarcodeKeyboardWedgeListenerState
    extends State<BarcodeKeyboardWedgeListener> {
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeyPressTime;
  Timer? _resetTimer;
  bool _isScannerBurst = false;
  String _firstBurstChar = '';

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  @override
  void didUpdateWidget(covariant BarcodeKeyboardWedgeListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      } else {
        HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
        _resetState();
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _resetTimer?.cancel();
    super.dispose();
  }

  void _resetState() {
    _buffer.clear();
    _lastKeyPressTime = null;
    _isScannerBurst = false;
    _firstBurstChar = '';
    _resetTimer?.cancel();
  }

  void _scheduleResetTimer() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 150), () {
      _resetState();
    });
  }

  bool _isPrefix(KeyEvent event) {
    final char = event.character;
    if (char == null || char.isEmpty) return false;
    final codeUnit = char.codeUnitAt(0);
    // Control characters STX (0x02), SOH (0x01), etc. (excluding Enter, Tab, \r)
    return (codeUnit >= 1 && codeUnit <= 31 && codeUnit != 9 && codeUnit != 10 && codeUnit != 13);
  }

  bool _isSuffix(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      return true;
    }
    final char = event.character;
    return char == '\n' || char == '\r' || char == '\t' || char == '\x03';
  }

  bool _isInputFocused() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null || primaryFocus.context == null) return false;
    return primaryFocus.context!.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _rollbackPollutedChar(String char) {
    try {
      final primaryFocus = FocusManager.instance.primaryFocus;
      if (primaryFocus?.context != null) {
        final editable =
            primaryFocus!.context!.findAncestorStateOfType<EditableTextState>();
        if (editable != null) {
          final text = editable.textEditingValue.text;
          if (text.isNotEmpty && text.endsWith(char)) {
            final updatedText = text.substring(0, text.length - char.length);
            editable.userUpdateTextEditingValue(
              editable.textEditingValue.copyWith(
                text: updatedText,
                selection: TextSelection.collapsed(offset: updatedText.length),
              ),
              SelectionChangedCause.keyboard,
            );
          }
        }
      }
    } catch (_) {}
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted || !widget.enabled) return false;

    // During an active scanner burst, swallow all KeyUp and KeyRepeat events
    // so child widgets don't receive unmatched key-up artifacts.
    if (_isScannerBurst && (event is KeyUpEvent || event is KeyRepeatEvent)) {
      return true;
    }

    if (event is! KeyDownEvent) {
      return false;
    }

    // 1. Detect Scanner Prefixes (e.g., STX / SOH)
    if (_isPrefix(event)) {
      _isScannerBurst = true;
      _buffer.clear();
      _scheduleResetTimer();
      return true; // Swallow prefix
    }

    // 2. Detect Scanner Suffixes (Enter / Tab / \r / \n)
    if (_isSuffix(event)) {
      if (_buffer.length >= widget.minBarcodeLength) {
        final barcode = _cleanBarcode(_buffer.toString());
        _resetState();
        if (barcode.isNotEmpty) {
          widget.onBarcodeScanned(barcode);
        }
        return true; // Swallow suffix so it doesn't trigger form submit/tab jump
      }
      _resetState();
      return false; // Not a barcode burst; allow natural Enter/Tab key navigation
    }

    final char = event.character;
    if (char == null || char.isEmpty) {
      // Escape resets scanner buffer
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _resetState();
      }
      return false;
    }

    final now = DateTime.now();
    final diff = _lastKeyPressTime != null
        ? now.difference(_lastKeyPressTime!)
        : null;
    _lastKeyPressTime = now;

    // 3. Fast Burst Keystrokes (Hardware scanner wedge)
    if (diff != null && diff <= widget.maxInterKeyDelay) {
      if (!_isScannerBurst) {
        _isScannerBurst = true;
        // Strip the first character that might have leaked into the focused input
        if (_firstBurstChar.isNotEmpty) {
          _rollbackPollutedChar(_firstBurstChar);
        }
      }
      _buffer.write(char);
      _scheduleResetTimer();
      return true; // Swallow hardware barcode keystroke
    }

    // 4. Initial Keystroke or Slow Typing
    if (_isScannerBurst) {
      _isScannerBurst = false;
    }

    final hasInputFocus = _isInputFocused();

    if (!hasInputFocus) {
      // No text field has focus: capture everything into scanner buffer
      _buffer.clear();
      _buffer.write(char);
      _firstBurstChar = char;
      _scheduleResetTimer();
      return true; // Swallow so it doesn't trigger shortcut conflicts
    }

    // A text input currently has focus:
    // Let this first character enter naturally in case it's a human typing.
    // If a second character arrives within <= maxInterKeyDelay, the next key
    // will detect the burst and roll back [_firstBurstChar]!
    _buffer.clear();
    _buffer.write(char);
    _firstBurstChar = char;
    _scheduleResetTimer();
    return false;
  }

  String _cleanBarcode(String raw) {
    // Strip control characters, spaces, and leading/trailing whitespace
    return raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
