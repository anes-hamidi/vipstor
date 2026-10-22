import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../providers/staff_providers.dart';
import '../../../router/staff_router.dart';
import 'driver_order_utils.dart';

/// Fast, safe proof-of-delivery flow.
///
/// Workflow improvements over the legacy dialog:
///  - Prefills the actual remaining amount (not the gross order total).
///  - Clearly previews cash collected, amount carried on the customer account
///    and overpayments before the driver commits.
///  - Requires an explicit confirmation when delivering on credit (0 DZD).
///  - Presents GPS capture as a best-effort stamp, never as a blocker.
///  - Is responsive: bottom sheet on phones, centered dialog on larger screens.
class ProofOfDeliveryDialog extends ConsumerStatefulWidget {
  final OrderEntity order;
  final VoidCallback onDelivered;
  final bool asSheet;

  const ProofOfDeliveryDialog({
    super.key,
    required this.order,
    required this.onDelivered,
    this.asSheet = false,
  });

  /// Opens as a bottom sheet on compact screens and as a dialog elsewhere.
  static Future<void> show(
    BuildContext context, {
    required OrderEntity order,
    required VoidCallback onDelivered,
  }) {
    final isCompact = MediaQuery.sizeOf(context).width < 640;

    if (isCompact) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ProofOfDeliveryDialog(
          order: order,
          onDelivered: onDelivered,
          asSheet: true,
        ),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (_) => ProofOfDeliveryDialog(
        order: order,
        onDelivered: onDelivered,
      ),
    );
  }

  @override
  ConsumerState<ProofOfDeliveryDialog> createState() =>
      _ProofOfDeliveryDialogState();
}

