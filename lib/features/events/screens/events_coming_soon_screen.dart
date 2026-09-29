import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/auth/widgets/powered_by_emilestone.dart';

/// "Events · Coming soon" preview.
///
/// Shown for every Events route while `FeatureFlags.eventsEnabled` is off
/// (see `events_gate.dart`). It only replaces what users see: the Events
/// module's screens, providers and server APIs are untouched.
///
/// Motion: a one-shot staggered entrance plus one slow ambient loop (floating
/// hero, orbiting dishes, badge shimmer, drifting glow). Both controllers are
/// disposed with the screen, pause off-screen via TickerMode, and are skipped
/// entirely when the OS asks for reduced motion.
class EventsComingSoonScreen extends StatefulWidget {
  const EventsComingSoonScreen({super.key});

  @override
  State<EventsComingSoonScreen> createState() => _EventsComingSoonScreenState();
}

class _Feature {
  const _Feature(this.icon, this.title, this.body, this.colors);
  final IconData icon;
  final String title;
  final String body;
  final List<Color> colors;
}

const _orange = Color(0xFFEA580C);
const _pink = Color(0xFFEC4899);
const _violet = Color(0xFF7C3AED);

const _features = <_Feature>[
  _Feature(
    Icons.event_available_rounded,
    'Set up in a minute',
    'Name, date, type and expected guests.',
    [_orange, Color(0xFFF59E0B)],
  ),
  _Feature(
    Icons.qr_code_2_rounded,
    'Guests join by QR',
    'They scan, add their party and they\'re in.',
    [_pink, _violet],
  ),
  _Feature(
    Icons.restaurant_rounded,
    'Every plate counted',
    'Adults, children, veg and non-veg, live.',
    [Color(0xFF059669), Color(0xFF0891B2)],
  ),
  _Feature(
    Icons.tune_rounded,
    'Your menu, your way',
    'Add meal types like Jain or Dessert.',
    [_violet, Color(0xFF4F46E5)],
  ),
  _Feature(
    Icons.ios_share_rounded,
    'Reports in one tap',
    'Share the guest list as PDF or Excel.',
    [Color(0xFF0891B2), Color(0xFF4F46E5)],
  ),
  _Feature(
    Icons.lock_clock_rounded,
    'Private by design',
    'Event data clears itself when you\'re done.',
    [Color(0xFF475569), Color(0xFF0F766E)],
  ),
];

const _orbitEmojis = ['🍽️', '🎉', '🥗', '🍰'];

