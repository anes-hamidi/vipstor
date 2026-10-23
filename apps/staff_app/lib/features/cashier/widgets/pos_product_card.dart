import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:domain/domain.dart';

/// Premium POS product tile with:
/// - Brand border on in-cart state with glow shadow
/// - Tonal price footer
/// - Animated add-to-cart button in the role brand color
/// - Compact stock badge
class PosProductCard extends StatefulWidget {
  final ProductEntity product;
  final int cartQuantity;
  final VoidCallback? onAddToCart;

  const PosProductCard({
    super.key,
    required this.product,
    this.cartQuantity = 0,
    required this.onAddToCart,
  });

  @override
  State<PosProductCard> createState() => _PosProductCardState();
}

class _PosProductCardState extends State<PosProductCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _glowAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final role = context.roleTheme;
    final brand = role.roleBrandColor;

    final retailePrice =
        widget.product.getPriceForQuantity(PriceTier.retail, 1);
    final isAvailable = widget.product.availableQty > 0;
    final inCart = widget.cartQuantity > 0;

    Color bgColor;
    Color borderColor;
    List<BoxShadow> shadows;

    if (inCart) {
      bgColor = role.badgeBackground;
      borderColor = brand;
      shadows = [
        BoxShadow(
          color: cs.shadow.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: brand.withValues(alpha: 0.22),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ];
    } else if (!isAvailable) {
      bgColor = cs.surfaceContainerLow;
      borderColor = cs.outlineVariant;
      shadows = [];
    } else {
      bgColor = cs.surface;
      borderColor = cs.outlineVariant.withValues(alpha: 0.75);
      shadows = [
        BoxShadow(
          color: cs.shadow.withValues(alpha: isDark ? 0.28 : 0.06),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
    }

    if (_hovered && isAvailable && !inCart) {
      borderColor = brand.withValues(alpha: 0.60);
    }

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        if (isAvailable) _ctrl.forward();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        _ctrl.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (ctx, child) => DecoratedBox(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: AppRadius.xl2All,
              border: Border.all(
                color: Color.lerp(
                  borderColor,
                  brand,
                  inCart ? 1.0 : _glowAnim.value * 0.4,
                )!,
                width: inCart ? 1.5 : 1.0,
              ),
              boxShadow: shadows,
            ),
            child: child,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.xl2All,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isAvailable ? widget.onAddToCart : null,
                borderRadius: AppRadius.xl2All,
                highlightColor: brand.withValues(alpha: 0.08),
                splashColor: brand.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Short cards: drop the French name, tighten the footer.
                      final compact = constraints.maxHeight < 190;
                      final type = widget.product.unit;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Image with overlaid badges ─────
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _ProductImage(
                                  url: widget.product.photoUrl,
                                  isAvailable: isAvailable,
                                ),
                                // Stock badge + cart pill
                                PositionedDirectional(
                                  top: 4,
                                  start: 4,
                                  end: 4,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (inCart) ...[
                                        TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.8, end: 1.0),
                                          duration:
                                              const Duration(milliseconds: 250),
                                          curve: Curves.elasticOut,
                                          builder: (context, val, child) =>
                                              Transform.scale(
                                                  scale: val, child: child),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: brand,
                                              borderRadius: AppRadius.pillAll,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: brand.withValues(
                                                      alpha: 0.35),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .symmetric(
                                                horizontal: AppSpacing.sm,
                                                vertical: 3,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .shopping_cart_rounded,
                                                      size: 10,
                                                      color: cs.onPrimary),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    '${widget.cartQuantity}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: cs.onPrimary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Pack size chip
                                if (widget.product.packSize > 1)
                                  PositionedDirectional(
                                    bottom: 4,
                                    start: 4,
                                    end: 4,
                                    child: Align(
                                      alignment:
                                          AlignmentDirectional.bottomStart,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.surface
                                              .withValues(alpha: 0.92),
                                          borderRadius: AppRadius.smAll,
                                        ),
                                        child: Text(
                                          type,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: brand,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: AppSpacing.sm),

                          // ── Names ─────
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.product.nameAr,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  height: 1.2,
                                  color: isAvailable
                                      ? cs.onSurface
                                      : cs.onSurface.withValues(alpha: 0.40),
                                ),
                              ),
                              if (!compact &&
                                  widget.product.nameFr.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.product.nameFr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant
                                        .withValues(alpha: 0.70),
                                  ),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: AppSpacing.xs + 2),

                          // ── Footer: Wholesale Price & Action Button ─────
                          Container(
                            padding: EdgeInsetsDirectional.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical:
                                  compact ? AppSpacing.xs : AppSpacing.xs + 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: AppRadius.mdAll,
                              border: Border.all(
                                color: brand.withValues(
                                  alpha: isDark ? 0.20 : 0.15,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: DzdPriceTag(
                                      centimes: retailePrice,
                                      gold: inCart,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                if (!isAvailable)
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
                                      borderRadius: AppRadius.smAll,
                                    ),
                                    child: Icon(
                                      Icons.block_rounded,
                                      size: 14,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Product photo with a neutral placeholder for missing / loading / failed
/// images. Greyed out when the product is out of stock.
class _ProductImage extends StatelessWidget {
  final String? url;
  final bool isAvailable;

  const _ProductImage({
    required this.url,
    required this.isAvailable,
  });

  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholderColor = cs.surfaceContainerHigh;
    final iconColor = cs.onSurfaceVariant.withValues(alpha: 0.70);

    final placeholder = Center(
      child: Icon(Icons.inventory_2_outlined, size: 28, color: iconColor),
    );

    final hasUrl = url != null && url!.isNotEmpty;

    Widget content = hasUrl
        ? Image.network(
            url!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 400,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSyncLoaded) {
              if (wasSyncLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (_, __, ___) => placeholder,
          )
        : placeholder;

    if (!isAvailable && hasUrl) {
      content = Opacity(
        opacity: 0.55,
        child: ColorFiltered(colorFilter: _greyscale, child: content),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: placeholderColor,
        borderRadius: AppRadius.mdAll,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.mdAll,
        child: SizedBox.expand(child: content),
      ),
    );
  }
}
