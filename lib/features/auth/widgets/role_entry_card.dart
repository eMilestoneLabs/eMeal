import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

// ── RoleEntryCard ──────────────────────────────────────────────────────────────

/// Premium glassmorphism role selection card.
///
/// Visual hierarchy:
///   • Left: gradient icon container with subtle inner highlight
///   • Center: title (bold) + subtitle (secondary)
///   • Right: animated arrow container
///
/// Tap behaviour:
///   • Scale press animation: 0.97 → 1.0 with spring easing
///   • Border glows to accentColor on press
///   • Calls [onTap] on release
///
/// Uses BackdropFilter blur for glass effect — parent must not clip this.
class RoleEntryCard extends StatefulWidget {
  const RoleEntryCard({
    super.key,
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    this.badge,
  });

  final IconData icon;

  /// Two color stops for the icon container gradient (left → right).
  final List<Color> gradientColors;

  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  /// Optional pill badge (e.g., "New", "Quick Join").
  final String? badge;

  @override
  State<RoleEntryCard> createState() => _RoleEntryCardState();
}

class _RoleEntryCardState extends State<RoleEntryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;

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
      value: 0.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.972).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
    _glowAnim = CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
    _pressCtrl.forward();
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
    _pressCtrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _pressCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _pressCtrl,
      builder: (_, _) {
        final glow = _glowAnim.value;
        return Transform.scale(
          scale: _scaleAnim.value,
          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            child: _CardBody(
              isDark: isDark,
              accentColor: widget.accentColor,
              gradientColors: widget.gradientColors,
              icon: widget.icon,
              title: widget.title,
              subtitle: widget.subtitle,
              badge: widget.badge,
              glowIntensity: glow,
              isPressed: _isPressed,
            ),
          ),
        );
      },
    );
  }
}

// ── Card body ─────────────────────────────────────────────────────────────────

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.isDark,
    required this.accentColor,
    required this.gradientColors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.glowIntensity,
    required this.isPressed,
    this.badge,
  });

  final bool isDark;
  final Color accentColor;
  final List<Color> gradientColors;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final double glowIntensity;
  final bool isPressed;

  @override
  Widget build(BuildContext context) {
    // Glass surface color
    final surfaceColor = isDark
        ? Color.lerp(
            const Color(0xFF1A2236),
            accentColor,
            0.04,
          )!
        : Color.lerp(
            Colors.white,
            accentColor,
            0.025,
          )!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: isDark ? 0.85 : 0.90),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isPressed
                  ? accentColor.withValues(alpha: 0.50)
                  : isDark
                      ? accentColor.withValues(alpha: 0.14)
                      : accentColor.withValues(alpha: 0.18),
              width: isPressed ? 1.5 : 1.0,
            ),
            boxShadow: [
              // Accent glow on press
              BoxShadow(
                color: accentColor
                    .withValues(alpha: (0.20 + 0.12 * glowIntensity)),
                blurRadius: 20 + 12 * glowIntensity,
                offset: const Offset(0, 4),
              ),
              // Ambient shadow
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: isDark ? 0.28 : 0.07),
                blurRadius: 16,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // ── Gradient icon container ──────────────────────────────
              _IconContainer(
                gradientColors: gradientColors,
                icon: icon,
              ),
              const SizedBox(width: 16),

              // ── Title + subtitle ─────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppTypography.titleSmall.copyWith(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          _Badge(
                            label: badge!,
                            accentColor: accentColor,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // ── Arrow ────────────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor
                      .withValues(alpha: isPressed ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Icon container ────────────────────────────────────────────────────────────

class _IconContainer extends StatelessWidget {
  const _IconContainer({
    required this.gradientColors,
    required this.icon,
  });

  final List<Color> gradientColors;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Inner highlight for depth
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
          Icon(icon, size: 28, color: Colors.white),
        ],
      ),
    );
  }
}

// ── Badge pill ────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.accentColor});

  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: accentColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
