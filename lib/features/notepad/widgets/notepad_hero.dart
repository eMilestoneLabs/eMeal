import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/notepad/providers/notepad_provider.dart';
import 'package:smart_meal_management/features/notepad/utils/note_date_format.dart';

/// Premium home header for the Notepad: time-of-day greeting, the user's
/// first name, an inviting tagline, and today's date. Pure presentation —
/// no note data is read here, so it never rebuilds while typing elsewhere.
class NotepadHero extends StatelessWidget {
  const NotepadHero({super.key, required this.isDark, this.userName});

  final bool isDark;

  /// Display name of the signed-in user (first word is shown). Optional so
  /// the notepad keeps working even if the auth scope is unavailable.
  final String? userName;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Good Night';
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String? get _firstName {
    final raw = userName?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final name = _firstName;
    final dateLine = DateFormat('EEEE, d MMMM').format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateLine.toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: AppConstants.space6),
        Text(
              name == null ? _greeting : '$_greeting,',
              style: AppTypography.headlineSmall.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            )
            .animate()
            .fadeIn(duration: AppConstants.animNormal)
            .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
        if (name != null)
          Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: AppColors.primary,
                ),
              )
              .animate()
              .fadeIn(
                duration: AppConstants.animNormal,
                delay: const Duration(milliseconds: 80),
              )
              .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
        const SizedBox(height: AppConstants.space6),
        Text(
          'Capture your ideas before they disappear.',
          style: AppTypography.bodySmall.copyWith(
            height: 1.4,
            color:
                isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ).animate().fadeIn(
          duration: AppConstants.animNormal,
          delay: const Duration(milliseconds: 140),
        ),
      ],
    );
  }
}

/// "Today's Notes" glass stat card: live counts for notes, pinned, checklists
/// and open to-dos, plus a last-activity stamp. Reads the provider it is given
/// (the caller rebuilds it via its own AnimatedBuilder).
class NotepadStatsCard extends StatelessWidget {
  const NotepadStatsCard({
    super.key,
    required this.provider,
    required this.isDark,
  });

  final NotepadProvider provider;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final lastEdit = provider.lastEditedAt;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;

    return Container(
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              AppColors.primary.withValues(alpha: isDark ? 0.20 : 0.08),
              surface,
            ),
            Color.alphaBlend(
              AppColors.violet.withValues(alpha: isDark ? 0.14 : 0.05),
              surface,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius + 4),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: isDark ? 0.10 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.violet],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppConstants.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Notes",
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color:
                            isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      lastEdit == null
                          ? 'Private · stored only on this device'
                          : 'Last edited ${NoteDateFormat.relative(lastEdit)}',
                      style: AppTypography.labelSmall.copyWith(
                        fontSize: 11,
                        color:
                            isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space16),
          Row(
            children: [
              _Stat(
                value: provider.totalCount,
                label: 'Notes',
                color: AppColors.primary,
                isDark: isDark,
              ),
              _divider(),
              _Stat(
                value: provider.pinnedCount,
                label: 'Pinned',
                color: AppColors.warning,
                isDark: isDark,
              ),
              _divider(),
              _Stat(
                value: provider.checklistCount,
                label: 'Checklists',
                color: AppColors.secondary,
                isDark: isDark,
              ),
              _divider(),
              _Stat(
                value: provider.openChecklistItems,
                label: 'To-dos left',
                color: AppColors.info,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 30,
    margin: const EdgeInsets.symmetric(horizontal: AppConstants.space8),
    color: (isDark ? AppColors.borderDark : AppColors.border).withValues(
      alpha: 0.6,
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final int value;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Animated count-up so the card feels alive on open.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: AppConstants.animSlow,
            curve: Curves.easeOutCubic,
            builder:
                (context, v, _) => Text(
                  '${v.round()}',
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color:
                  isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
