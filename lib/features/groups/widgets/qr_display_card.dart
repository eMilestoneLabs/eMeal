import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smart_meal_management/core/utils/qr_payload_parser.dart';
import 'package:smart_meal_management/core/utils/qr_share.dart';

/// Real scannable QR display card for group joining.
///
/// Encodes [groupId] + [joinCode] via [QrPayloadParser.encodeGroupQr] into a
/// structured `group:<id>:<token>` payload.  Students scan this with
/// [QrScannerView]; [QrPayloadParser] decodes it on the other side.
///
/// The complete QR card (QR + code) can be shared as an image via the share
/// button; falls back to text share when capture fails.
class QrDisplayCard extends StatefulWidget {
  const QrDisplayCard({
    super.key,
    required this.groupId,
    required this.joinCode,
    required this.groupName,
  });

  final String groupId;
  final String joinCode;
  final String groupName;

  @override
  State<QrDisplayCard> createState() => _QrDisplayCardState();
}

class _QrDisplayCardState extends State<QrDisplayCard> {
  final GlobalKey _qrKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareQrImage() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Issue 3: render the branded QR straight to PNG (no widget-capture race),
      // so WhatsApp receives the premium QR image — not just the text fallback.
      final qrData = QrPayloadParser.encodeGroupQr(
        groupId: widget.groupId,
        joinToken: widget.joinCode,
      );
      await QrShare.shareGroupQr(
        qrData: qrData,
        joinCode: widget.joinCode,
        groupName: widget.groupName,
        text: 'Join "${widget.groupName}" on MealAttend!\n\n'
            'Use code: ${widget.joinCode}\n\n'
            'Open the app → Scan QR or enter code to join.',
        subject: 'Join ${widget.groupName}',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Encode as structured payload — same format as admin_group_detail_screen.
    final qrData = QrPayloadParser.encodeGroupQr(
      groupId: widget.groupId,
      joinToken: widget.joinCode,
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            widget.groupName,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Real scannable QR code — white background required for scanner
          // contrast on both light and dark themes. RepaintBoundary lets the
          // complete card be captured and shared as an image.
          RepaintBoundary(
            key: _qrKey,
            child: Container(
              width: 196,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 180,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black87,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.joinCode,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Code display + copy
          Text(
            'Join Code',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _copyCode(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.joinCode,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _sharing ? null : _shareQrImage,
            icon: const Icon(Icons.share_rounded, size: 18),
            label: Text(_sharing ? 'Sharing…' : 'Share QR image'),
          ),
          const SizedBox(height: 4),
          Text(
            'Share this code or QR with members to join.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.joinCode));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Join code "${widget.joinCode}" copied'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}
