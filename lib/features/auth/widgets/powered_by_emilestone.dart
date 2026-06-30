import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Animated "Powered by eMilestone" brand mark (SRS AUTH-010 / UI-015).
///
/// A premium, lightweight loop tuned for a calm, classy cadence:
///  - a one-time entrance (fade + gentle rise),
///  - a single left→right shimmer that sweeps the wordmark then rests,
///  - a sparkle that softly pulses in scale + opacity and drifts in rotation.
///
/// One AnimationController drives the loop; the entrance uses a fire-once
/// TweenAnimationBuilder. Set [animate] to false for reduced-motion / low-power.
class PoweredByEmilestone extends StatefulWidget {
  const PoweredByEmilestone({
    super.key,
    this.baseColor,
    this.highlightColor,
    this.prefixColor,
    this.animate = true,
  });

  /// Resting color of the "eMilestone" wordmark.
  final Color? baseColor;

  /// Color of the shimmer that sweeps across the wordmark.
  final Color? highlightColor;

  /// Color of the muted "Powered by" prefix + sparkle.
  final Color? prefixColor;

  /// When false, renders the static brand mark (accessibility / low-power).
  final bool animate;

  @override
  State<PoweredByEmilestone> createState() => _PoweredByEmilestoneState();
}

class _PoweredByEmilestoneState extends State<PoweredByEmilestone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Fraction of each cycle spent sweeping; the remainder is a calm pause.
  static const double _sweepFraction = 0.5;

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
    final base = widget.baseColor ?? colorScheme.onSurface.withValues(alpha: 0.55);
    final highlight = widget.highlightColor ?? colorScheme.primary;
    final prefix =
        widget.prefixColor ?? colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

    final wordStyle = AppTypography.labelMedium.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    );
    final prefixStyle = AppTypography.labelSmall.copyWith(
      color: prefix,
      letterSpacing: 0.4,
      fontWeight: FontWeight.w500,
    );

    final loop = AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;
        // One-directional sweep during the first [_sweepFraction] of the cycle,
        // eased, then held off-screen for a restful pause.
        final swept = (v / _sweepFraction).clamp(0.0, 1.0);
        final p = Curves.easeInOut.transform(swept);
        final pos = -1.0 + 2.0 * p; // travels left → right

        // Sparkle breathes over the whole cycle (independent of the sweep).
        final breathe = (math.sin(v * 2 * math.pi) + 1) / 2; // 0..1
        final sparkleScale = 0.88 + 0.24 * breathe;
        final sparkleOpacity = 0.55 + 0.45 * breathe;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: sparkleOpacity,
              child: Transform.rotate(
                angle: breathe * 0.5,
                child: Transform.scale(
                  scale: sparkleScale,
                  child: Icon(Icons.auto_awesome_rounded,
                      size: 13, color: highlight),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('Powered by ', style: prefixStyle),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(pos - 0.5, 0),
                end: Alignment(pos + 0.5, 0),
                colors: [base, highlight, base],
                stops: const [0.30, 0.5, 0.70],
              ).createShader(bounds),
              child: Text(
                'eMilestone',
                style: wordStyle.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    // Fire-once entrance: fade in + gentle rise.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: loop,
    );
  }
}
