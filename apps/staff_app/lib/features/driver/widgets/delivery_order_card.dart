import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:ui_kit/ui_kit.dart';

import 'driver_order_utils.dart';

/// Delivery task card used in the driver queue, the map stop sheet and the
/// desktop route panel.
///
/// The card is fully responsive: action buttons stack on narrow phones and
/// align on one row once enough width is available. Item details are collapsed
/// by default to keep the queue scannable, then expand in place.
class DeliveryOrderCard extends StatefulWidget {
  final OrderEntity order;
  final int? stopNumber;
  final double? distanceKm;
  final VoidCallback? onNavigate;
  final VoidCallback? onCall;
  final VoidCallback? onDeliver;
  final bool embedded;
  final bool highlighted;

  const DeliveryOrderCard({
    super.key,
    required this.order,
    this.stopNumber,
    this.distanceKm,
    this.onNavigate,
    this.onCall,
    this.onDeliver,
    this.embedded = false,
    this.highlighted = false,
  });

  @override
  State<DeliveryOrderCard> createState() => _DeliveryOrderCardState();
}

class _DeliveryOrderCardState extends State<DeliveryOrderCard> {
  bool _itemsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final order = widget.order;
    final isActive = isOrderActive(order.status);
    final isCompleted = isOrderCompleted(order.status);
    final customer = deliveryCustomerName(order);
    final phone = deliveryCustomerPhone(order);
    final address = deliveryAddressText(order);
    final note = deliveryNote(order);
    final distance = formatDistanceKm(widget.distanceKm);

