import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';

/// A two-column grid of quick-action tiles for the admin dashboard.
///
/// Each tile is a tappable card that navigates to a key admin feature:
/// Groups, Configure Meals, Export Reports, Attendance, and Billing.
/// FR-ADM-050: optional callback tiles add "Publish Notice" and
/// "Corrections" when the host screen provides handlers; "Vacations" opens
/// the vacation-approval queue and "Notepad" the personal notepad.
class QuickActionGrid extends StatelessWidget {
  const QuickActionGrid({
    super.key,
    this.onPublishNotice,
    this.onReviewCorrections,
    this.onVacationRequests,
    this.billingEnabled = true,
  });

  /// Live-Test-15 ISSUE-2: Meal Pricing is the MASTER GATE for meal billing.
  /// False hides the Member Billing tile entirely — when no group in the
  /// organization has Meal Pricing on there is no financial subsystem to open,
  /// and showing a screen that can only render ₹0 is what the requirement
  /// rejects. Defaults to true so every existing call site is unchanged.
  final bool billingEnabled;

  /// FR-ADM-050 (ISSUE-15): opens the notice composer when provided.
  final VoidCallback? onPublishNotice;

  /// Module 33: opens the correction-requests review queue when provided.
  final VoidCallback? onReviewCorrections;

  /// command_3: opens the vacation-requests approval queue when provided.
  final VoidCallback? onVacationRequests;

  @override
  Widget build(BuildContext context) {
    final actions = [
      const _ActionItem(
        icon: Icons.group_add_rounded,
        label: 'Manage Groups',
        color: AppColors.primary,
        route: RouteNames.adminGroups,
      ),
      const _ActionItem(
        icon: Icons.restaurant_menu_rounded,
        label: 'Configure Meals',
        color: AppColors.warning,
        route: RouteNames.adminMealConfig,
      ),
      const _ActionItem(
        icon: Icons.download_rounded,
        label: 'Export Reports',
        color: AppColors.secondary,
        route: RouteNames.adminExports,
      ),
      const _ActionItem(
        icon: Icons.fact_check_rounded,
        label: 'Attendance',
        color: AppColors.present,
        route: RouteNames.adminAttendance,
      ),
      if (billingEnabled)
        const _ActionItem(
          icon: Icons.receipt_long_rounded,
          label: 'Member Billing',
          color: AppColors.info,
          route: RouteNames.adminBilling,
        ),
      // Issue 6: quick access to archived groups (restore / permanent delete).
      const _ActionItem(
        icon: Icons.inventory_2_rounded,
        label: 'Archived Groups',
        color: AppColors.warning,
        route: '${RouteNames.adminGroups}?archived=true',
      ),
      if (onPublishNotice != null)
        _ActionItem(
          icon: Icons.campaign_rounded,
          label: 'Publish Notice',
          color: AppColors.error,
          onTap: onPublishNotice,
        ),
      if (onReviewCorrections != null)
        _ActionItem(
          icon: Icons.rule_rounded,
          label: 'Corrections',
          color: AppColors.secondary,
          onTap: onReviewCorrections,
        ),
      if (onVacationRequests != null)
        _ActionItem(
          icon: Icons.beach_access_rounded,
          label: 'Vacations',
          color: AppColors.vacation,
          onTap: onVacationRequests,
        ),
      const _ActionItem(
        icon: Icons.edit_note_rounded,
        label: 'Notepad',
        color: AppColors.violet,
        route: RouteNames.notepad,
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
          .map((a) => _QuickActionTile(
              item: a, onTap: a.onTap ?? () => context.push(a.route!)))
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
    this.route,
    this.onTap,
  }) : assert(route != null || onTap != null, 'Provide a route or onTap');
  final IconData icon;
  final String label;
  final Color color;
  final String? route;
  final VoidCallback? onTap;
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
