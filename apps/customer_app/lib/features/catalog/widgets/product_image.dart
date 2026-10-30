import 'package:cached_network_image/cached_network_image.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../../services/customer_image_cache.dart';

/// Product photo with a neutral fallback for missing or broken images.
///
/// The image is decorative: the product name is always rendered next to it, so
/// screen readers do not need a duplicated label.
class CatalogProductImage extends StatelessWidget {
  final ProductEntity product;
  final BoxFit fit;

  const CatalogProductImage({
    super.key,
    required this.product,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = product.photoUrl?.trim();
    final Widget image = url == null || url.isEmpty
        ? _fallback(scheme)
        : CachedNetworkImage(
            imageUrl: url,
            cacheManager: CustomerImageCache.manager,
            fit: fit,
            memCacheWidth: 640,
            fadeInDuration: AppMotion.fast,
            placeholder: (_, __) =>
                ColoredBox(color: scheme.surfaceContainerHigh),
            errorWidget: (_, __, ___) => _fallback(scheme),
          );
    return ExcludeSemantics(child: image);
  }

  Widget _fallback(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: 28,
          color: scheme.primary.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
