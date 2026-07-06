import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/utils/qr_payload_parser.dart';

// ── QrScannerView ─────────────────────────────────────────────────────────────

/// Full-screen QR scanner widget for the group join flow.
///
/// Features:
/// - Real camera preview via [mobile_scanner]
/// - Animated scan-frame overlay
/// - Flashlight toggle button
/// - Camera permission denied state with guidance
/// - Single-scan mode (auto-pauses after successful detection)
/// - Lifecycle-safe: pauses scanner when widget is inactive
///
/// Usage — push as a full-screen route:
/// ```dart
/// final code = await Navigator.of(context).push<String>(
///   MaterialPageRoute(
///     fullscreenDialog: true,
///     builder: (_) => QrScannerView(
///       onCodeScanned: (code) => Navigator.of(context).pop(code),
///     ),
///   ),
/// );
/// ```
class QrScannerView extends StatefulWidget {
  const QrScannerView({
    super.key,
    required this.onCodeScanned,
  });

  /// Called once with the extracted join code when a valid QR is detected.
  /// The caller is responsible for popping the route after receiving the code.
  final ValueChanged<String> onCodeScanned;

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _flashOn = false;
  bool _scanned = false; // Guard: only fire onCodeScanned once
  bool _picking = false; // Issue 9: gallery pick in progress
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
    _processRawValue(capture.barcodes.firstOrNull?.rawValue);
  }

  /// Shared decode path for BOTH the live camera and a gallery-picked image
  /// (Issue 9). [notFoundMessage] tailors the error when nothing decodes.
  void _processRawValue(
    String? rawValue, {
    String notFoundMessage = 'Not a valid MealAttend group QR. Try again.',
  }) {
    if (_scanned) return;
    if (rawValue == null) {
      _flashError(notFoundMessage);
      return;
    }

    // Use QrPayloadParser to support structured `group:{id}:{token}` format
    // as well as legacy plain codes and deep-link URLs.
    final payload = QrPayloadParser.parseGroupQr(rawValue);
    if (payload == null) {
      _flashError('Not a valid MealAttend group QR. Try again.');
      return;
    }

    // Valid payload — pause scanner and notify caller with the join token
    _scanned = true;
    _controller.stop();
    widget.onCodeScanned(payload.joinToken);
  }

  void _flashError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _errorMessage = null);
    });
  }

  /// Issue 9: pick a saved QR image from the gallery and decode it — for users
  /// who received the invite QR as a photo/screenshot rather than in person.
  Future<void> _pickFromGallery() async {
    if (_scanned || _picking) return;
    setState(() => _picking = true);
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return; // user cancelled
      final result = await _controller.analyzeImage(picked.path);
      if (!mounted) return;
      _processRawValue(
        result?.barcodes.firstOrNull?.rawValue,
        notFoundMessage: 'No QR code found in that image. Try another.',
      );
    } catch (_) {
      _flashError('Could not read that image. Try another.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
          'Scan Group QR',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: false,
        actions: [
          // Issue 9: pick a QR image from the gallery (received as a photo).
          IconButton(
            onPressed: _picking ? null : _pickFromGallery,
            tooltip: 'Pick QR from gallery',
            icon: _picking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.photo_library_outlined,
                    color: Colors.white),
          ),
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
          // ── Camera feed ────────────────────────────────────────────────────
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

          // ── Scan-frame overlay ─────────────────────────────────────────────
          const _ScanFrameOverlay(),

          // ── Bottom instruction banner ──────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBanner(
              errorMessage: _errorMessage,
              colorScheme: colorScheme,
              onPickFromGallery: _picking ? null : _pickFromGallery,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan frame overlay ────────────────────────────────────────────────────────

/// Draws a semi-transparent overlay with a transparent scan window in the
/// center, plus four corner brackets to guide the user.
class _ScanFrameOverlay extends StatelessWidget {
  const _ScanFrameOverlay();

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
        cornerColor: AppColors.primary,
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
  const _BottomBanner({
    required this.errorMessage,
    required this.colorScheme,
    this.onPickFromGallery,
  });

  final String? errorMessage;
  final ColorScheme colorScheme;
  final VoidCallback? onPickFromGallery;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: errorMessage != null
          ? _ErrorBanner(message: errorMessage!, key: const ValueKey('err'))
          : _HintBanner(
              key: const ValueKey('hint'),
              onPickFromGallery: onPickFromGallery,
            ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({super.key, this.onPickFromGallery});

  final VoidCallback? onPickFromGallery;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_scanner_rounded,
              color: Colors.white, size: 28),
          const SizedBox(height: 10),
          const Text(
            'Point your camera at the group QR code',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'The code will be detected automatically',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
          // Issue 9: obvious gallery entry for QR photos/screenshots.
          if (onPickFromGallery != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onPickFromGallery,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Choose from gallery'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
              ),
            ),
          ],
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

/// Shown when the camera cannot be opened (permission denied, no hardware, etc.)
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
                    backgroundColor: AppColors.primary,
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
