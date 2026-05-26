import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/widgets/app_glass_card.dart';
import 'package:smart_meal_management/shared/widgets/app_status_chip.dart';

/// Reusable group summary card for the admin groups list.
///
/// Displays group name, type chip, member count, meal-system badge, and
/// active indicator.  Tap triggers [onTap]; long-press reveals [onArchive].
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    this.onTap,
    this.onArchive,
  });

  final GroupModel group;
  final VoidCallback? onTap;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      glassEnabled: false,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(
                children: [
                  // Icon container
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _groupIcon(group.type),
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          group.type.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status chip
                  AppStatusChip.label(
                    label: group.isActive ? 'Active' : 'Archived',
                    color: group.isActive ? AppColors.present : AppColors.textTertiary,
                    compact: true,
                  ),
                  if (onArchive != null)
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'archive',
                          child: Row(
                            children: [
                              Icon(Icons.archive_rounded, size: 16),
                              SizedBox(width: 8),
                              Text('Archive'),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (v) {
                        if (v == 'archive') onArchive?.call();
                      },
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Stats row — uses Wrap so badges never overflow ────────────
              Row(
                children: [
                  // Badges section (wraps to next line on narrow screens)
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatBadge(
                          icon: Icons.people_rounded,
                          label: '${group.memberCount} members',
                        ),
                        _StatBadge(
                          icon: group.mealConfig.mealsEnabled
                              ? Icons.restaurant_rounded
                              : Icons.no_meals_rounded,
                          label: group.mealConfig.mealsEnabled
                              ? 'Meals On'
                              : 'Att. Only',
                          color: group.mealConfig.mealsEnabled
                              ? AppColors.secondary
                              : AppColors.textTertiary,
                        ),
                        if (group.mealConfig.preferencesEnabled)
                          const _StatBadge(
                            icon: Icons.tune_rounded,
                            label: 'Prefs On',
                            color: AppColors.warning,
                          ),
                      ],
                    ),
                  ),
                  // Join code — right-aligned, constrained width
                  if (group.joinCode != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 90),
                          child: Text(
                            group.joinCode!,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _groupIcon(GroupType type) => switch (type) {
        GroupType.hostel => Icons.apartment_rounded,
        GroupType.mess => Icons.restaurant_rounded,
        GroupType.cafeteria => Icons.local_cafe_rounded,
        GroupType.pg => Icons.home_rounded,
        GroupType.coachingInstitute => Icons.school_rounded,
        GroupType.office => Icons.business_rounded,
        GroupType.factory_ => Icons.factory_rounded,
        GroupType.community => Icons.people_rounded,
        GroupType.event => Icons.celebration_rounded,
        GroupType.other => Icons.group_rounded,
      };
}

// ── Stat badge ────────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: c,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

  }
}
