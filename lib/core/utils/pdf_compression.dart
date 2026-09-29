import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Live-Test-16 ISSUE-13 — on-device PDF compression (Android, PdfBox-Android
/// via the "emeal/pdf_compress" channel). App-side only: the server is never
/// asked to compress.
///
/// Returns the compressed bytes when they fit [maxBytes]; null when the PDF
/// cannot reach the budget without unacceptable quality loss, or on a
/// platform without the compressor (iOS keeps the previous behaviour).
/// Throws [PdfUnreadableException] for encrypted / corrupt input.
class PdfUnreadableException implements Exception {
  const PdfUnreadableException();
  @override
  String toString() => 'PDF is password-protected or unreadable';
}

const MethodChannel _channel = MethodChannel('emeal/pdf_compress');

Future<Uint8List?> compressPdfToBudget(Uint8List bytes, int maxBytes) async {
  if (bytes.length <= maxBytes) return bytes;
  if (!Platform.isAndroid) return null;
  try {
    final out = await _channel.invokeMethod<Uint8List>('compress', {
      'bytes': bytes,
      'maxBytes': maxBytes,
    });
    return out;
  } on PlatformException catch (e) {
    if (e.code == 'PDF_UNREADABLE') throw const PdfUnreadableException();
    return null;
  } on MissingPluginException {
    return null;
  }
}
