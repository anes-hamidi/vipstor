import 'package:core/core.dart';
import 'package:flutter/material.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_shadows.dart';
import '../tokens/app_spacing.dart';

/// Premium KPI metric tile with animated glow on hover, a gradient icon chip,
/// optional delta trend indicator, and a gold foil bottom accent line.
///
/// ```dart
/// KpiCard(
///   title: 'إجمالي المبيعات',
///   value: 'DZD 142,500',
///   icon: Icons.point_of_sale_rounded,
///   deltaText: '+12%',
///   isPositiveDelta: true,
/// )
/// ```
class KpiCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? accentColor;
  final String? subtitle;
  final String? deltaText;
  final bool? isPositiveDelta;
  final VoidCallback? onTap;
  final bool loading;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.accentColor,
    this.subtitle,
    this.deltaText,
    this.isPositiveDelta,
    this.onTap,
    this.loading = false,
  });

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final scheme  = theme.colorScheme;
    final colors  = context.appColors;
    final isDark  = theme.brightness == Brightness.dark;
    final accent  = widget.accentColor ?? context.roleTheme.roleBrandColor;

    final bgColor   = scheme.surfaceContainerLow;
    final shadows   = isDark ? AppShadows.cardSoftDark : AppShadows.cardSoftLight;
    final borderClr = accent.withValues(alpha: isDark ? 0.32 : 0.22);

    return MouseRegion(
      onEnter: (_) { if (widget.onTap != null || true) _ctrl.forward(); },
      onExit:  (_) => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _glow,
        builder: (ctx, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: Color.lerp(borderClr, accent, _glow.value * 0.7)!,
              width: 1.0 + _glow.value * 0.5,
            ),
            boxShadow: [
              ...shadows,
              if (_glow.value > 0.05)
                BoxShadow(
                  color: accent.withValues(alpha: 0.12 * _glow.value),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: child,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.lgAll,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              highlightColor: accent.withValues(alpha: 0.06),
              splashColor:    accent.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                child: widget.loading
                    ? _LoadingSkeleton(accent: accent)
                    : _KpiContent(
                        widget: widget,
                        accent: accent,
                        colors: colors,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiContent extends StatelessWidget {
  final KpiCard widget;
  final Color accent;
  final AppColors colors;

  const _KpiContent({
    required this.widget,
    required this.accent,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row: title + icon chip
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Gradient icon chip
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.22),
                    accent.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: accent.withValues(alpha: 0.32),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(widget.icon, color: accent, size: 20),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.sm),

        // Value
        Text(
          widget.value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: theme.colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        // Delta + subtitle row
        if (widget.subtitle != null || widget.deltaText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              if (widget.deltaText != null) ...[
                _DeltaChip(
                  text: widget.deltaText!,
                  isPositive: widget.isPositiveDelta ?? true,
                  colors: colors,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (widget.subtitle != null)
                Expanded(
                  child: Text(
                    widget.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],

        // Brand foil accent line
        Padding(
          padding: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
          child: Container(
            height: 2.5,
            width: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [
                  accent,
                  Color.lerp(accent, Colors.white, 0.45)!,
                ],
              ),
              borderRadius: AppRadius.fullAll,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.24),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final String text;
  final bool isPositive;
  final AppColors colors;

  const _DeltaChip({
    required this.text,
    required this.isPositive,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPositive ? colors.success : colors.cancelled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingSkeleton extends StatefulWidget {
  final Color accent;
  const _LoadingSkeleton({required this.accent});

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final shimmerGrad = LinearGradient(
          colors: [
            isDark ? const Color(0xFF2A2518) : const Color(0xFFEDE3B8),
            isDark ? const Color(0xFF3A3220) : const Color(0xFFFFFBEE),
            isDark ? const Color(0xFF2A2518) : const Color(0xFFEDE3B8),
          ],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-1 + _ctrl.value * 2, 0),
          end: Alignment(1 + _ctrl.value * 2, 0),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _shimmerBox(shimmerGrad, 80, 12),
                _shimmerBox(shimmerGrad, 36, 36, radius: AppRadius.mdAll),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _shimmerBox(shimmerGrad, 140, 24),
            const SizedBox(height: AppSpacing.sm),
            _shimmerBox(shimmerGrad, 90, 12),
          ],
        );
      },
    );
  }

  Widget _shimmerBox(LinearGradient g, double w, double h,
      {BorderRadius? radius}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: g,
        borderRadius: radius ?? AppRadius.smAll,
      ),
    );
  }
}
