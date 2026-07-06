import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Issue 3 (command_3): share the group invite as a PREMIUM QR *image* on both
/// admin and student sides.
///
/// The previous approach captured a laid-out widget via [RenderRepaintBoundary].
/// On real devices the capture frequently raced widget paint, threw, and
/// silently degraded to a text-only WhatsApp share (only the code went out).
///
/// This composer renders the QR straight to PNG bytes with [QrPainter] on an
/// off-screen [ui.Canvas] — there is NO widget, no layout, and therefore no
/// capture race. The QR, group name and join code are drawn onto a branded card
/// so the shared image is scannable AND recognisably MealAttend. Sharing never
/// throws: any failure degrades to a plain text share (fail-safe).
class QrShare {
  const QrShare._();

  /// Compose the branded QR card and open the platform share sheet with the PNG.
  /// Returns `true` when the image was shared, `false` on the text-only fallback.
  static Future<bool> shareGroupQr({
    required String qrData,
    required String joinCode,
    required String groupName,
    String? text,
    String? subject,
    double scale = 3.0,
  }) async {
    try {
      final bytes = await composePng(
        qrData: qrData,
        joinCode: joinCode,
        groupName: groupName,
        scale: scale,
      );

      final dir = await getTemporaryDirectory();
      final safeName =
          'mealattend-group-qr-$joinCode.png'.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: text,
        subject: subject,
      );
      return true;
    } catch (_) {
      // Fail-safe: never let composition break sharing — degrade to text.
      if (text != null && text.isNotEmpty) {
        await Share.share(text, subject: subject);
      }
      return false;
    }
  }

  // ── Off-screen composition ─────────────────────────────────────────────────

  /// Logical layout constants (device-independent px). The final raster is
  /// [scale]× larger for crisp output.
  static const double _w = 360;
  static const double _pad = 24;
  static const double _qrSize = 240;

  /// Renders the branded QR card to PNG bytes. Exposed for testing.
  static Future<Uint8List> composePng({
    required String qrData,
    required String joinCode,
    required String groupName,
    double scale = 3.0,
  }) async {
    final qrLeft = (_w - _qrSize) / 2;
    const qrTop = 96.0;

    // Text painters (measured up-front so the card height fits the content).
    final titleTp = _text(
      groupName,
      const TextStyle(
        color: Color(0xFF4338CA),
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: _w - 2 * _pad,
      maxLines: 2,
    );
    final codeTp = _text(
      joinCode,
      const TextStyle(
        color: Color(0xFF111827),
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: 6,
      ),
      maxWidth: _w - 2 * _pad,
    );
    final hintTp = _text(
      'Scan with MealAttend or enter the code to join',
      const TextStyle(
        color: Color(0xFF6B7280),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      maxWidth: _w - 2 * _pad,
      maxLines: 2,
    );

    final codeTop = qrTop + _qrSize + 28;
    final hintTop = codeTop + codeTp.height + 14;
    final h = hintTop + hintTp.height + 28;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);

    // ── Branded gradient backdrop ──
    final bgRect = Rect.fromLTWH(0, 0, _w, h);
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(_w, h),
          const [Color(0xFF6366F1), Color(0xFF7C3AED)],
        ),
    );

    // ── White card ──
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(16, 16, _w - 32, h - 32),
      const Radius.circular(24),
    );
    canvas.drawRRect(cardRect, Paint()..color = Colors.white);

    // ── Title ──
    titleTp.paint(canvas, Offset((_w - titleTp.width) / 2, 44));

    // ── QR white panel + border ──
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(qrLeft - 12, qrTop - 12, _qrSize + 24, _qrSize + 24),
      const Radius.circular(16),
    );
    canvas.drawRRect(panel, Paint()..color = Colors.white);
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE5E7EB),
    );

    // ── QR (drawn directly, no widget capture) ──
    final qrPainter = QrPainter(
      data: qrData,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF111827),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF111827),
      ),
    );
    canvas.save();
    canvas.translate(qrLeft, qrTop);
    qrPainter.paint(canvas, const Size(_qrSize, _qrSize));
    canvas.restore();

    // ── Join code + hint ──
    codeTp.paint(canvas, Offset((_w - codeTp.width) / 2, codeTop));
    hintTp.paint(canvas, Offset((_w - hintTp.width) / 2, hintTop));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (_w * scale).ceil(),
      (h * scale).ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('QR PNG encode failed');
    }
    return byteData.buffer.asUint8List();
  }

  static TextPainter _text(
    String s,
    TextStyle style, {
    required double maxWidth,
    int maxLines = 1,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return tp;
  }
}
