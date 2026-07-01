import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Animated "Powered by eMilestone" brand mark (SRS AUTH-010 / UI-015).
///
/// Premium, always-visible, letter-by-letter animation: a soft glow wave sweeps
/// across the wordmark so each letter lights up (highlight color + subtle lift +
/// glow) in sequence, then repeats — plus a pulsing sparkle. Every letter is
/// ALWAYS rendered in a readable [baseColor], so it's visible even at rest and
/// on every launch (not just cold start).
///
/// Set [animate] false for reduced-motion (static, fully-visible mark).
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

  static const String _word = 'eMilestone';

  @override
  State<PoweredByEmilestone> createState() => _PoweredByEmilestoneState();
}

class _PoweredByEmilestoneState extends State<PoweredByEmilestone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
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

  /// Glow intensity (0..1) for the letter at [index] given wave [head] position.
  double _glow(double head, int index) {
    final d = head - index;
    // Smooth bell centred just after the head passes the letter.
    final x = (d - 1.0);
    return math.exp(-(x * x) / 1.6).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = widget.baseColor ?? colorScheme.onSurface.withValues(alpha: 0.80);
    final highlight = widget.highlightColor ?? colorScheme.primary;
    final prefix =
        widget.prefixColor ?? colorScheme.onSurfaceVariant.withValues(alpha: 0.70);

    final wordStyle = AppTypography.labelMedium.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    );
    final prefixStyle = AppTypography.labelSmall.copyWith(
      color: prefix,
      letterSpacing: 0.5,
      fontWeight: FontWeight.w600,
    );

    final letters = PoweredByEmilestone._word.split('');

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;
        // Wave head travels across all letters, with a tail pause each cycle.
        final head = v * (letters.length + 5);
        final breathe = (math.sin(v * 2 * math.pi) + 1) / 2;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Opacity(
              opacity: 0.7 + 0.3 * breathe,
              child: Transform.scale(
                scale: 0.9 + 0.2 * breathe,
                child: Transform.rotate(
                  angle: breathe * 0.5,
                  child: Icon(Icons.auto_awesome_rounded, size: 13, color: highlight),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('Powered by ', style: prefixStyle),
            for (int i = 0; i < letters.length; i++)
              _AnimatedLetter(
                char: letters[i],
                style: wordStyle,
                base: base,
                highlight: highlight,
                glow: widget.animate ? _glow(head, i) : 0.0,
              ),
          ],
        );
      },
    );
  }
}

class _AnimatedLetter extends StatelessWidget {
  const _AnimatedLetter({
    required this.char,
    required this.style,
    required this.base,
    required this.highlight,
    required this.glow,
  });

  final String char;
  final TextStyle style;
  final Color base;
  final Color highlight;
  final double glow; // 0..1

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(base, highlight, glow) ?? base;
    return Transform.translate(
      offset: Offset(0, -1.5 * glow), // gentle lift as the wave passes
      child: Text(
        char,
        style: style.copyWith(
          color: color,
          shadows: glow > 0.15
              ? [
                  Shadow(
                    color: highlight.withValues(alpha: 0.55 * glow),
                    blurRadius: 8 * glow,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
