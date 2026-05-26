import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/events/widgets/event_qr_scanner_view.dart';

// ── EventGuestJoinScreen ───────────────────────────────────────────────────────

/// Event-specific QR join screen for event guests.
///
/// Two-step flow:
///   Step 1 — Scan event QR code (or enter code manually)
///   Step 2 — Enter guest info (name, adult count, children count)
///
/// Design: Violet/pink event branding. Zero hostel/group wording.
/// After completion → EventGuestDashboard.
class EventGuestJoinScreen extends StatefulWidget {
  /// Optional join code passed directly from a deep-link URL.
  final String? initialCode;

  const EventGuestJoinScreen({super.key, this.initialCode});

  @override
  State<EventGuestJoinScreen> createState() => _EventGuestJoinScreenState();
}

class _EventGuestJoinScreenState extends State<EventGuestJoinScreen>
    with TickerProviderStateMixin {
  // ── Step tracking ──────────────────────────────────────────────────────────
  int _step = 0; // 0 = QR scan, 1 = guest info

  // ── Step 0 — QR ───────────────────────────────────────────────────────────
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();
  bool _showManualEntry = false;
  final bool _isScanning = false;
  String? _codeError;

  // ── Step 1 — Guest info ────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  String? _nameError;
  int _adultCount = 1;
  int _childCount = 0;
  bool _isJoining = false;

  // ── Animations ─────────────────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final AnimationController _stepCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  late final Animation<double> _stepFade;
  late final Animation<double> _pulseFade;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _stepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _entryFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    ));
    _stepFade = CurvedAnimation(
      parent: _stepCtrl,
      curve: Curves.easeOut,
    );
    _pulseFade = Tween<double>(begin: 0.35, end: 0.70).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _entryCtrl.forward();

    // If a code was passed via deep-link, pre-fill and skip to step 1.
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      _codeCtrl.text = widget.initialCode!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _advanceToGuestInfo());
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _stepCtrl.dispose();
    _pulseCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── QR scan ────────────────────────────────────────────────────────────────

  /// Opens the full-screen [EventQrScannerView] and pre-fills the code on
  /// a successful scan, then auto-advances to the guest info step.
  Future<void> _startQrScan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => EventQrScannerView(
          onCodeScanned: (scannedCode) => Navigator.of(context).pop(scannedCode),
        ),
      ),
    );

    if (!mounted || code == null || code.isEmpty) return;
    _codeCtrl.text = code;
    _advanceToGuestInfo();
  }

  void _advanceToGuestInfo() {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _codeError = 'Enter the event code to continue');
      return;
    }
    setState(() {
      _step = 1;
      _codeError = null;
    });
    _stepCtrl.forward(from: 0);
  }

  // ── Join event ─────────────────────────────────────────────────────────────

  Future<void> _joinEvent() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter your name to continue');
      return;
    }
    if (name.length < 2) {
      setState(() => _nameError = 'Please enter a valid name');
      return;
    }

    setState(() => _isJoining = true);
    // Simulate network join — replace with real service call in Phase 3+
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isJoining = false);

    // Pass party data so EventGuestShell can initialise immediately
    context.go(
      RouteNames.eventGuestDashboard,
      extra: EventGuestJoinExtra(
        primaryName: name,
        adultsCount: _adultCount,
        childrenCount: _childCount,
        joinCode: _codeCtrl.text.trim(),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      body: Stack(
        children: [
          _EventGuestBackground(isDark: isDark, size: size),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── App bar ────────────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                        onPressed: () {
                          if (_step > 0) {
                            setState(() => _step = 0);
                            _stepCtrl.reverse();
                          } else {
                            context.pop();
                          }
                        },
                      ),
                      const Spacer(),
                      // Step indicator
                      _StepPill(current: _step, total: 2),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),

                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _step == 0
                        ? _QrStep(
                            key: const ValueKey('qr'),
                            entryFade: _entryFade,
                            entrySlide: _entrySlide,
                            pulseFade: _pulseFade,
                            isDark: isDark,
                            codeCtrl: _codeCtrl,
                            codeFocus: _codeFocus,
                            showManualEntry: _showManualEntry,
                            isScanning: _isScanning,
                            codeError: _codeError,
                            onScan: _startQrScan,
                            onToggleManual: () => setState(
                                () => _showManualEntry = !_showManualEntry),
                            onSubmitCode: _advanceToGuestInfo,
                            onCodeChanged: (_) =>
                                setState(() => _codeError = null),
                          )
                        : _GuestInfoStep(
                            key: const ValueKey('info'),
                            fadeAnim: _stepFade,
                            isDark: isDark,
                            nameCtrl: _nameCtrl,
                            nameFocus: _nameFocus,
                            nameError: _nameError,
                            adultCount: _adultCount,
                            childCount: _childCount,
                            isJoining: _isJoining,
                            onNameChanged: (_) =>
                                setState(() => _nameError = null),
                            onAdultChanged: (v) =>
                                setState(() => _adultCount = v),
                            onChildChanged: (v) =>
                                setState(() => _childCount = v),
                            onJoin: _joinEvent,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 0 — QR Scan ──────────────────────────────────────────────────────────

class _QrStep extends StatelessWidget {
  const _QrStep({
    super.key,
    required this.entryFade,
    required this.entrySlide,
    required this.pulseFade,
    required this.isDark,
    required this.codeCtrl,
    required this.codeFocus,
    required this.showManualEntry,
    required this.isScanning,
    required this.codeError,
    required this.onScan,
    required this.onToggleManual,
    required this.onSubmitCode,
    required this.onCodeChanged,
  });

  final Animation<double> entryFade;
  final Animation<Offset> entrySlide;
  final Animation<double> pulseFade;
  final bool isDark;
  final TextEditingController codeCtrl;
  final FocusNode codeFocus;
  final bool showManualEntry;
  final bool isScanning;
  final String? codeError;
  final VoidCallback onScan;
  final VoidCallback onToggleManual;
  final VoidCallback onSubmitCode;
  final ValueChanged<String> onCodeChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: FadeTransition(
        opacity: entryFade,
        child: SlideTransition(
          position: entrySlide,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // ── Header ───────────────────────────────────────────────────
              _EventTag(isDark: isDark),
              const SizedBox(height: 20),
              Text(
                'Join Event',
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan the QR code shared by your event organizer to join instantly.',
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 36),

              // ── QR Scanner viewport ──────────────────────────────────────
              _QrViewport(
                isDark: isDark,
                pulseFade: pulseFade,
                isScanning: isScanning,
                onScan: onScan,
              ),

              const SizedBox(height: 28),

              // ── Or divider ───────────────────────────────────────────────
              Row(children: [
                Expanded(
                    child: Divider(
                        color: (isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary)
                            .withValues(alpha: 0.25))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'or',
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                    child: Divider(
                        color: (isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary)
                            .withValues(alpha: 0.25))),
              ]),

              const SizedBox(height: 20),

              // ── Manual code toggle ───────────────────────────────────────
              GestureDetector(
                onTap: onToggleManual,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      showManualEntry
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_rounded,
                      size: 16,
                      color: const Color(0xFFEC4899),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      showManualEntry
                          ? 'Hide manual entry'
                          : 'Enter event code manually',
                      style: AppTypography.labelMedium.copyWith(
                        color: const Color(0xFFEC4899),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Manual entry field ───────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: showManualEntry
                    ? Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _GlassInputField(
                              label: 'Event Code',
                              hint: 'e.g. EVT-XXXX-2026',
                              controller: codeCtrl,
                              focusNode: codeFocus,
                              isDark: isDark,
                              errorText: codeError,
                              onChanged: onCodeChanged,
                              onSubmitted: (_) => onSubmitCode(),
                            ),
                            if (codeError != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                codeError!,
                                style: AppTypography.labelSmall.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _GradientButton(
                              label: 'Continue with Code',
                              icon: Icons.arrow_forward_rounded,
                              gradientColors: const [
                                Color(0xFFEC4899),
                                Color(0xFF8B5CF6),
                              ],
                              onTap: onSubmitCode,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step 1 — Guest Info ────────────────────────────────────────────────────────

class _GuestInfoStep extends StatelessWidget {
  const _GuestInfoStep({
    super.key,
    required this.fadeAnim,
    required this.isDark,
    required this.nameCtrl,
    required this.nameFocus,
    required this.nameError,
    required this.adultCount,
    required this.childCount,
    required this.isJoining,
    required this.onNameChanged,
    required this.onAdultChanged,
    required this.onChildChanged,
    required this.onJoin,
  });

  final Animation<double> fadeAnim;
  final bool isDark;
  final TextEditingController nameCtrl;
  final FocusNode nameFocus;
  final String? nameError;
  final int adultCount;
  final int childCount;
  final bool isJoining;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<int> onAdultChanged;
  final ValueChanged<int> onChildChanged;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final totalGuests = adultCount + childCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: FadeTransition(
        opacity: fadeAnim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),

            // ── Header ──────────────────────────────────────────────────────
            _EventTag(isDark: isDark),
            const SizedBox(height: 20),
            Text(
              'Your Details',
              style: AppTypography.headlineMedium.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tell us who\'s joining. You can rename guests later from your dashboard.',
              style: AppTypography.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 32),

            // ── Name field ───────────────────────────────────────────────────
            _GlassInputField(
              label: 'Your Name',
              hint: 'e.g. Rahul Mahanta',
              controller: nameCtrl,
              focusNode: nameFocus,
              isDark: isDark,
              errorText: nameError,
              onChanged: onNameChanged,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
            ),

            const SizedBox(height: 28),

            // ── Guest count section ──────────────────────────────────────────
            Text(
              'How many people are joining?',
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Including yourself',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),

            _CounterRow(
              icon: Icons.person_rounded,
              label: 'Adults',
              count: adultCount,
              min: 1,
              max: 20,
              isDark: isDark,
              onChanged: onAdultChanged,
              accentColor: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 12),
            _CounterRow(
              icon: Icons.child_care_rounded,
              label: 'Children',
              count: childCount,
              min: 0,
              max: 10,
              isDark: isDark,
              onChanged: onChildChanged,
              accentColor: const Color(0xFFEC4899),
            ),

            const SizedBox(height: 24),

            // ── Summary chip ─────────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF8B5CF6)
                      .withValues(alpha: isDark ? 0.25 : 0.18),
                ),
              ),
              child: Row(children: [
                const Icon(
                  Icons.groups_rounded,
                  size: 20,
                  color: Color(0xFF8B5CF6),
                ),
                const SizedBox(width: 10),
                Text(
                  '$totalGuests ${totalGuests == 1 ? 'person' : 'people'} joining  ·  $adultCount ${adultCount == 1 ? 'adult' : 'adults'}${childCount > 0 ? '  ·  $childCount ${childCount == 1 ? 'child' : 'children'}' : ''}',
                  style: AppTypography.labelMedium.copyWith(
                    color: const Color(0xFF8B5CF6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 32),

            // ── Join button ──────────────────────────────────────────────────
            _GradientButton(
              label: isJoining ? 'Joining Event…' : 'Join Event',
              icon: isJoining ? null : Icons.celebration_rounded,
              gradientColors: const [
                Color(0xFF8B5CF6),
                Color(0xFFEC4899),
              ],
              isLoading: isJoining,
              onTap: isJoining ? () {} : onJoin,
            ),

            const SizedBox(height: 20),
            Text(
              'No account needed. Your session is temporary and event-specific.',
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(
                color: (isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiary)
                    .withValues(alpha: 0.55),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── QR Viewport ───────────────────────────────────────────────────────────────

class _QrViewport extends StatelessWidget {
  const _QrViewport({
    required this.isDark,
    required this.pulseFade,
    required this.isScanning,
    required this.onScan,
  });

  final bool isDark;
  final Animation<double> pulseFade;
  final bool isScanning;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: isScanning ? null : onScan,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: isDark
                ? const Color(0xFF1A2236).withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.85),
            border: Border.all(
              color: const Color(0xFF8B5CF6)
                  .withValues(alpha: isScanning ? 0.80 : 0.35),
              width: isScanning ? 2.0 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6)
                    .withValues(alpha: isScanning ? 0.30 : 0.12),
                blurRadius: isScanning ? 28 : 16,
                spreadRadius: isScanning ? 2 : 0,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Corner brackets
              ..._buildCorners(),

              // Center content
              if (isScanning)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF8B5CF6)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Scanning…',
                      style: AppTypography.labelMedium.copyWith(
                        color: const Color(0xFF8B5CF6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else
                AnimatedBuilder(
                  animation: pulseFade,
                  builder: (_, _) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: pulseFade.value,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF8B5CF6)
                                .withValues(alpha: 0.12),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 36,
                            color: Color(0xFF8B5CF6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Tap to Scan',
                        style: AppTypography.labelMedium.copyWith(
                          color: const Color(0xFF8B5CF6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Point camera at event QR',
                        style: AppTypography.labelSmall.copyWith(
                          color: (isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiary)
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCorners() {
    const color = Color(0xFF8B5CF6);
    const size = 22.0;
    const thickness = 3.0;
    const radius = 6.0;

    Widget corner({
      double? top,
      double? bottom,
      double? left,
      double? right,
      required bool flipX,
      required bool flipY,
    }) {
      return Positioned(
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(
              flipX ? -1 : 1, flipY ? -1 : 1, 1),
          child: const CustomPaint(
            size: Size(size, size),
            painter: _CornerPainter(
                color: color, thickness: thickness, radius: radius),
          ),
        ),
      );
    }

    return [
      corner(top: 12, left: 12, flipX: false, flipY: false),
      corner(top: 12, right: 12, flipX: true, flipY: false),
      corner(bottom: 12, left: 12, flipX: false, flipY: true),
      corner(bottom: 12, right: 12, flipX: true, flipY: true),
    ];
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.color,
    required this.thickness,
    required this.radius,
  });

  final Color color;
  final double thickness;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(radius, 0)
      ..arcToPoint(Offset(0, radius),
          radius: Radius.circular(radius), clockwise: false)
      ..lineTo(0, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.thickness != thickness ||
      oldDelegate.radius != radius;
}

// ── Counter Row ───────────────────────────────────────────────────────────────

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.min,
    required this.max,
    required this.isDark,
    required this.onChanged,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final int count;
  final int min;
  final int max;
  final bool isDark;
  final ValueChanged<int> onChanged;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1A2236).withValues(alpha: 0.80)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: isDark ? 0.18 : 0.14),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.titleSmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              // Decrement
              _CountBtn(
                icon: Icons.remove_rounded,
                color: accentColor,
                isDark: isDark,
                enabled: count > min,
                onTap: () => onChanged(count - 1),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 28,
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: AppTypography.numericSmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Increment
              _CountBtn(
                icon: Icons.add_rounded,
                color: accentColor,
                isDark: isDark,
                enabled: count < max,
                onTap: () => onChanged(count + 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBtn extends StatelessWidget {
  const _CountBtn({
    required this.icon,
    required this.color,
    required this.isDark,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final bool isDark;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: isDark ? 0.20 : 0.12)
              : (isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary)
                  .withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.30)
                : (isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiary)
                    .withValues(alpha: 0.15),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? color
              : (isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary)
                  .withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

// ── Gradient Button ───────────────────────────────────────────────────────────

class _GradientButton extends StatefulWidget {
  const _GradientButton({
    required this.label,
    required this.gradientColors,
    required this.onTap,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  final IconData? icon;
  final bool isLoading;

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 180),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Transform.scale(
        scale: _scale.value,
        child: GestureDetector(
          onTapDown: (_) => _ctrl.forward(),
          onTapUp: (_) {
            _ctrl.reverse();
            widget.onTap();
          },
          onTapCancel: () => _ctrl.reverse(),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.gradientColors,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: widget.gradientColors.first.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: widget.isLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.label,
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (widget.icon != null) ...[
                        const SizedBox(width: 8),
                        Icon(widget.icon, size: 18, color: Colors.white),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Glass Input Field ──────────────────────────────────────────────────────────

class _GlassInputField extends StatefulWidget {
  const _GlassInputField({
    required this.label,
    required this.isDark,
    this.hint,
    this.controller,
    this.focusNode,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
  });

  final String label;
  final String? hint;
  final bool isDark;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;

  @override
  State<_GlassInputField> createState() => _GlassInputFieldState();
}

class _GlassInputFieldState extends State<_GlassInputField>
    with SingleTickerProviderStateMixin {
  late final FocusNode _focus;
  late final AnimationController _ctrl;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _focus.addListener(() {
      setState(() => _hasFocus = _focus.hasFocus);
      if (_focus.hasFocus) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError =
        widget.errorText != null && widget.errorText!.isNotEmpty;
    final accentColor = const Color(0xFF8B5CF6);
    final borderColor = hasError
        ? Theme.of(context).colorScheme.error
        : _hasFocus
            ? accentColor
            : accentColor.withValues(alpha: widget.isDark ? 0.22 : 0.16);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? const Color(0xFF1A2236).withValues(alpha: 0.80)
                  : Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: _hasFocus && !hasError ? 1.8 : 1.2,
              ),
              boxShadow: _hasFocus
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(
                            alpha: 0.12 + 0.08 * _ctrl.value),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              textCapitalization: widget.textCapitalization,
              textInputAction: widget.textInputAction,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: AppTypography.bodyLarge.copyWith(
                color: widget.isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                labelStyle: AppTypography.bodyMedium.copyWith(
                  color: hasError
                      ? Theme.of(context).colorScheme.error
                      : _hasFocus
                          ? accentColor
                          : (widget.isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary)
                              .withValues(alpha: 0.75),
                ),
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: (widget.isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary)
                      .withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Event Tag ─────────────────────────────────────────────────────────────────

class _EventTag extends StatelessWidget {
  const _EventTag({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration_rounded,
              size: 13, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            'Event Guest',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step Pill ─────────────────────────────────────────────────────────────────

class _StepPill extends StatelessWidget {
  const _StepPill({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: const Color(0xFF8B5CF6)
              .withValues(alpha: isDark ? 0.30 : 0.20),
        ),
      ),
      child: Text(
        'Step ${current + 1} of $total',
        style: AppTypography.labelSmall.copyWith(
          color: const Color(0xFF8B5CF6),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Background ────────────────────────────────────────────────────────────────

class _EventGuestBackground extends StatelessWidget {
  const _EventGuestBackground({required this.isDark, required this.size});

  final bool isDark;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8B5CF6)
                        .withValues(alpha: isDark ? 0.14 : 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFEC4899)
                        .withValues(alpha:                        isDark ? 0.12 : 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
