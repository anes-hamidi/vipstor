import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Headless/Invisible Camera Barcode Scanner Service powered by Google ML Kit.
///
/// Features:
/// - Runs [CameraController.startImageStream] in the background WITHOUT displaying any camera preview or UI.
/// - Passes incoming camera frames directly to Google ML Kit [BarcodeScanner].
/// - Converts Android (YUV420) and iOS (BGRA8888) camera frames to [InputImage] with correct sensor rotation.
/// - Frame-dropping mechanism prevents pipeline lag and CPU throttling.
/// - Haptic feedback upon barcode recognition.
/// - Debounce prevents duplicate firing of the same barcode within a short window.
/// - Gracefully no-ops on desktop (Windows/Linux/macOS) and Web.
class HeadlessBarcodeScannerService {
  HeadlessBarcodeScannerService._();
  static final HeadlessBarcodeScannerService instance =
      HeadlessBarcodeScannerService._();

  CameraController? _cameraController;
  BarcodeScanner? _barcodeScanner;

  final ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isInitializingNotifier = ValueNotifier<bool>(false);

  bool _isProcessingFrame = false;
  bool _isContinuous = false;
  void Function(String barcode)? _onScanCallback;

  String? _lastScannedBarcode;
  DateTime? _lastScannedTime;
  static const Duration _debounceDuration = Duration(milliseconds: 1400);

  /// True if running on a mobile platform with camera hardware support.
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  bool get isScanning => isScanningNotifier.value;

  /// Starts the silent camera stream and begins scanning for barcodes.
  ///
  /// [onScan]: Callback invoked with the scanned barcode string.
  /// [continuous]: If false (default), the scanner automatically shuts down after reading one barcode.
  ///               If true, keeps scanning subsequent barcodes (ideal for Cashier POS continuous entry).
  Future<bool> startScanning({
    required void Function(String barcode) onScan,
    bool continuous = false,
  }) async {
    if (!isSupported) {
      debugPrint('[HeadlessBarcodeScanner] Mobile camera not supported on this platform.');
      return false;
    }

    if (isScanningNotifier.value) {
      // Update callback and mode if already running
      _onScanCallback = onScan;
      _isContinuous = continuous;
      return true;
    }

    _onScanCallback = onScan;
    _isContinuous = continuous;
    isInitializingNotifier.value = true;

    try {
      _barcodeScanner ??= BarcodeScanner(
        formats: [
          BarcodeFormat.all,
        ],
      );

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('[HeadlessBarcodeScanner] No cameras found on device.');
        isInitializingNotifier.value = false;
        return false;
      }

      // Prefer the standard rear-facing camera
      final rearCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Low/Medium resolution is ideal: fast FPS, minimal memory, high barcode detection rate
      _cameraController = CameraController(
        rearCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      // Start streaming frames directly to ML Kit
      await _cameraController!.startImageStream(_processCameraImage);

      isInitializingNotifier.value = false;
      isScanningNotifier.value = true;
      debugPrint('[HeadlessBarcodeScanner] Headless camera stream started successfully.');
      return true;
    } catch (e, stack) {
      debugPrint('[HeadlessBarcodeScanner] Failed to start headless camera: $e\n$stack');
      await stopScanning();
      isInitializingNotifier.value = false;
      return false;
    }
  }

  /// Stops the camera image stream and releases the camera hardware.
  Future<void> stopScanning() async {
    isScanningNotifier.value = false;
    isInitializingNotifier.value = false;
    _isProcessingFrame = false;
    _onScanCallback = null;

    try {
      if (_cameraController != null) {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        await _cameraController!.dispose();
        _cameraController = null;
      }
    } catch (e) {
      debugPrint('[HeadlessBarcodeScanner] Error disposing CameraController: $e');
    }
  }

  /// Toggle scanning on / off
  Future<void> toggleScanning({
    required void Function(String barcode) onScan,
    bool continuous = false,
  }) async {
    if (isScanningNotifier.value) {
      await stopScanning();
    } else {
      await startScanning(onScan: onScan, continuous: continuous);
    }
  }

  /// Internal frame processor
  Future<void> _processCameraImage(CameraImage image) async {
    if (!isScanningNotifier.value || _isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final barcodes = await _barcodeScanner?.processImage(inputImage);
      if (barcodes == null || barcodes.isEmpty || !isScanningNotifier.value) return;

      for (final barcode in barcodes) {
        final raw = barcode.displayValue ?? barcode.rawValue;
        if (raw == null || raw.trim().isEmpty) continue;

        final cleaned = raw.trim();

        // Debounce check for identical barcodes
        final now = DateTime.now();
        if (_lastScannedBarcode == cleaned && _lastScannedTime != null) {
          final diff = now.difference(_lastScannedTime!);
          if (diff < _debounceDuration) {
            continue;
          }
        }

        _lastScannedBarcode = cleaned;
        _lastScannedTime = now;

        // Subtle haptic confirmation
        HapticFeedback.mediumImpact();

        final callback = _onScanCallback;
        if (!_isContinuous) {
          // Single-shot mode: stop immediately
          await stopScanning();
        }

        if (callback != null) {
          callback(cleaned);
        }

        break;
      }
    } catch (e) {
      debugPrint('[HeadlessBarcodeScanner] Frame analysis error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Converts a [CameraImage] buffer into an [InputImage] for Google ML Kit.
  InputImage? _buildInputImage(CameraImage image) {
    final camera = _cameraController?.description;
    if (camera == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[_cameraController?.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // Android NV21 or multi-plane YUV
    if (image.planes.length != 1 && Platform.isAndroid) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // iOS BGRA or single plane
    final int bytesPerPixel =
        image.format.group == ImageFormatGroup.bgra8888 ? 4 : 1;

    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    return InputImage.fromBytes(
      bytes: allBytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow * bytesPerPixel,
      ),
    );
  }

  static final Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Disposes all camera and ML Kit resources.
  Future<void> dispose() async {
    await stopScanning();
    await _barcodeScanner?.close();
    _barcodeScanner = null;
    isScanningNotifier.dispose();
    isInitializingNotifier.dispose();
  }
}