    final content = Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, theme, colors, isActive, isCompleted),
          const SizedBox(height: AppSpacing.md),
          _buildCustomerRow(context, theme, colors, customer, phone),
          if (address != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildAddressRow(context, theme, colors, address, distance),
          ],
          if (note != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildNote(context, theme, colors, note),
          ],
          const SizedBox(height: AppSpacing.md),
          _buildMetaChips(context, theme, colors, isActive),
          const SizedBox(height: AppSpacing.md),
          _buildAmountPanel(context, theme, colors, isActive, isCompleted),
          const SizedBox(height: AppSpacing.sm),
          _buildItemsSection(context, theme, colors),
          const SizedBox(height: AppSpacing.sm),
          const GoldDivider(
            height: 1,
            margin: EdgeInsetsDirectional.symmetric(
              vertical: AppSpacing.sm,
            ),
          ),
          _buildActions(context, theme, colors, isActive, isCompleted, phone),
        ],
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return LuxuryCard(
      goldAccent: isActive,
      selected: widget.highlighted,
      padding: EdgeInsets.zero,
      child: content,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    bool isActive,
    bool isCompleted,
  ) {
    final order = widget.order;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StopBadge(
          number: widget.stopNumber,
          active: isActive,
          completed: isCompleted,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'طلب #${orderShortNumber(order)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                formatTimeAgo(order.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        StatusBadge(
          type: _badgeType(order.status),
          customLabel: _statusLabel(order.status),
          compact: true,
        ),
      ],
    );
  }

  Widget _buildCustomerRow(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    String customer,
    String? phone,
  ) {
    final order = widget.order;
    final isOnline = order.channel == OrderChannel.online;

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.goldMuted,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: colors.goldBorder),
          ),
          child: Icon(
            isOnline ? Icons.storefront_rounded : Icons.person_rounded,
            size: 19,
            color: colors.gold,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (phone != null)
                Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (phone != null && widget.onCall != null)
          _SmallActionButton(
            icon: Icons.call_rounded,
            tooltip: 'اتصال بالزبون',
            color: colors.success,
            onPressed: widget.onCall,
          ),
      ],
    );
  }

  Widget _buildAddressRow(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    String address,
    String distance,
  ) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 17,
            color: colors.gold,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              address,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (distance.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: colors.goldMuted,
                borderRadius: AppRadius.pillAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.near_me_rounded, size: 11, color: colors.gold),
                  const SizedBox(width: 3),
                  Text(
                    distance,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.gold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNote(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    String note,
  ) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.warningContainer.withValues(alpha: 0.45),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 15, color: colors.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onWarningContainer,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChips(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    bool isActive,
  ) {
    final order = widget.order;
    final due = order.dueAmountCentimes;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        _MetaChip(
          icon: Icons.inventory_2_outlined,
          label: '${order.items.length} أصناف',
        ),
        _MetaChip(
          icon: Icons.payments_outlined,
          label: paymentSituationLabel(order),
          color: due <= 0 ? colors.success : colors.warning,
        ),
        _MetaChip(
          icon: order.channel == OrderChannel.online
              ? Icons.language_rounded
              : Icons.store_rounded,
          label:
              order.channel == OrderChannel.online ? 'طلب أونلاين' : 'طلب متجر',
        ),
        if (!isActive && order.status == OrderStatus.settled)
          _MetaChip(
            icon: Icons.verified_outlined,
            label: 'تمت التسوية',
            color: colors.success,
          ),
      ],
    );
  }

  Widget _buildAmountPanel(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    bool isActive,
    bool isCompleted,
  ) {
    final order = widget.order;
    final due = order.dueAmountCentimes;
    final isSettled = order.status == OrderStatus.settled;
    final hasPaid = order.paidAmountCentimes > 0;
    final showAccountBalance = isCompleted && !isSettled && due > 0;
    final primaryAmount = isCompleted
        ? (isSettled || hasPaid ? order.paidAmountCentimes : due)
        : due;
    final label = isCompleted
        ? (isSettled || hasPaid ? 'المحصل نقداً' : 'المبلغ على الحساب')
        : 'المطلوب تحصيله';
    final valueColor = isCompleted
        ? (isSettled || hasPaid ? colors.success : colors.warning)
        : colors.gold;
    // Only show the secondary figure when it adds information: a prepayment on
    // an active task, or the remaining account balance after a partial payment.
    final showSecondary = hasPaid && (isActive || due > 0);
    final secondaryLabel =
        showAccountBalance ? 'المتبقي على الحساب' : 'مدفوع مسبقاً';
    final secondaryAmount = showAccountBalance ? due : order.paidAmountCentimes;
    final secondaryColor = showAccountBalance ? colors.warning : colors.success;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            colors.goldMuted,
            theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
          ],
        ),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.goldBorder.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                DzdPriceTag.lg(
                  centimes: primaryAmount,
                  gold: isActive,
                  color: valueColor,
                ),
              ],
            ),
          ),
          if (showSecondary)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  secondaryLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  DzdFormatter.formatCentimes(
                    secondaryAmount,
                    showDecimals: false,
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: secondaryColor,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildItemsSection(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
  ) {
    final items = widget.order.items;

    if (items.isEmpty) {
      return Text(
        'لا توجد أصناف مسجلة في هذا الطلب',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _itemsExpanded = !_itemsExpanded),
          borderRadius: AppRadius.smAll,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  Icons.list_alt_rounded,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'تفاصيل الأصناف (${items.length})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _itemsExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _itemsExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
            child: Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          constraints: const BoxConstraints(minWidth: 24),
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: AppRadius.smAll,
                          ),
                          child: Text(
                            '${item.quantity}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            item.productName.isEmpty
                                ? 'صنف ${item.productId.length > 6 ? item.productId.substring(0, 6) : item.productId}'
                                : item.productName,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          DzdFormatter.formatCentimes(
                            item.lineTotalCentimes,
                            showDecimals: false,
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    bool isActive,
    bool isCompleted,
    String? phone,
  ) {
    if (!isActive) {
      return Row(
        children: [
          Icon(
            isCompleted ? Icons.task_alt_rounded : Icons.block_rounded,
            size: 16,
            color: isCompleted ? colors.success : colors.cancelled,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              isCompleted
                  ? 'تم إنجاز هذه المهمة بنجاح'
                  : 'هذه المهمة لم تعد نشطة',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isCompleted
                    ? colors.success
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.onNavigate != null)
            TextButton.icon(
              onPressed: widget.onNavigate,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('العنوان'),
            ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 430;
        final navigateButton = OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.gold,
            side: BorderSide(color: colors.gold.withValues(alpha: 0.45)),
            minimumSize: const Size(0, 46),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.md,
            ),
          ),
          onPressed: widget.onNavigate,
          icon: const Icon(Icons.navigation_rounded, size: 17),
          label: const Text('الملاحة'),
        );
        final callButton = phone != null && widget.onCall != null
            ? _SmallActionButton(
                icon: Icons.call_rounded,
                tooltip: 'اتصال بالزبون',
                color: colors.success,
                onPressed: widget.onCall,
                size: 46,
              )
            : null;
        final deliverButton = SizedBox(
          width: double.infinity,
          child: GoldButton.icon(
            onPressed: widget.onDeliver,
            icon: Icons.check_circle_outline_rounded,
            label: 'تأكيد التسليم',
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              deliverButton,
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: navigateButton),
                  if (callButton != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    callButton,
                  ],
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: navigateButton),
            if (callButton != null) ...[
              const SizedBox(width: AppSpacing.sm),
              callButton,
            ],
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: deliverButton),
          ],
        );
      },
    );
  }

  static StatusBadgeType _badgeType(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return StatusBadgeType.delivered;
      case OrderStatus.settled:
        return StatusBadgeType.completed;
      case OrderStatus.outForDelivery:
        return StatusBadgeType.processing;
      case OrderStatus.ready:
        return StatusBadgeType.ready;
      case OrderStatus.cancelled:
      case OrderStatus.refused:
        return StatusBadgeType.cancelled;
      case OrderStatus.assigned:
      case OrderStatus.accepted:
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
      case OrderStatus.submitted:
      case OrderStatus.requiresManagerReview:
        return StatusBadgeType.pending;
    }
  }

  static String _statusLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return 'تم التسليم';
      case OrderStatus.settled:
        return 'تمت التسوية';
      case OrderStatus.outForDelivery:
        return 'في الطريق';
      case OrderStatus.ready:
        return 'جاهز';
      case OrderStatus.cancelled:
        return 'ملغى';
      case OrderStatus.refused:
        return 'مرفوض';
      case OrderStatus.assigned:
        return 'مكلف';
      case OrderStatus.accepted:
        return 'مقبول';
      case OrderStatus.confirmed:
        return 'مؤكد';
      case OrderStatus.preparing:
        return 'يُحضَّر';
      case OrderStatus.submitted:
        return 'جديد';
      case OrderStatus.requiresManagerReview:
        return 'مراجعة';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small building blocks
