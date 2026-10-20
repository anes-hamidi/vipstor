import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:uuid/uuid.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';
import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';

/// Fast Proof of Delivery Dialog:
/// Focuses strictly on Cash Collection and GPS Localization for quick, streamlined deliveries.
class ProofOfDeliveryDialog extends ConsumerStatefulWidget {
  final OrderEntity order;
  final VoidCallback onDelivered;

  const ProofOfDeliveryDialog({
    super.key,
    required this.order,
    required this.onDelivered,
  });

  @override
  ConsumerState<ProofOfDeliveryDialog> createState() =>
      _ProofOfDeliveryDialogState();
}

class _ProofOfDeliveryDialogState extends ConsumerState<ProofOfDeliveryDialog> {
  late TextEditingController _cashController;
  int _collectedCentimes = 0;

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
    _captureGpsStamp();
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  Future<void> _captureGpsStamp() async {
    setState(() => _isFetchingGps = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      _stampedPosition = pos;

      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          _stampedAddress =
              '${p.street ?? ""}, ${p.locality ?? ""}, ${p.administrativeArea ?? ""}';
        }
      } catch (_) {}
    } catch (_) {
      // Best-effort GPS capture: does not crash or block delivery
    } finally {
      if (mounted) setState(() => _isFetchingGps = false);
    }
  }

  Future<void> _finalizeDelivery() async {
    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(authStateProvider);
      if (user == null) throw Exception('غير مسجل الدخول');

      final orderRepo = ref.read(orderRepositoryProvider);
      final clientId = const Uuid().v4();

      await orderRepo.completeDeliveryWithProof(
        driverId: user.id,
        orderId: widget.order.id,
        collectedCashCentimes: _collectedCentimes,
        deliveryLat: _stampedPosition?.latitude,
        deliveryLng: _stampedPosition?.longitude,
        notes: _stampedAddress != null
            ? 'تم التسليم عند: $_stampedAddress'
            : null,
        clientId: clientId,
      );

      widget.onDelivered();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'تم تأكيد التسليم بنجاح وترحيل المبلغ المحصل لعهدتك!'),
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
    final isDark = theme.brightness == Brightness.dark;
    final orderNum =
        widget.order.orderNumber?.toString() ?? widget.order.id.substring(0, 8);

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: Colors.green,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'تسليم الطلب #$orderNum',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const Divider(height: 24),

              // 1. Customer & Order Summary Card
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1A16)
                      : const Color(0xFFF9F6F0),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'المبلغ المطلوب:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        DzdPriceTag.lg(
                          centimes: widget.order.totalAmountCentimes,
                          gold: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.order.customerName ??
                                widget.order.customerSnapshot?['customer_name'] ??
                                widget.order.customerSnapshot?['store_name'] ??
                                'زبون',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.order.customerPhone != null ||
                            widget.order.customerSnapshot?['phone'] != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.phone_outlined, size: 14),
                          const SizedBox(width: 2),
                          Text(
                            widget.order.customerPhone ??
                                widget.order.customerSnapshot!['phone'] as String,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // 2. Cash Collection Field & Fast Chips
              TextField(
                controller: _cashController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'المبلغ المحصل نقدًا (دج) *',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                ),
                onChanged: (val) {
                  final clean = val.replaceAll(' ', '').trim();
                  final parsed = double.tryParse(clean) ?? 0.0;
                  setState(() {
                    _collectedCentimes = (parsed * 100).round();
                  });
                },
              ),

              const SizedBox(height: 8),

              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('المبلغ كاملاً'),
                    onPressed: () {
                      _cashController.text =
                          (widget.order.totalAmountCentimes / 100)
                              .toStringAsFixed(0);
                      setState(() =>
                          _collectedCentimes = widget.order.totalAmountCentimes);
                    },
                    backgroundColor: isDark
                        ? const Color(0xFF2A2215)
                        : const Color(0xFFF3E8CE),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.history_toggle_off, size: 16),
                    label: const Text('دفع لاحقاً (على الحساب)'),
                    onPressed: () {
                      _cashController.text = '0';
                      setState(() => _collectedCentimes = 0);
                    },
                    backgroundColor: isDark
                        ? const Color(0xFF241B18)
                        : const Color(0xFFF5E4E0),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // 3. Location / GPS Geotag Stamp
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF141A24)
                      : const Color(0xFFEDF4FC),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    if (_isFetchingGps) ...[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'جاري تحديد الموقع الجغرافي تلقائياً...',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ] else if (_stampedPosition != null) ...[
                      const Icon(
                        Icons.my_location_rounded,
                        color: Colors.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الموقع: ${_stampedPosition!.latitude.toStringAsFixed(4)}, ${_stampedPosition!.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                            if (_stampedAddress != null)
                              Text(
                                _stampedAddress!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const Icon(
                        Icons.location_off_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'لم يتم التقاط الموقع بدقة',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                      TextButton(
                        onPressed: _captureGpsStamp,
                        child: const Text('تحديث', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: 12,
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _finalizeDelivery,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.done_all_rounded),
                    label: Text(
                      _isSubmitting
                          ? 'جاري التسليم...'
                          : 'تأكيد التسليم وترحيل العهدة',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
