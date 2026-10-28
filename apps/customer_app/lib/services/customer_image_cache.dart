import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Persistent image cache shared by every product / avatar image.
///
/// Delegates to CachedNetworkImage's DefaultCacheManager so all catalogue
/// images share one unified cache without adding a separate dependency.
class CustomerImageCache {
  CustomerImageCache._();

  /// The shared cache manager instance used by [CachedNetworkImage] widgets.
  ///
  /// Pass this as `cacheManager:` to every [CachedNetworkImage] so all images
  /// share one unified LRU disk cache.
  static final manager = DefaultCacheManager();

  static bool _warming = false;

  /// Downloads the first screenful of images ahead of scrolling.
  ///
  /// Runs at most four requests at a time and never throws: a missing photo
  /// must not interrupt catalogue rendering.
  static Future<void> warmUp(
    Iterable<String?> urls, {
    int limit = 28,
    int concurrency = 4,
  }) async {
    if (_warming) return;
    final unique = urls
        .whereType<String>()
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && u.startsWith('http'))
        .toSet()
        .take(limit)
        .toList();
    if (unique.isEmpty) return;

    _warming = true;
    try {
      for (var i = 0; i < unique.length; i += concurrency) {
        final batch = unique.skip(i).take(concurrency);
        await Future.wait(batch.map((url) async {
          try {
            // Pre-populate the shared disk cache via DefaultCacheManager.
            await manager.getSingleFile(url);
          } catch (_) {
            // Ignore individual image failures — a missing photo must not
            // interrupt catalogue rendering.
          }
        }));
      }
    } finally {
      _warming = false;
    }
  }
}
