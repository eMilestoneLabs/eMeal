import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';

import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

// ── EventEntryScreen ───────────────────────────────────────────────────────────

/// Event mode entry selection screen.
///
/// Shown when user taps "Event" on the role select screen.
/// Two paths:
///   1. Event Admin  → login/signup flow with event role context
///   2. Event Guest  → QR scan flow (no account needed)
///
/// Design: Premium card layout with event-brand violet/purple accent.
class EventEntryScreen extends StatefulWidget {
  const EventEntryScreen({super.key});

  @override
  State<EventEntryScreen> createState() => _EventEntryScreenState();
}

class _EventEntryScreenState extends State<EventEntryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _headerFade = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    ));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _onAdminTap() {
    context.push('${RouteNames.login}?role=event',
        extra: const AuthRouteExtra(roleContext: 'event'));
  }

  void _onGuestTap() {
    // Guest flow: event-specific QR join screen (no account needed)
    context.push(RouteNames.eventGuestJoin);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    const accentColor = AppColors.vacation;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      body: Stack(
        children: [
          // ── Ambient glow background ──────────────────────────────────
          _EventBackground(isDark: isDark, size: size),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── App bar ────────────────────────────────────────────
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
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                ),

                // ── Header ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: SlideTransition(
                      position: _headerSlide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Event icon
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.vacation,
                                  AppColors.gradientPurple,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.vacation.withValues(alpha: 0.30),
                                  blurRadius: 20,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.celebration_rounded,
                                size: 28, color: Colors.white),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Event Mode',
                            style: AppTypography.headlineMedium.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'How would you like to continue?',
                            style: AppTypography.bodyMedium.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // ── Entry cards ────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      children: [
                        // Admin card
                        _StaggerCard(
                          index: 0,
                          controller: _animCtrl,
                          child: _EventEntryCard(
                            icon: Icons.manage_accounts_rounded,
                            gradientColors: const [
                              AppColors.vacation,
                              AppColors.gradientPurple,
                            ],
                            title: 'Event Admin',
                            subtitle:
                                'Create & manage your event, guest lists, and meal planning',
                            accentColor: accentColor,
                            tag: 'Account required',
                            tagIcon: Icons.lock_rounded,
                            onTap: _onAdminTap,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Guest card
                        _StaggerCard(
                          index: 1,
                          controller: _animCtrl,
                          child: _EventEntryCard(
                            icon: Icons.qr_code_scanner_rounded,
                            gradientColors: const [
                              Color(0xFFEC4899),
                              Color(0xFFF97316),
                            ],
                            title: 'Event Guest',
                            subtitle:
                                'Scan the event QR code to join instantly — no account needed',
                            accentColor: const Color(0xFFEC4899),
                            tag: 'No signup needed',
                            tagIcon: Icons.bolt_rounded,
                            onTap: _onGuestTap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Bottom note ────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 32, left: 24, right: 24),
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: Text(
                      'Event Guest sessions are temporary and event-specific',
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSmall.copyWith(
                        color: (isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary)
                            .withValues(alpha: 0.55),
                      ),
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

// ── Event entry card ──────────────────────────────────────────────────────────

class _EventEntryCard extends StatefulWidget {
  const _EventEntryCard({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.tag,
    required this.tagIcon,
    required this.onTap,
  });

  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String subtitle;
  final Color accentColor;
  final String tag;
  final IconData tagIcon;
  final VoidCallback onTap;

  @override
  State<_EventEntryCard> createState() => _EventEntryCardState();
}

class _EventEntryCardState extends State<_EventEntryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 200),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.972).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _pressCtrl,
      builder: (_, _) {
        return Transform.scale(
          scale: _scaleAnim.value,
          child: GestureDetector(
            onTapDown: (_) {
              setState(() => _isPressed = true);
              _pressCtrl.forward();
            },
            onTapUp: (_) {
              setState(() => _isPressed = false);
              _pressCtrl.reverse();
              widget.onTap();
            },
            onTapCancel: () {
              setState(() => _isPressed = false);
              _pressCtrl.reverse();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Color.lerp(const Color(0xFF1A2236),
                                widget.accentColor, 0.04)!
                            .withValues(alpha: 0.85)
                        : Color.lerp(
                                Colors.white, widget.accentColor, 0.025)!
                            .withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _isPressed
                          ? widget.accentColor.withValues(alpha: 0.45)
                          : widget.accentColor
                              .withValues(alpha: isDark ? 0.18 : 0.20),
                      width: _isPressed ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentColor
                            .withValues(alpha: 0.16 + 0.10 * _pressCtrl.value),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.25 : 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: widget.gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: widget.gradientColors.first
                                  .withValues(alpha: 0.28),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.18),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Icon(widget.icon, size: 28, color: Colors.white),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Text + tag
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: AppTypography.titleSmall.copyWith(
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              widget.subtitle,
                              style: AppTypography.bodySmall.copyWith(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Tag pill
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.tagIcon,
                                  size: 11,
                                  color: widget.accentColor,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  widget.tag,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: widget.accentColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Arrow
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(
                                alpha: _isPressed ? 0.18 : 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: widget.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Background ────────────────────────────────────────────────────────────────

class _EventBackground extends StatelessWidget {
  const _EventBackground({required this.isDark, required this.size});

  final bool isDark;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.vacation
                        .withValues(alpha: isDark ? 0.14 : 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -50,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFEC4899)
                        .withValues(alpha: isDark ? 0.10 : 0.05),
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

// ── Stagger entrance ──────────────────────────────────────────────────────────

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
    final start = (0.20 + index * 0.15).clamp(0.0, 0.85);
    final end = (start + 0.55).clamp(0.0, 1.0);

    final fade = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOut),
    ));

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
