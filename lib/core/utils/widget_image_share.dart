import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Captures a widget subtree (wrapped in a [RepaintBoundary] keyed by
/// [boundaryKey]) as a PNG and opens the platform share sheet with the image.
///
/// Used for sharing the complete group-join QR card as an image (FR-GRP QR
/// share). Falls back to sharing [fallbackText] alone when capture fails for
/// any reason (widget not laid out, platform error) — sharing never crashes
/// the app.
///
/// Returns `true` when the image share sheet was opened, `false` when the
/// text-only fallback was used.
class WidgetImageShare {
  const WidgetImageShare._();

  static Future<bool> shareAsImage({
    required GlobalKey boundaryKey,
    required String filename,
    String? text,
    String? subject,
    double pixelRatio = 3.0,
  }) async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('RepaintBoundary not found');
      // If the boundary needs paint (mid-frame), give it one frame to settle.
      if (boundary.debugNeedsPaint) {
        await Future<void>.delayed(const Duration(milliseconds: 32));
      }
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('PNG encode failed');

      final dir = await getTemporaryDirectory();
      final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: text,
        subject: subject,
      );
      return true;
    } catch (_) {
      // Fail-safe: never let image capture break sharing — degrade to text.
      if (text != null && text.isNotEmpty) {
        await Share.share(text, subject: subject);
      }
      return false;
    }
  }
}
