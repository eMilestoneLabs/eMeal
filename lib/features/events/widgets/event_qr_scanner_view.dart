import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/utils/qr_payload_parser.dart';

// ── EventQrScannerView ────────────────────────────────────────────────────────

/// Full-screen QR scanner widget for the event guest join flow.
///
/// Identical architecture to [QrScannerView] (groups/widgets) but validates
/// the scanned value as an event QR via [QrPayloadParser.parseEventQr()].
///
/// Features:
/// - Real camera preview via [mobile_scanner]
/// - Animated scan-frame overlay (violet/pink event branding)
/// - Flashlight toggle
/// - Camera permission denied state with guidance
/// - Single-scan guard (auto-pauses after successful detection)
/// - Lifecycle-safe: pauses scanner when widget is inactive
///
/// Usage:
/// ```dart
/// final code = await Navigator.of(context).push<String>(
///   MaterialPageRoute(
///     fullscreenDialog: true,
///     builder: (_) => EventQrScannerView(
///       onCodeScanned: (code) => Navigator.of(context).pop(code),
///     ),
///   ),
/// );
/// ```
class EventQrScannerView extends StatefulWidget {
  const EventQrScannerView({
    super.key,
    required this.onCodeScanned,
  });

  /// Called once with the extracted join token when a valid event QR is detected.
  /// The caller is responsible for popping the route after receiving the token.
  final ValueChanged<String> onCodeScanned;

  @override
  State<EventQrScannerView> createState() => _EventQrScannerViewState();
}

class _EventQrScannerViewState extends State<EventQrScannerView>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _flashOn = false;
  bool _scanned = false; // Guard: only fire onCodeScanned once
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_scanned) _controller.start();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _controller.stop();
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    // Use QrPayloadParser to validate event QR payload.
    final payload = QrPayloadParser.parseEventQr(rawValue);
    if (payload == null) {
      // Not a valid event QR — show user-friendly error and resume scanning.
      if (mounted) {
        setState(() =>
            _errorMessage = 'Not a valid event QR code. Try again.');
      }
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _errorMessage = null);
      });
      return;
    }

    // Valid payload — pause scanner and notify caller with the join token.
    _scanned = true;
    _controller.stop();
    widget.onCodeScanned(payload.joinToken);
  }

  Future<void> _toggleFlash() async {
    await _controller.toggleTorch();
    if (mounted) setState(() => _flashOn = !_flashOn);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Scan Event QR',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: false,
        actions: [
          // Flash toggle
          IconButton(
            onPressed: _toggleFlash,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                key: ValueKey(_flashOn),
                color: _flashOn ? Colors.amber : Colors.white,
              ),
            ),
            tooltip: _flashOn ? 'Turn off flash' : 'Turn on flash',
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Camera feed ───────────────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return _CameraErrorView(
                error: error,
                colorScheme: colorScheme,
              );
            },
          ),

          // ── Scan-frame overlay (violet branding) ───────────────────────
          const _EventScanFrameOverlay(),

          // ── Bottom instruction / error banner ──────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBanner(errorMessage: _errorMessage),
          ),
        ],
      ),
    );
  }
}

// ── Scan frame overlay ────────────────────────────────────────────────────────

class _EventScanFrameOverlay extends StatelessWidget {
  const _EventScanFrameOverlay();

  static const double _frameSize = 240.0;
  static const double _cornerLen = 28.0;
  static const double _cornerWidth = 3.5;

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _OverlayPainter(
        frameSize: _frameSize,
        cornerLength: _cornerLen,
        cornerWidth: _cornerWidth,
        // Violet accent for event branding
        cornerColor: Color(0xFF8B5CF6),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  const _OverlayPainter({
    required this.frameSize,
    required this.cornerLength,
    required this.cornerWidth,
    required this.cornerColor,
  });

  final double frameSize;
  final double cornerLength;
  final double cornerWidth;
  final Color cornerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final half = frameSize / 2;

    final left = cx - half;
    final top = cy - half;
    final right = cx + half;
    final bottom = cy + half;

    // Semi-transparent dark overlay with transparent cutout
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, right, bottom),
        const Radius.circular(12),
      ))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Corner brackets
    final cornerPaint = Paint()
      ..color = cornerColor
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLength)
        ..lineTo(left, top)
        ..lineTo(left + cornerLength, top),
      cornerPaint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLength, top)
        ..lineTo(right, top)
        ..lineTo(right, top + cornerLength),
      cornerPaint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - cornerLength)
        ..lineTo(left, bottom)
        ..lineTo(left + cornerLength, bottom),
      cornerPaint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLength, bottom)
        ..lineTo(right, bottom)
        ..lineTo(right, bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.cornerColor != cornerColor || old.frameSize != frameSize;
}

// ── Bottom banner ─────────────────────────────────────────────────────────────

class _BottomBanner extends StatelessWidget {
  const _BottomBanner({required this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: errorMessage != null
          ? _ErrorBanner(message: errorMessage!, key: const ValueKey('err'))
          : const _HintBanner(key: ValueKey('hint')),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration_rounded, color: Color(0xFF8B5CF6), size: 28),
          SizedBox(height: 10),
          Text(
            'Point your camera at the event QR code',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'The code will be detected automatically',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Camera error view ─────────────────────────────────────────────────────────

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({
    required this.error,
    required this.colorScheme,
  });

  final MobileScannerException error;
  final ColorScheme colorScheme;

  String get _message {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Camera permission is required to scan QR codes.\n\n'
            'Please enable camera access in Settings → App Permissions.';
      case MobileScannerErrorCode.unsupported:
        return 'QR scanning is not supported on this device.';
      default:
        return 'Camera could not be started. Please restart the app.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? Icons.camera_alt_outlined
                    : Icons.error_outline_rounded,
                color: Colors.white54,
                size: 56,
              ),
              const SizedBox(height: 20),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              if (error.errorCode ==
                  MobileScannerErrorCode.permissionDenied) ...[
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Go back'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