class _EventsComingSoonScreenState extends State<EventsComingSoonScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _intro.value = 1;
    } else {
      _intro.forward();
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// A fade + rise tied to one slice of the entrance timeline.
  Widget _reveal(double start, double end, Widget child) {
    final curve = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, math.min(end, 1.0), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  bool get _isEventAccount {
    final user = AuthProviderScope.of(context).currentUser;
    return user != null && user.role.isEventGroup;
  }

  void _leave() {
    final auth = AuthProviderScope.of(context);
    if (_isEventAccount) {
      auth.logout();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final user = auth.currentUser;
    final home =
        user == null
            ? RouteNames.roleSelect
            : (user.role.isAdminGroup
                ? RouteNames.adminDashboard
                : RouteNames.studentDashboard);
    GoRouter.maybeOf(context)?.go(home);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final fgSoft =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final bg = isDark ? AppColors.backgroundDark : AppColors.background;
    final eventAccount = _isEventAccount;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Ambient glow, drifting slowly behind everything.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _loop,
              builder:
                  (context, _) => CustomPaint(
                    painter: _GlowPainter(t: _loop.value, isDark: isDark),
                  ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (!eventAccount)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Back',
                      icon: Icon(Icons.arrow_back_rounded, color: fg),
                      onPressed: _leave,
                    ),
                  )
                else
                  const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Column(
                      children: [
                        _reveal(0.0, 0.45, _Hero(loop: _loop)),
                        const SizedBox(height: 18),
                        _reveal(0.12, 0.55, _ComingSoonBadge(loop: _loop)),
                        const SizedBox(height: 14),
                        _reveal(
                          0.18,
                          0.6,
                          ShaderMask(
                            shaderCallback:
                                (r) => const LinearGradient(
                                  colors: [_orange, _pink, _violet],
                                ).createShader(r),
                            child: Text(
                              'Events are coming',
                              textAlign: TextAlign.center,
                              style: AppTypography.headlineMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _reveal(
                          0.24,
                          0.66,
                          Text(
                            'Weddings, parties and functions.\n'
                            'Know exactly how many plates to cook.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: fgSoft,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        for (var i = 0; i < _features.length; i++) ...[
                          _reveal(
                            0.32 + i * 0.07,
                            0.72 + i * 0.07,
                            _FeatureCard(feature: _features[i], isDark: isDark),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 14),
                        _reveal(
                          0.75,
                          1.0,
                          Text(
                            'We\'re adding the finishing touches.',
                            textAlign: TextAlign.center,
                            style: AppTypography.labelMedium.copyWith(
                              color: fgSoft,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: _reveal(
                    0.8,
                    1.0,
                    _GradientButton(
                      label: eventAccount ? 'Sign out' : 'Got it',
                      onTap: _leave,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: PoweredByEmilestone(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating celebration mark with dishes orbiting around it.
class _Hero extends StatelessWidget {
  const _Hero({required this.loop});
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    const size = 196.0;
    const orbit = 80.0;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final t = loop.value * 2 * math.pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Soft orbit ring.
              Container(
                width: orbit * 2,
                height: orbit * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _pink.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                ),
              ),
              for (var i = 0; i < _orbitEmojis.length; i++)
                Transform.translate(
                  offset: Offset(
                    math.cos(t + i * math.pi / 2) * orbit,
                    math.sin(t + i * math.pi / 2) * orbit,
                  ),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          Theme.of(context).brightness == Brightness.dark
                              ? AppColors.surfaceDark
                              : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _orbitEmojis[i],
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(0, math.sin(t) * 6),
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_orange, _pink],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _pink.withValues(
                          alpha: 0.30 + 0.12 * (0.5 + 0.5 * math.sin(t)),
                        ),
                        blurRadius: 32,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.celebration_rounded,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "Coming soon" pill with a light sweep passing across it.
class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge({required this.loop});
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(colors: [_orange, _pink]),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.rocket_launch_rounded,
            size: 15,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            'COMING SOON',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: loop,
      builder: (context, child) {
        final x = -1.5 + 3.0 * loop.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback:
              (r) => LinearGradient(
                begin: Alignment(x - 0.4, 0),
                end: Alignment(x + 0.4, 0),
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.45),
                  Colors.white.withValues(alpha: 0),
                ],
              ).createShader(r),
          child: child,
        );
      },
      child: pill,
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature, required this.isDark});
  final _Feature feature;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final fgSoft =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceDark : Colors.white).withValues(
          alpha: isDark ? 0.85 : 0.92,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border).withValues(
            alpha: 0.7,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: feature.colors.first.withValues(alpha: isDark ? 0.10 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(
                colors: feature.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(feature.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: AppTypography.titleSmall.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  feature.body,
                  style: AppTypography.bodySmall.copyWith(color: fgSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [_orange, _pink]),
          boxShadow: [
            BoxShadow(
              color: _pink.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three soft color glows drifting on slow circular paths.
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.t, required this.isDark});
  final double t;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    final alpha = isDark ? 0.20 : 0.14;
    void glow(Color c, double cx, double cy, double r) {
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }

    final w = size.width, h = size.height;
    glow(
      _orange,
      w * (0.15 + 0.05 * math.cos(a)),
      h * (0.12 + 0.03 * math.sin(a)),
      w * 0.6,
    );
    glow(
      _pink,
      w * (0.9 + 0.05 * math.sin(a)),
      h * (0.35 + 0.04 * math.cos(a)),
      w * 0.55,
    );
    glow(
      _violet,
      w * (0.3 + 0.06 * math.sin(a)),
      h * (0.85 + 0.03 * math.cos(a)),
      w * 0.6,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.t != t || old.isDark != isDark;
}
