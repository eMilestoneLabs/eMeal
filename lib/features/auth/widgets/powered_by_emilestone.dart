import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Animated "Powered by eMilestone" brand mark (SRS AUTH-010 / UI-015).
///
/// Premium + robust:
///  - the wordmark is ALWAYS rendered in a readable [baseColor] (it never
///    depends on an entrance/animation state to be visible — fixes Issue 8),
///  - a bright highlight sweeps left→right across it (ShaderMask) then rests,
///  - a sparkle softly pulses in scale + opacity.
///
/// One AnimationController; set [animate] false for reduced-motion (renders the
/// static, fully-visible mark).
class PoweredByEmilestone extends StatefulWidget {
  const PoweredByEmilestone({
    super.key,
    this.baseColor,
    this.highlightColor,
    this.prefixColor,
    this.animate = true,
  });

  final Color? baseColor;
  final Color? highlightColor;
  final Color? prefixColor;
  final bool animate;

  @override
  State<PoweredByEmilestone> createState() => _PoweredByEmilestoneState();
}

class _PoweredByEmilestoneState extends State<PoweredByEmilestone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const double _sweepFraction = 0.5; // sweep half the cycle, then rest

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant PoweredByEmilestone old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.animate && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Readable defaults — always visible even at rest, in light AND dark.
    final base = widget.baseColor ?? colorScheme.onSurface.withValues(alpha: 0.75);
    final highlight = widget.highlightColor ?? colorScheme.primary;
    final prefix =
        widget.prefixColor ?? colorScheme.onSurfaceVariant.withValues(alpha: 0.70);

    final wordStyle = AppTypography.labelMedium.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    );
    final prefixStyle = AppTypography.labelSmall.copyWith(
      color: prefix,
      letterSpacing: 0.5,
      fontWeight: FontWeight.w600,
    );

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;
        final swept = (v / _sweepFraction).clamp(0.0, 1.0);
        final p = Curves.easeInOut.transform(swept);
        final pos = -1.0 + 2.0 * p; // travels left → right, then holds

        final breathe = (math.sin(v * 2 * math.pi) + 1) / 2; // 0..1
        final sparkleScale = 0.9 + 0.2 * breathe;
        final sparkleOpacity = 0.7 + 0.3 * breathe;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: sparkleOpacity,
              child: Transform.rotate(
                angle: breathe * 0.5,
                child: Transform.scale(
                  scale: sparkleScale,
                  child: Icon(Icons.auto_awesome_rounded, size: 13, color: highlight),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('Powered by ', style: prefixStyle),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) {
                // Base fills the whole word (always visible); a bright band
                // sweeps across for the premium shimmer.
                if (!widget.animate) {
                  return LinearGradient(colors: [base, base]).createShader(bounds);
                }
                return LinearGradient(
                  begin: Alignment(pos - 0.5, 0),
                  end: Alignment(pos + 0.5, 0),
                  colors: [base, highlight, base],
                  stops: const [0.30, 0.5, 0.70],
                ).createShader(bounds);
              },
              child: Text(
                'eMilestone',
                style: wordStyle.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}
