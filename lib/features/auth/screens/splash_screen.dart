import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/models/auth_state.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

// ── SplashScreen ───────────────────────────────────────────────────────────────

/// Flagship first-impression screen — shown for ~1.8s before routing to
/// [RoleSelectScreen].
///
/// Design language: premium SaaS / fintech startup.
///   Dark  → deep navy-black background, indigo glow orbs, gradient logo.
///   Light → soft pearl-lavender background, subtle indigo gradients.
///
/// Animation sequence:
///   0ms   → background gradient fades in
///   150ms → logo icon scales + fades in with glow
///   500ms → brand name slides up + fades in
///   700ms → tagline fades in
///   900ms → shimmer dots animate
///   1800ms → navigate to /role-select
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Controllers ─────────────────────────────────────────────────────────────
  late final AnimationController _bgCtrl;
  late final AnimationController _logoCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _dotsCtrl;

  // ── Animations ──────────────────────────────────────────────────────────────
  late final Animation<double> _bgFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoGlow;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<double> _taglineFade;
  late final Animation<double> _dotsFade;

  bool _navigated = false;
  bool _introDone = false;

  @override
  void initState() {
    super.initState();

    // Background fade
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bgFade = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeOut);

    // Logo reveal: scale from 0.72 → 1.0, fade in
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );
    _logoFade = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _logoGlow = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );

    // Text: title + tagline
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    ));
    _titleFade = CurvedAnimation(
      parent: _textCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _taglineFade = CurvedAnimation(
      parent: _textCtrl,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    // Dots indicator
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _dotsFade = CurvedAnimation(parent: _dotsCtrl, curve: Curves.easeOut);

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Stage 1: Background
    _bgCtrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // Stage 2: Logo
    _logoCtrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    // Stage 3: Text
    _textCtrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Stage 4: Dots
    _dotsCtrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 900));

    // Intro finished. Navigate now if the session has resolved; otherwise wait
    // — didChangeDependencies retries the moment auth state arrives.
    _introDone = true;
    _navigate();
  }

  void _navigate() {
    if (_navigated || !mounted) return;
    final auth = AuthProviderScope.of(context);
    // Wait until the persisted session resolves. While AuthUnknown the router
    // keeps us on splash; navigating now would flash the role-select screen for
    // a logged-in user before their dashboard loads (cold-boot regression).
    if (auth.state is AuthUnknown) return;
    // Authenticated users are routed to their dashboard by the router's redirect
    // (splash is an auth route) — never bounce them through role-select.
    if (auth.isAuthenticated) return;
    _navigated = true;
    context.go(RouteNames.roleSelect);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AuthProviderScope is an InheritedNotifier, so this re-runs when the
    // session resolves (AuthUnknown -> authenticated/unauthenticated). Re-decide
    // the post-intro navigation once the real auth state is known.
    AuthProviderScope.of(context);
    if (_introDone) _navigate();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);

    return GestureDetector(
      onTap: _navigate,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.splashDark : AppColors.splashLight,
        body: FadeTransition(
          opacity: _bgFade,
          child: Stack(
            children: [
              // ── Layered gradient background ──────────────────────────────
              _SplashBackground(isDark: isDark, size: size),

              // ── Center content ───────────────────────────────────────────
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    ScaleTransition(
                      scale: _logoScale,
                      child: FadeTransition(
                        opacity: _logoFade,
                        child: _LogoMark(glowAnim: _logoGlow, isDark: isDark),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Brand name
                    SlideTransition(
                      position: _titleSlide,
                      child: FadeTransition(
                        opacity: _titleFade,
                        child: Text(
                          'MealAttend',
                          style: AppTypography.displaySmall.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Tagline
                    FadeTransition(
                      opacity: _taglineFade,
                      child: Text(
                        'Meals · Attendance · Groups',
                        style: AppTypography.bodyMedium.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 56),

                    // Animated dots
                    FadeTransition(
                      opacity: _dotsFade,
                      child: _PulseDots(isDark: isDark),
                    ),
                  ],
                ),
              ),

              // ── Bottom tagline ────────────────────────────────────────────
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'Smart Meal & Attendance Management',
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSmall.copyWith(
                      color: (isDark
                              ? AppColors.textTertiaryDark
                              : AppColors.textTertiary)
                          .withValues(alpha: 0.6),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Layered background ────────────────────────────────────────────────────────

class _SplashBackground extends StatelessWidget {
  const _SplashBackground({required this.isDark, required this.size});

  final bool isDark;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          // Base gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [AppColors.splashDark, AppColors.splashDarkMid]
                    : [AppColors.splashLight, AppColors.splashLightMid],
              ),
            ),
          ),

          // Top-right indigo glow orb
          Positioned(
            top: -size.height * 0.15,
            right: -size.width * 0.2,
            child: Container(
              width: size.width * 0.75,
              height: size.width * 0.75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),

          // Bottom-left purple/violet glow orb
          Positioned(
            bottom: -size.height * 0.12,
            left: -size.width * 0.25,
            child: Container(
              width: size.width * 0.80,
              height: size.width * 0.80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.gradientViolet
                        .withValues(alpha: isDark ? 0.14 : 0.07),
                    AppColors.gradientViolet.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),

          // Center subtle radial — gives depth
          Center(
            child: Container(
              width: size.width * 1.2,
              height: size.width * 1.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: isDark ? 0.06 : 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Fine diagonal noise overlay (subtle texture)
          if (isDark)
            SizedBox.expand(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.gradientPurple.withValues(alpha: 0.04),
                      Colors.transparent,
                      AppColors.primary.withValues(alpha: 0.03),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Logo mark ─────────────────────────────────────────────────────────────────

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.glowAnim, required this.isDark});

  final Animation<double> glowAnim;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowAnim,
      builder: (_, _) {
        final glowOpacity = glowAnim.value;
        return Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.gradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              // Primary glow
              BoxShadow(
                color: AppColors.primary
                    .withValues(alpha: 0.45 * glowOpacity),
                blurRadius: 40,
                spreadRadius: 4,
                offset: const Offset(0, 8),
              ),
              // Soft ambient
              BoxShadow(
                color: AppColors.gradientViolet
                    .withValues(alpha: 0.20 * glowOpacity),
                blurRadius: 60,
                spreadRadius: 8,
                offset: const Offset(0, 12),
              ),
              // Inner highlight
              BoxShadow(
                color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.15),
                blurRadius: 1,
                spreadRadius: -2,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Subtle inner gradient overlay for depth
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              const Icon(
                Icons.restaurant_rounded,
                size: 44,
                color: Colors.white,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Pulse dots loading indicator ──────────────────────────────────────────────

class _PulseDots extends StatefulWidget {
  const _PulseDots({required this.isDark});
  final bool isDark;

  @override
  State<_PulseDots> createState() => _PulseDotsState();
}

class _PulseDotsState extends State<_PulseDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
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
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot offset by 0.25
            final phase = ((_ctrl.value - i * 0.25) % 1.0);
            final scale = 0.6 + 0.4 * _triangle(phase);
            final opacity = 0.3 + 0.7 * _triangle(phase);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: opacity),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  /// Triangle wave: peaks at 0.5, returns to 0 at 0 and 1.
  double _triangle(double t) {
    if (t < 0.5) return t * 2;
    return (1 - t) * 2;
  }
}
