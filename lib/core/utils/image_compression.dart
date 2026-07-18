import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Live-Test-11 ISSUE-007 — guaranteed-fit image compression.
///
/// The previous quality-only ladder (fixed 1080 px, quality 70→20) could not
/// bring every photo under the byte budget — detailed/noisy photos stayed
/// above the cap even at quality 20 and the upload was rejected with
/// "too large even after compression". This ladder steps RESOLUTION down as
/// well as quality, so any real-world photo lands inside the budget while
/// keeping the best resolution/quality pair that fits.
///
/// Aspect ratio is always preserved by the codec (no cropping); EXIF is
/// stripped. Returns null only when the codec cannot process the input at all.
Future<Uint8List?> compressImageToBudget(
  Uint8List raw,
  int maxBytes,
) async {
  // Already inside the budget — nothing to do.
  if (raw.length <= maxBytes) return raw;

  // (bound, qualities): descending resolution bounds, each with its own
  // quality steps. 640 px @ quality 20 is a few tens of KB for any photo —
  // the practical guarantee that the budget is reachable.
  const ladder = <(int, List<int>)>[
    (1080, [70, 55, 40]),
    (800, [55, 40, 30]),
    (640, [45, 30, 20]),
  ];

  Uint8List? best;
  for (final (bound, qualities) in ladder) {
    for (final q in qualities) {
      try {
        final out = await FlutterImageCompress.compressWithList(
          raw,
          quality: q,
          minWidth: bound,
          minHeight: (bound * 2) ~/ 3,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
        if (out.isEmpty) continue;
        best = out;
        if (out.length <= maxBytes) return out;
      } catch (_) {
        // Try the next rung — a single codec failure must not abort the ladder.
      }
    }
  }
  // Nothing fit (pathological input) — return the smallest attempt so the
  // caller's byte-cap check produces its normal, friendly error.
  return best;
}
