import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';

/// A 2×2 grid of quick-action tiles for the admin dashboard.
///
/// Each tile is a tappable card that navigates to a key admin feature:
/// Groups, Configure Meals, Export Reports, and Attendance.
class QuickActionGrid extends StatelessWidget {
  const QuickActionGrid({super.key});

  @override
  Widget build(BuildContext context) {
    const actions = [
      _ActionItem(
        icon: Icons.group_add_rounded,
        label: 'Manage Groups',
        color: AppColors.primary,
        route: RouteNames.adminGroups,
      ),
      _ActionItem(
        icon: Icons.restaurant_menu_rounded,
        label: 'Configure Meals',
        color: AppColors.warning,
        route: RouteNames.adminMealConfig,
      ),
      _ActionItem(
        icon: Icons.download_rounded,
        label: 'Export Reports',
        color: AppColors.secondary,
        route: RouteNames.adminExports,
      ),
      _ActionItem(
        icon: Icons.fact_check_rounded,
        label: 'Attendance',
        color: AppColors.present,
        route: RouteNames.adminAttendance,
      ),
      _ActionItem(
        icon: Icons.receipt_long_rounded,
        label: 'Member Billing',
        color: AppColors.info,
        route: RouteNames.adminBilling,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: actions
          .map((a) => _QuickActionTile(item: a, onTap: () => context.push(a.route)))
          .toList(),
    );
  }
}

// ── Data model ─────────────────────────────────────────────────────────────────

class _ActionItem {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
  });
  final IconData icon;
  final String label;
  final Color color;
  final String route;
}

// ── Tile widget ────────────────────────────────────────────────────────────────

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.item, required this.onTap});
  final _ActionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.color.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, size: 18, color: item.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
