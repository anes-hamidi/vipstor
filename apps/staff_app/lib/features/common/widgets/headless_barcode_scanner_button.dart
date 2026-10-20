import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../services/headless_barcode_scanner_service.dart';

/// An action button / suffix icon for TextFields that activates the headless
/// Google ML Kit barcode scanner on mobile devices without any camera preview.
class HeadlessBarcodeScannerButton extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onScanned;
  final bool continuous;
  final double iconSize;
  final String? tooltip;
  final bool showOnlyOnMobile;

  const HeadlessBarcodeScannerButton({
    super.key,
    this.controller,
    this.onScanned,
    this.continuous = false,
    this.iconSize = 20,
    this.tooltip,
    this.showOnlyOnMobile = true,
  });

  @override
  State<HeadlessBarcodeScannerButton> createState() =>
      _HeadlessBarcodeScannerButtonState();
}

class _HeadlessBarcodeScannerButtonState
    extends State<HeadlessBarcodeScannerButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final _scanner = HeadlessBarcodeScannerService.instance;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(String barcode) {
    if (widget.controller != null) {
      widget.controller!.text = barcode;
    }
    if (widget.onScanned != null) {
      widget.onScanned!(barcode);
    }
  }

  Future<void> _handleToggle() async {
    if (!_scanner.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المسح عبر الكاميرا متاح حصرياً على أجهزة الهواتف الذكية (Android / iOS).'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_scanner.isScanning) {
      await _scanner.stopScanning();
      _animController.stop();
      _animController.reset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إيقاف الماسح الصامت.'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      final started = await _scanner.startScanning(
        onScan: (barcode) {
          _onBarcodeDetected(barcode);
          if (!widget.continuous) {
            _animController.stop();
            _animController.reset();
          }
        },
        continuous: widget.continuous,
      );

      if (started && mounted) {
        _animController.repeat(reverse: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.qr_code_scanner_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.continuous
                        ? 'الماسح التلقائي نشط — وجّه الهاتف نحو الباركود بشكل متواصل.'
                        : 'الماسح نشط في الخلفية — وجّه الهاتف نحو الباركود.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF1F1A12),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showOnlyOnMobile && !_scanner.isSupported) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _scanner.isInitializingNotifier,
      builder: (context, isInitializing, _) {
        if (isInitializing) {
          return SizedBox(
            width: widget.iconSize + 16,
            height: widget.iconSize + 16,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            ),
          );
        }

        return ValueListenableBuilder<bool>(
          valueListenable: _scanner.isScanningNotifier,
          builder: (context, isScanning, _) {
            if (isScanning && !_animController.isAnimating) {
              _animController.repeat(reverse: true);
            } else if (!isScanning && _animController.isAnimating) {
              _animController.stop();
              _animController.reset();
            }

            return AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final colors = context.appColors;
                final pulseColor = isScanning
                    ? Color.lerp(
                        colors.goldLight,
                        Colors.greenAccent,
                        _animController.value,
                      )!
                    : null;

                return IconButton(
                  iconSize: widget.iconSize,
                  tooltip: widget.tooltip ??
                      (isScanning ? 'إيقاف مسح الباركود' : 'مسح الباركود (كاميرا خلفية)'),
                  icon: Icon(
                    isScanning
                        ? Icons.qr_code_scanner_rounded
                        : Icons.qr_code_scanner_outlined,
                    color: pulseColor ??
                        (isScanning
                            ? colors.goldLight
                            : Theme.of(context).colorScheme.primary),
                  ),
                  onPressed: _handleToggle,
                );
              },
            );
          },
        );
      },
    );
  }
}

/// A compact status indicator / toggle pill for screens that support continuous
/// barcode scanning mode (e.g. Counter POS Cashier).
class HeadlessScannerToggleChip extends StatelessWidget {
  final ValueChanged<String> onScanned;
  final String activeLabel;
  final String idleLabel;

  const HeadlessScannerToggleChip({
    super.key,
    required this.onScanned,
    this.activeLabel = 'الماسح التلقائي نشط',
    this.idleLabel = 'تشغيل ماسح الكاميرا',
  });

  @override
  Widget build(BuildContext context) {
    final scanner = HeadlessBarcodeScannerService.instance;
    if (!scanner.isSupported) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: scanner.isScanningNotifier,
      builder: (context, isScanning, _) {
        return FilterChip(
          selected: isScanning,
          showCheckmark: false,
          avatar: Icon(
            isScanning
                ? Icons.qr_code_scanner_rounded
                : Icons.qr_code_scanner_outlined,
            size: 16,
            color: isScanning ? Colors.white : context.appColors.goldLight,
          ),
          label: Text(
            isScanning ? activeLabel : idleLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isScanning ? FontWeight.bold : FontWeight.normal,
              color: isScanning ? Colors.white : null,
            ),
          ),
          selectedColor: Colors.green.shade700,
          onSelected: (_) {
            scanner.toggleScanning(
              onScan: onScanned,
              continuous: true,
            );
          },
        );
      },
    );
  }
}
