import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';

import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/widgets/role_entry_card.dart';

// ── RoleSelectScreen ───────────────────────────────────────────────────────────

/// Premium workspace-selection entry screen.
///
/// Three role cards — each feels like choosing a distinct product experience.
/// Design: cinematic multi-blob animated background, staggered card entrance
/// with easeOutBack spring, gradient scaffold background, vivid color palette.
class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen>
    with TickerProviderStateMixin {
  // ── Entrance animation ─────────────────────────────────────────────────────
  late final AnimationController _animCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  // ── Floating blob animation ────────────────────────────────────────────────
  late final AnimationController _blobCtrl;
  late final Animation<double> _blobFloat;

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _headerFade = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    ));
    _animCtrl.forward();

    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat(reverse: true);
    _blobFloat = CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _blobCtrl.dispose();
    super.dispose();
  }

  void _onStudentTap() {
    context.push('${RouteNames.login}?role=student',
        extra: const AuthRouteExtra(roleContext: 'student'));
  }

  void _onAdminTap() {
    context.push('${RouteNames.login}?role=admin',
        extra: const AuthRouteExtra(roleContext: 'admin'));
  }

  void _onEventTap() {
    context.push(RouteNames.eventEntry);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF060B17), const Color(0xFF0C1428)]
                : [const Color(0xFFF0F4FF), const Color(0xFFE8EDFF)],
          ),
        ),
        child: Stack(
          children: [
            // ── Animated blob background ───────────────────────────────
            // RepaintBoundary isolates the blob animation layer so each frame
            // only re-rasterizes the background — not the card content above it.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _blobFloat,
                builder: (_, _) => _RoleSelectBackground(
                  isDark: isDark,
                  size: size,
                  blobValue: _blobFloat.value,
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // ── Header ────────────────────────────────────────────
                  FadeTransition(
                    opacity: _headerFade,
                    child: SlideTransition(
                      position: _headerSlide,
                      child: const _BrandHeader(),
                    ),
                  ),

                  // ── Cards ──────────────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          _StaggerCard(
                            index: 0,
                            controller: _animCtrl,
                            child: RoleEntryCard(
                              icon: Icons.school_rounded,
                              gradientColors: const [
                                Color(0xFF4F46E5), // deep indigo
                                Color(0xFF06B6D4), // cyan
                              ],
                              title: 'Student / Guest',
                              subtitle:
                                  'Join your group, track meals & attendance',
                              accentColor: const Color(0xFF4F46E5),
                              onTap: _onStudentTap,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _StaggerCard(
                            index: 1,
                            controller: _animCtrl,
                            child: RoleEntryCard(
                              icon: Icons.dashboard_customize_rounded,
                              gradientColors: const [
                                Color(0xFF059669), // emerald
                                Color(0xFF0891B2), // deep sky
                              ],
                              title: 'Admin / Manager',
                              subtitle:
                                  'Manage your organization, meals & reports',
                              accentColor: const Color(0xFF059669),
                              onTap: _onAdminTap,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _StaggerCard(
                            index: 2,
                            controller: _animCtrl,
                            child: RoleEntryCard(
                              icon: Icons.celebration_rounded,
                              gradientColors: const [
                                Color(0xFFEA580C), // vibrant orange
                                Color(0xFFEC4899), // hot pink
                              ],
                              title: 'Event',
                              subtitle:
                                  'Create an event or join as a guest',
                              accentColor: const Color(0xFFEA580C),
                              badge: 'Quick Join',
                              onTap: _onEventTap,
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),

                  // ── Footer ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: FadeTransition(
                      opacity: _headerFade,
                      child: Text(
                        'Smart Meal & Attendance Management',
                        style: AppTypography.labelSmall.copyWith(
                          color: (isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiary)
                              .withValues(alpha: 0.50),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animated blob background ───────────────────────────────────────────────────

class _RoleSelectBackground extends StatelessWidget {
  const _RoleSelectBackground({
    required this.isDark,
    required this.size,
    required this.blobValue,
  });

  final bool isDark;
  final Size size;

  /// 0..1 — each blob uses a different phase for organic motion.
  final double blobValue;

  @override
  Widget build(BuildContext context) {
    // Independent drift per blob
    final t0 = blobValue;              // primary (top-right) — full cycle
    final t1 = 1.0 - blobValue;

    return Stack(
      children: [
        // Top-right primary orb
        Positioned(
          top: -100 + 30 * t0,
          right: -90 + 20 * (1 - t0),
          child: Container(
            width: isDark ? 320 : 300,
            height: isDark ? 320 : 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF4F46E5)
                      .withValues(alpha: isDark ? 0.22 + 0.08 * t0 : 0.12 + 0.04 * t0),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Bottom-left violet orb
        Positioned(
          bottom: -90 + 25 * t1,
          left: -80 + 20 * (1 - t1),
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF8B5CF6)
                      .withValues(alpha: isDark ? 0.18 + 0.06 * t1 : 0.10 + 0.03 * t1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Mid-screen accent orb
        Positioned(
          top: size.height * 0.40 + 18 * blobValue,
          left: size.width * 0.20 + 10 * (1 - blobValue),
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFEA580C)
                      .withValues(alpha: isDark ? 0.10 + 0.04 * t0 : 0.06 + 0.02 * t0),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Brand header ───────────────────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // App icon badge
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Smart Meal',
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your workspace',
            style: AppTypography.bodyMedium.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark.withValues(alpha: 0.80)
                  : AppColors.textSecondary,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Stagger card ───────────────────────────────────────────────────────────

/// Wraps a card in a staggered fade+slide entrance animation.
/// Each card's interval is offset by [index] * 0.12 so they cascade in.
class _StaggerCard extends StatelessWidget {
  const _StaggerCard({
    required this.index,
    required this.controller,
    required this.child,
  });

  final int index;
  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double start = 0.25 + index * 0.10;
    final double end = (start + 0.45).clamp(0.0, 1.0);

    final fade = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    ));

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: child,
      ),
    );
  }
}
