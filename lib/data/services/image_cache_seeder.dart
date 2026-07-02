import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Seeds the on-disk image cache — the same one `CachedNetworkImage` reads —
/// with just-uploaded bytes under their final stored URL.
///
/// Why: every upload produces a brand-new timestamped object URL, so the very
/// first render of a freshly uploaded meal photo / avatar was a guaranteed
/// cache MISS that re-downloaded from the CDN over a high-RTT link (seconds of
/// "why isn't my new image showing?"). Seeding the cache with the bytes we
/// *just sent* makes the new image render instantly everywhere in the app —
/// zero network — while staying byte-identical to what the server stored.
///
/// Purely additive + best-effort: on any failure the image simply downloads
/// exactly as before.
class ImageCacheSeeder {
  ImageCacheSeeder._();

  /// Stores [bytes] under [url] in the default image cache. No-ops when [url]
  /// is null or not an http(s) URL (e.g. a base64 data URI). Fire-and-forget.
  static Future<void> seed(String? url, Uint8List bytes) async {
    if (url == null ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      return;
    }
    try {
      await DefaultCacheManager().putFile(url, bytes, fileExtension: 'jpg');
    } catch (_) {/* best-effort: a seed failure only means a normal download */}
  }
}
