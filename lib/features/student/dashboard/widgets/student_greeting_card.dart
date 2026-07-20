import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/widgets/user_avatar.dart';

/// Greeting card at top of the student dashboard.
///
/// Renders a time-based greeting, the student's name and optional group label,
/// and a compact stats row with:
/// - Attendance rate this month
/// - Streak badge (shown only when streak > 0)
/// - Auto-attend indicator (shown only when [isDefaultAttendance] = true)
/// - Vacation mode banner (shown only when [isVacationMode] = true)
class StudentGreetingCard extends StatelessWidget {
  const StudentGreetingCard({
    super.key,
    String? name,
    this.user,
    this.groupName,
    this.roleLabel,
    this.onAvatarTap,
    this.streakDays = 0,
    this.isVacationMode = false,
    this.attendanceRate = 0.0,
    this.isDefaultAttendance = false,
  }) : name = name ?? '';

  final String name;
  final UserModel? user;

  /// Displayed below the name as a subtle group label.
  final String? groupName;

  /// #2: the member's per-group display role (e.g. "Member"), shown as a chip
  /// beside the group name. Null hides it (legacy joins with no explicit role).
  final String? roleLabel;

  final VoidCallback? onAvatarTap;
  final int streakDays;
  final bool isVacationMode;
  final double attendanceRate;

  /// When true, shows an "Auto-attend ON" chip so the student knows their
  /// default-attendance mode is active.
  final bool isDefaultAttendance;

  String get _displayName => user?.name ?? name;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space20),
      decoration: BoxDecoration(
        // 3-stop gradient: soft lavender → indigo → rich violet
        // gives a vivid, premium CRED/Linear-inspired look vs a flat solid blue.
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary, AppColors.violet],
          stops: [0.0, 0.45, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Vacation banner (top of card) ────────────────────────────────
          if (isVacationMode)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.vacation.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: AppColors.vacation.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.beach_access_rounded,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    'Vacation Mode Active',
                    style:
                        AppTypography.labelSmall.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),

          // ── Greeting + avatar (ISSUE-003) ─────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_greeting,',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _displayName,
                      style: AppTypography.headlineSmall.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // ISSUE-003: profile photo on the hero card — consistent with
              // the rest of the app; taps through to the profile tab.
              UserAvatar(
                name: _displayName,
                avatarUrl: user?.avatarUrl,
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                foregroundColor: AppColors.onPrimary,
                onTap: onAvatarTap,
              ),
            ],
          ),

          // ── Group label + per-group role (#2) ─────────────────────────────
          if (groupName != null && groupName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.group_outlined,
                  size: 13,
                  color: Colors.white60,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    groupName!,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                ),
                // #2: per-group role chip (e.g. "Member") next to the group.
                if (roleLabel != null && roleLabel!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      roleLabel!,
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: AppConstants.space16),

          // ── Stats row ────────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Attendance rate
              _StatChip(
                icon: Icons.bar_chart_rounded,
                label:
                    '${(attendanceRate * 100).toStringAsFixed(0)}% this month',
              ),
              // Streak (only when > 0)
              if (streakDays > 0)
                _StatChip(
                  icon: Icons.local_fire_department_rounded,
                  label: '$streakDays day streak',
                  color: const Color(0xFFFBBF24),
                ),
              // Default attendance indicator
              if (isDefaultAttendance)
                const _StatChip(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Auto-attend ON',
                  color: Color(0xFF86EFAC), // soft green
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    this.color = Colors.white70,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