class _ProofOfDeliveryDialogState extends ConsumerState<ProofOfDeliveryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cashController;
  late final TextEditingController _notesController;

  int _collectedCentimes = 0;
  bool _deferredConfirmed = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  // GPS stamp
  Position? _stampedPosition;
  String? _stampedAddress;
  String? _gpsError;
  bool _isFetchingGps = false;

  int get _dueCentimes => widget.order.dueAmountCentimes;
  bool get _needsDeferredConfirmation =>
      _collectedCentimes == 0 && _dueCentimes > 0;
  bool get _canSubmit =>
      !_isSubmitting && (!_needsDeferredConfirmation || _deferredConfirmed);

  @override
  void initState() {
    super.initState();
    _collectedCentimes = _dueCentimes;
    _cashController = TextEditingController(
      text: _amountInputText(_dueCentimes),
    );
    _notesController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureGpsStamp();
    });
  }

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _amountInputText(int centimes) {
    final dinars = centimes / 100.0;
    return dinars == dinars.roundToDouble()
        ? dinars.toStringAsFixed(0)
        : dinars.toStringAsFixed(2);
  }

  Future<void> _captureGpsStamp() async {
    if (mounted) {
      setState(() {
        _isFetchingGps = true;
        _gpsError = null;
      });
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 7),
      );

      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts = <String>[
            if (place.street?.trim().isNotEmpty ?? false) place.street!.trim(),
            if (place.locality?.trim().isNotEmpty ?? false)
              place.locality!.trim(),
            if (place.administrativeArea?.trim().isNotEmpty ?? false)
              place.administrativeArea!.trim(),
          ];
          if (parts.isNotEmpty) address = parts.join('، ');
        }
      } catch (_) {
        // Geocoding is best-effort; coordinates are still a valid stamp.
      }

      if (!mounted) return;
      setState(() {
        _stampedPosition = position;
        _stampedAddress = address;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _gpsError = 'تعذر تحديد الموقع الحالي';
      });
    } finally {
      if (mounted) setState(() => _isFetchingGps = false);
    }
  }

  Future<void> _finalizeDelivery() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_needsDeferredConfirmation && !_deferredConfirmed) {
      setState(() {
        _errorMessage =
            'يجب تأكيد أن الزبون لم يدفع قبل تسجيل التسليم على الحساب.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final user = ref.read(authStateProvider);
      if (user == null) {
        throw Exception('الجلسة منتهية. يرجى تسجيل الدخول مجدداً.');
      }

      final notes = <String>[
        if (_notesController.text.trim().isNotEmpty)
          _notesController.text.trim(),
        if (_stampedAddress != null) 'تم التسليم عند: $_stampedAddress',
      ].join(' • ');

      await ref.read(orderRepositoryProvider).completeDeliveryWithProof(
            driverId: user.id,
            orderId: widget.order.id,
            collectedCashCentimes: _collectedCentimes,
            deliveryLat: _stampedPosition?.latitude,
            deliveryLng: _stampedPosition?.longitude,
            notes: notes.isEmpty ? null : notes,
            clientId: const Uuid().v4(),
          );

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      final colors = context.appColors;
      final amount = DzdFormatter.formatCentimes(
        _collectedCentimes,
        showDecimals: false,
      );

      widget.onDelivered();
      Navigator.of(context).pop();

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _collectedCentimes > 0
                  ? 'تم تأكيد التسليم. أُضيف $amount دج إلى عهدة الكاش.'
                  : 'تم تأكيد التسليم. سيُسجل المبلغ المتبقي على حساب الزبون.',
            ),
            backgroundColor: colors.success,
            behavior: SnackBarBehavior.floating,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.mdAll,
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
        _isSubmitting = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('host lookup') ||
        text.contains('network') ||
        text.contains('timeout')) {
      return 'تعذر الاتصال بالخادم. تحقق من الشبكة ثم أعد المحاولة.';
    }
    if (text.contains('already_delivered') ||
        text.contains('already delivered')) {
      return 'تم تسجيل هذا الطلب كمُسلَّم مسبقاً.';
    }
    if (text.contains('غير مسجل')) return 'الجلسة منتهية. سجّل الدخول مجدداً.';
    return 'تعذر تسجيل التسليم. حاول مرة أخرى.';
  }

  void _setAmount(int centimes) {
    setState(() {
      _collectedCentimes = centimes;
      _cashController.text = _amountInputText(centimes);
      _deferredConfirmed = false;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isDark = theme.brightness == Brightness.dark;

    final content = Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.92),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: widget.asSheet
            ? const BorderRadius.vertical(top: Radius.circular(24))
            : AppRadius.xxlAll,
        border: Border.all(
          color: colors.gold.withValues(alpha: widget.asSheet ? 0.35 : 0.20),
        ),
        boxShadow: AppShadows.dialogLuxury,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg,
          widget.asSheet ? AppSpacing.sm : AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.asSheet)
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsetsDirectional.only(
                      bottom: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colors.gold.withValues(alpha: 0.35),
                      borderRadius: AppRadius.pillAll,
                    ),
                  ),
                ),
              _buildHeader(context, theme, colors),
              const SizedBox(height: AppSpacing.md),
              _buildOrderSummary(context, theme, colors),
              const SizedBox(height: AppSpacing.md),
              _buildCashSection(context, theme, colors, isDark),
              const SizedBox(height: AppSpacing.md),
              _buildPaymentRecap(context, theme, colors),
              if (_needsDeferredConfirmation) ...[
                const SizedBox(height: AppSpacing.sm),
                _buildDeferredConfirmation(context, theme, colors),
              ],
              const SizedBox(height: AppSpacing.md),
              _buildGpsStamp(context, theme, colors),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesController,
                textInputAction: TextInputAction.done,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة التسليم (اختياري)',
                  hintText: 'مثال: تم التسليم لصاحب المحل مباشرة',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  alignLabelWithHint: true,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                _ErrorBanner(message: _errorMessage!),
              ],
              const SizedBox(height: AppSpacing.lg),
              _buildActions(context, theme, colors),
            ],
          ),
        ),
      ),
    );

    if (widget.asSheet) return content;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: content,
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
  ) {
    final orderNumber = orderShortNumber(widget.order);

    return Row(
      children: [
        Container(
          padding: const EdgeInsetsDirectional.all(9),
          decoration: BoxDecoration(
            color: colors.success.withValues(alpha: 0.12),
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: colors.success.withValues(alpha: 0.26)),
          ),
          child: Icon(
            Icons.local_shipping_rounded,
            color: colors.success,
            size: 21,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تأكيد تسليم الطلب #$orderNumber',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'راجع المبلغ والموقع قبل تأكيد التسليم',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'إغلاق',
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _buildOrderSummary(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
  ) {
    final order = widget.order;
    final customer = deliveryCustomerName(order);
    final phone = deliveryCustomerPhone(order);
    final address = deliveryAddressText(order);
    final paidBefore = order.paidAmountCentimes;

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 16, color: colors.gold),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  customer,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (phone != null)
                Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (address != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: colors.gold,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    address,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const GoldDivider(
            height: 1,
            margin: EdgeInsetsDirectional.symmetric(
              vertical: AppSpacing.xs,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _SummaryValue(
                  label: 'إجمالي الطلب',
                  value: DzdFormatter.formatCentimes(
                    order.totalAmountCentimes,
                    showDecimals: false,
                  ),
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (paidBefore > 0)
                Expanded(
                  child: _SummaryValue(
                    label: 'مدفوع مسبقاً',
                    value: DzdFormatter.formatCentimes(
                      paidBefore,
                      showDecimals: false,
                    ),
                    color: colors.success,
                    alignEnd: true,
                  ),
                ),
              Expanded(
                child: _SummaryValue(
                  label: 'المتبقي الآن',
                  value: DzdFormatter.formatCentimes(
                    order.dueAmountCentimes,
                    showDecimals: false,
                  ),
                  color: colors.gold,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCashSection(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    bool isDark,
  ) {
    final due = _dueCentimes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.payments_outlined, size: 16, color: colors.gold),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'المبلغ المحصل نقداً',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              'دج',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _cashController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
          ],
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.attach_money_rounded),
            suffixText: 'دج',
            filled: true,
            fillColor: isDark
                ? theme.colorScheme.surfaceContainerHigh
                : theme.colorScheme.surfaceContainerLowest,
          ),
          validator: (value) {
            final parsed = DzdFormatter.parseDinarsToCentimes(value ?? '');
            if (parsed < 0) return 'أدخل مبلغاً صحيحاً';
            return null;
          },
          onChanged: (value) {
            final parsed = DzdFormatter.parseDinarsToCentimes(value);
            setState(() {
              _collectedCentimes = parsed;
              if (parsed > 0) _deferredConfirmed = false;
              _errorMessage = null;
            });
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            ActionChip(
              avatar: Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: colors.gold,
              ),
              label: Text(
                'المبلغ كاملاً (${DzdFormatter.formatCentimes(due, showDecimals: false)})',
              ),
              onPressed: () => _setAmount(due),
              backgroundColor: colors.goldMuted,
              side: BorderSide(color: colors.goldBorder),
            ),
            ActionChip(
              avatar: Icon(
                Icons.schedule_rounded,
                size: 16,
                color: colors.warning,
              ),
              label: const Text('دفع لاحقاً / آجل'),
              onPressed: () => _setAmount(0),
              backgroundColor: colors.warningContainer.withValues(alpha: 0.45),
              side: BorderSide(color: colors.warning.withValues(alpha: 0.25)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentRecap(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
  ) {
    final remaining = _dueCentimes - _collectedCentimes;

    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.goldMuted,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: colors.goldBorder),
      ),
      child: Column(
        children: [
          _PaymentRow(
            label: 'المطلوب قبل التحصيل',
            value: DzdFormatter.formatCentimes(
              _dueCentimes,
              showDecimals: false,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _PaymentRow(
            label: 'المحصل الآن',
            value: DzdFormatter.formatCentimes(
              _collectedCentimes,
              showDecimals: false,
            ),
            color: colors.success,
            bold: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          _PaymentRow(
            label: remaining > 0
                ? 'سيُضاف على حساب الزبون'
                : (remaining < 0 ? 'زيادة محصلة' : 'تم التحصيل بالكامل'),
            value: DzdFormatter.formatCentimes(
              remaining.abs(),
              showDecimals: false,
            ),
            color: remaining > 0
                ? colors.warning
                : (remaining < 0 ? colors.info : colors.success),
            bold: remaining != 0,
          ),
          if (remaining != 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  remaining > 0
                      ? Icons.info_outline_rounded
                      : Icons.notifications_active_outlined,
                  size: 14,
                  color: remaining > 0 ? colors.warning : colors.info,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    remaining > 0
                        ? 'سيتم ترحيل المبلغ المتبقي إلى حساب الزبون تلقائياً.'
                        : 'المبلغ المحصل أكبر من المتبقي. تأكد من إرجاع الباقي للزبون.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: remaining > 0 ? colors.warning : colors.info,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeferredConfirmation(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colors.warningContainer.withValues(alpha: 0.35),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.30)),
      ),
      child: CheckboxListTile(
        value: _deferredConfirmed,
        onChanged: (value) =>
            setState(() => _deferredConfirmed = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 0,
        ),
        dense: true,
        activeColor: colors.warning,
        title: Text(
          'أؤكد أن الزبون لم يدفع نقداً الآن',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'سيُسجل كامل المبلغ المتبقي كدين على حساب الزبون.',
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }

  Widget _buildGpsStamp(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
  ) {
    final hasPosition = _stampedPosition != null;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: hasPosition
            ? colors.successContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: hasPosition
              ? colors.success.withValues(alpha: 0.28)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          if (_isFetchingGps) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'جارٍ التقاط الموقع الجغرافي...',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ] else if (hasPosition) ...[
            Icon(Icons.my_location_rounded, size: 17, color: colors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تم توثيق موقع التسليم',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _stampedAddress ??
                        '${_stampedPosition!.latitude.toStringAsFixed(4)}, ${_stampedPosition!.longitude.toStringAsFixed(4)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تحديث الموقع',
              visualDensity: VisualDensity.compact,
              onPressed: _captureGpsStamp,
              icon: const Icon(Icons.refresh_rounded, size: 17),
            ),
          ] else ...[
            Icon(
              Icons.location_off_outlined,
              size: 17,
              color: colors.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _gpsError ?? 'لم يتم التقاط الموقع بعد',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.warning,
                ),
              ),
            ),
            TextButton(
              onPressed: _captureGpsStamp,
              child: const Text('تحديث'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
  ) {
    final submitLabel = _isSubmitting ? 'جارٍ التسليم...' : 'تأكيد التسليم';

    final cancelButton = TextButton(
      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
      child: const Text('إلغاء'),
    );

    final submitButton = SizedBox(
      height: 50,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: colors.success,
          foregroundColor: colors.onSuccess,
          disabledBackgroundColor: colors.success.withValues(alpha: 0.45),
          disabledForegroundColor: colors.onSuccess.withValues(alpha: 0.75),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.mdAll,
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        onPressed: _canSubmit ? _finalizeDelivery : null,
        icon: _isSubmitting
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.onSuccess),
                ),
              )
            : const Icon(Icons.done_all_rounded, size: 18),
        label: Text(submitLabel),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              submitButton,
              const SizedBox(height: AppSpacing.xs),
              cancelButton,
            ],
          );
        }

        return Row(
          children: [
            cancelButton,
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: submitButton),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local UI pieces
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  const _SummaryValue({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  const _PaymentRow({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          '$value دج',
          style: theme.textTheme.labelMedium?.copyWith(
            color: color ?? theme.colorScheme.onSurface,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.55),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.error.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 17, color: colors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: colors.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
