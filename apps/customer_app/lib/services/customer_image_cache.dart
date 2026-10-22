import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Persistent image cache shared by every product / avatar image.
///
/// A dedicated cache key lets us tune retention for catalogue photos while
/// keeping Flutter's default cache free for other network images.
class CustomerImageCache {
  CustomerImageCache._();

  static const _cacheKey = 'vip_customer_catalogue_v1';

  static final CacheManager manager = CacheManager(
    Config(
      _cacheKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 400,
      repo: JsonCacheInfoRepository(databaseName: _cacheKey),
      fileService: HttpFileService(),
    ),
  );

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
            await manager.downloadFile(url);
          } catch (_) {
            // Ignore individual image failures.
          }
        }));
      }
    } finally {
      _warming = false;
    }
  }
}
