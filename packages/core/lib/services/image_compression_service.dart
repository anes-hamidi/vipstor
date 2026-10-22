/// Image compression utilities for minimizing Supabase Storage consumption.
///
/// All product, profile, and asset images are compressed to WebP before
/// upload. Binary image data is never stored inside PostgreSQL columns —
/// only secure public/signed URLs are persisted in the database.
library;

import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
/// Compresses raw image bytes to WebP format before storage upload.
///
/// [quality] controls the compression level (0-100, default 85).
/// Returns the WebP-encoded byte list.
///
/// Throws if compression fails; callers should fall back to the original
/// bytes (e.g., upload as JPEG) to avoid breaking the upload flow.
class ImageCompressionService {
  ImageCompressionService._();

  /// Compresses [bytes] to WebP format.
  static Future<Uint8List> compressToWebP(
    Uint8List bytes, {
    int quality = 85,
  }) async {
    final result = await FlutterImageCompress.compressWithList(
      bytes,
      quality: quality.clamp(0, 100),
      format: CompressFormat.webp,
    );
    if (result.isEmpty) {
      throw StateError('Image compression returned empty result');
    }
    return Uint8List.fromList(result);
  }
}
