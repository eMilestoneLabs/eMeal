import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

// ── PasswordStrengthIndicator ──────────────────────────────────────────────────

/// Animated 4-segment bar that shows password strength in real-time.
///
/// Strength levels:
///   - Empty (0 segments) — no password yet
///   - Weak (1 segment, red) — < 6 chars or only one character class
///   - Fair (2 segments, orange) — mixed case or numbers, < 8 chars
///   - Good (3 segments, yellow-green) — 8+ chars, mixed case + numbers
///   - Strong (4 segments, green) — 8+ chars, upper+lower+number+special
class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({super.key, required this.password});

  final String password;

  PasswordStrength get _strength => _evaluate(password);

  static PasswordStrength _evaluate(String password) {
    if (password.isEmpty) return PasswordStrength.empty;
    if (password.length < 6) return PasswordStrength.weak;

    int score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) score++;

    if (score <= 1) return PasswordStrength.weak;
    if (score == 2) return PasswordStrength.fair;
    if (score == 3) return PasswordStrength.good;
    return PasswordStrength.strong;
  }

  @override
  Widget build(BuildContext context) {
    final strength = _strength;
    if (strength == PasswordStrength.empty) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Row(
            children: List.generate(4, (i) {
              final filled = i < strength.segments;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  height: 3,
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: filled
                        ? strength.color
                        : Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            strength.label,
            style: AppTypography.labelSmall.copyWith(
              color: strength.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── PasswordStrength enum ──────────────────────────────────────────────────────

enum PasswordStrength {
  empty(0, '', AppColors.textTertiary),
  weak(1, 'Weak', AppColors.absent),
  fair(2, 'Fair', AppColors.warning),
  good(3, 'Good', AppColors.info),
  strong(4, 'Strong', AppColors.present);

  const PasswordStrength(this.segments, this.label, this.color);
  final int segments;
  final String label;
  final Color color;
}