// ─────────────────────────────────────────────────────────────────────────────

class _StopBadge extends StatelessWidget {
  final int? number;
  final bool active;
  final bool completed;

  const _StopBadge({
    required this.number,
    required this.active,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final stateColor = completed ? colors.success : colors.cancelled;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: active ? AppGradients.gold : null,
        color: active ? null : stateColor.withValues(alpha: 0.14),
        borderRadius: AppRadius.mdAll,
        border: active
            ? null
            : Border.all(color: stateColor.withValues(alpha: 0.30)),
        boxShadow: active ? const [AppShadows.goldGlowSm] : null,
      ),
      alignment: Alignment.center,
      child: active
          ? (number != null
              ? Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1400),
                  ),
                )
              // Active tasks without a sequence (e.g. a stop opened from the
              // "without location" map section) still need an active marker.
              : const Icon(
                  Icons.local_shipping_rounded,
                  size: 18,
                  color: Color(0xFF1A1400),
                ))
          : Icon(
              completed ? Icons.check_rounded : Icons.remove_rounded,
              size: 18,
              color: stateColor,
            ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = color ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.08),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: resolved.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: resolved),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: resolved,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;
  final double size;

  const _SmallActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.35)),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.mdAll,
            ),
            minimumSize: Size(size, size),
          ),
          onPressed: onPressed,
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}
