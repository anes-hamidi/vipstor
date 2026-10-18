import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:uuid/uuid.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

class ProofOfDeliveryDialog extends ConsumerStatefulWidget {
  final OrderEntity order;
  final VoidCallback onDelivered;

  const ProofOfDeliveryDialog({
    super.key,
    required this.order,
    required this.onDelivered,
  });

  @override
  ConsumerState<ProofOfDeliveryDialog> createState() => _ProofOfDeliveryDialogState();
}

class _ProofOfDeliveryDialogState extends ConsumerState<ProofOfDeliveryDialog> {
  int _currentStep = 0;
  late TextEditingController _cashController;
  int _collectedCentimes = 0;

  // Signature
  late SignatureController _sigController;

  // Photo
  Uint8List? _photoBytes;
  bool _isCompressing = false;

  // GPS Stamp
  Position? _stampedPosition;
  String? _stampedAddress;
  bool _isFetchingGps = false;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _collectedCentimes = widget.order.totalAmountCentimes;
    _cashController = TextEditingController(
      text: (widget.order.totalAmountCentimes / 100.0).toStringAsFixed(0),
    );
    _sigController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _captureGpsStamp();
  }

  @override
  void dispose() {
    _cashController.dispose();
    _sigController.dispose();
    super.dispose();
  }

  Future<void> _captureGpsStamp() async {
    setState(() => _isFetchingGps = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );
      _stampedPosition = pos;

      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _stampedAddress = '${p.street ?? ""}, ${p.locality ?? ""}, ${p.administrativeArea ?? ""}';
        }
      } catch (_) {}
    } catch (_) {} finally {
      if (mounted) setState(() => _isFetchingGps = false);
    }
  }

   Future<void> _pickDeliveryPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      
      // Let ImagePicker compress directly using native OS pipeline (cross-platform safe)
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 70, // Compresses image directly without crashing
      );

      if (picked == null) return;

      setState(() => _isCompressing = true);

      Uint8List bytes = await picked.readAsBytes();

      // Graceful fallback for flutter_image_compress
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minHeight: 800,
          minWidth: 800,
          quality: 70,
        );
        if (compressed.isNotEmpty) {
          bytes = compressed;
        }
      } catch (e) {
        debugPrint('Image compression skipped/fallback: $e');
      }

      if (mounted) {
        setState(() {
          _photoBytes = bytes;
          _isCompressing = false;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        setState(() => _isCompressing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر التقاط أو اختيار الصورة: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _finalizeDelivery() async {
    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(authStateProvider);
      if (user == null) throw Exception('غير مسجل');

      final orderRepo = ref.read(orderRepositoryProvider);
      final clientId = const Uuid().v4();

      // Export signature if drawn
      String? sigBase64;
      if (_sigController.isNotEmpty) {
        final sigBytes = await _sigController.toPngBytes();
        if (sigBytes != null) {
          sigBase64 = base64Encode(sigBytes);
        }
      }

      String? photoBase64;
      if (_photoBytes != null) {
        photoBase64 = base64Encode(_photoBytes!);
      }

      await orderRepo.completeDeliveryWithProof(
        driverId: user.id,
        orderId: widget.order.id,
        collectedCashCentimes: _collectedCentimes,
        signatureBase64: sigBase64,
        photoBase64: photoBase64,
        deliveryLat: _stampedPosition?.latitude,
        deliveryLng: _stampedPosition?.longitude,
        notes: _stampedAddress != null ? 'تم التسليم عند: $_stampedAddress' : null,
        clientId: clientId,
      );

      widget.onDelivered();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم تأكيد التسليم، حفظ إثبات التوصيل، وترحيل المبلغ لعهدتك بنجاح!'),
            backgroundColor: context.appColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل التسليم: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_rounded, color: Colors.green),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'إثبات وتسليم الطلب #${widget.order.orderNumber ?? widget.order.id.substring(0, 8)}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),

              // Stepper tabs indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStepHeader(0, '1. التحصيل النقد', Icons.payments_outlined),
                  _buildStepHeader(1, '2. توقيع الزبون', Icons.draw_outlined),
                  _buildStepHeader(2, '3. صورة وموقع', Icons.camera_alt_outlined),
                ],
              ),
              const Divider(),

              // Step Body
              Expanded(
                child: SingleChildScrollView(
                  child: _buildCurrentStepBody(theme),
                ),
              ),

              const Divider(),
              // Navigation Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _currentStep -= 1),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('السابق'),
                    )
                  else
                    const SizedBox.shrink(),
                  if (_currentStep < 2)
                    FilledButton.icon(
                      onPressed: () => setState(() => _currentStep += 1),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('التالي'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _isSubmitting ? null : _finalizeDelivery,
                      icon: _isSubmitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                          : const Icon(Icons.check_circle),
                      label: Text(_isSubmitting ? 'جاري التأكيد...' : 'تأكيد التسليم النهائي'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepHeader(int stepIndex, String title, IconData icon) {
    final isSelected = _currentStep == stepIndex;
    final isPassed = _currentStep > stepIndex;

    return InkWell(
      onTap: () => setState(() => _currentStep = stepIndex),
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              isPassed ? Icons.check_circle : icon,
              size: 16,
              color: isSelected ? Colors.blue : (isPassed ? Colors.green : Colors.grey),
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue : (isPassed ? Colors.green : Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStepBody(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildCashStep(theme);
      case 1:
        return _buildSignatureStep(theme);
      case 2:
        return _buildPhotoAndGpsStep(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCashStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: AppRadius.mdAll,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('المبلغ المطلوب للطلب:'),
                  DzdPriceTag(centimes: widget.order.totalAmountCentimes, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('الزبون: ${widget.order.customerName ?? widget.order.customerSnapshot?['customer_name'] ?? "زبون"}', style: theme.textTheme.bodySmall),
                  if (widget.order.customerPhone != null)
                    Text('الهاتف: ${widget.order.customerPhone}', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,
        TextField(
          controller: _cashController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'المبلغ المحصل نقدًا من الزبون (دج) *',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          onChanged: (val) {
            final clean = val.replaceAll(' ', '').trim();
            final parsed = double.tryParse(clean) ?? 0.0;
            setState(() {
              _collectedCentimes = (parsed * 100).round();
            });
          },
        ),
        AppSpacing.gapMd,
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            ActionChip(
              label: const Text('المبلغ كاملاً'),
              onPressed: () {
                _cashController.text = (widget.order.totalAmountCentimes / 100).toStringAsFixed(0);
                setState(() => _collectedCentimes = widget.order.totalAmountCentimes);
              },
              backgroundColor: isDark ? const Color(0xFF1A1400) : const Color(0xFFD4AF37)
            ),
            ActionChip(
              label: const Text('دفع لاحقاً (على الحساب)'),
              onPressed: () {
                _cashController.text = '0';
                setState(() => _collectedCentimes = 0);
              },
              backgroundColor: isDark ? const Color(0xFF1A1400) : const Color(0xFFD4AF37)
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignatureStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('توقيع الزبون على الشاشة لإثبات الاستلام (Proof of Delivery Signature):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        AppSpacing.gapSm,
        Container(
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400, width: 1.5),
            borderRadius: AppRadius.mdAll,
            color: Colors.white,
          ),
          clipBehavior: Clip.antiAlias,
          child: Signature(
            controller: _sigController,
            backgroundColor: Colors.white,
          ),
        ),
        AppSpacing.gapSm,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => _sigController.clear(),
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('مسح التوقيع وإعادة المحاولة'),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoAndGpsStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('صورة إثبات التسليم (Photo Proof):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        AppSpacing.gapSm,
        if (_photoBytes != null) ...[
          Container(
            height: 160,
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: Colors.green),
              image: DecorationImage(image: MemoryImage(_photoBytes!), fit: BoxFit.cover),
            ),
          ),
          AppSpacing.gapSm,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _photoBytes = null),
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                label: const Text('حذف الصورة', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ] else if (_isCompressing) ...[
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        ] else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDeliveryPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('التقاط بالكاميرا'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDeliveryPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('من المعرض'),
                ),
              ),
            ],
          ),
        ],
        AppSpacing.gapLg,
        const Text('توثيق الموقع الجغرافي (GPS Geotag):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        AppSpacing.gapSm,
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.blue.withAlpha(20),
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: Colors.blue.withAlpha(60)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isFetchingGps)
                const Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('جاري تحديد الإحداثيات الحالية...'),
                  ],
                )
              else if (_stampedPosition != null) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'إحداثيات GPS: (${_stampedPosition!.latitude.toStringAsFixed(5)}, ${_stampedPosition!.longitude.toStringAsFixed(5)})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                if (_stampedAddress != null) ...[
                  const SizedBox(height: 4),
                  Text('العنوان المقارب: $_stampedAddress', style: theme.textTheme.bodySmall),
                ],
              ] else
                Row(
                  children: [
                    const Icon(Icons.location_off, color: Colors.orange, size: 18),
                    const SizedBox(width: 6),
                    const Text('تعذر جلب إحداثيات GPS بدقة.', style: TextStyle(fontSize: 12)),
                    const Spacer(),
                    TextButton(onPressed: _captureGpsStamp, child: const Text('إعادة المحاولة')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
