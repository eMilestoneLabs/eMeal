import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:smart_meal_management/features/admin/dashboard/widgets/admin_greeting_card.dart';
import 'package:smart_meal_management/features/notices/widgets/notice_bell.dart';
import 'package:smart_meal_management/features/admin/dashboard/widgets/quick_action_grid.dart';
import 'package:smart_meal_management/features/admin/dashboard/widgets/stats_summary_row.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_attendance_summary.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/widgets/app_section_title.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Admin home dashboard — greeting, KPI stats, quick actions, group list.
///
/// Uses [ListenableBuilder] to avoid manual addListener+setState boilerplate.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminDashboardProvider _provider;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _provider = AdminDashboardProvider();
      final auth = AuthProviderScope.of(context);
      final user = auth.currentUser;
      if (user == null) return;
      _provider.load(
        adminId: user.id,
        organizationId: user.organizationId,
        name: user.name,
      );
    }
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  void _refresh(AuthProvider auth) {
    final user = auth.currentUser;
    if (user == null) return;
    _provider.refresh(
      adminId: user.id,
      organizationId: user.organizationId,
      name: user.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = AuthProviderScope.of(context);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: false,
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (auth.currentUser != null)
            NoticeBell(
              organizationId: auth.currentUser!.organizationId,
              groupId: _provider.selectedGroupId,
              isAdmin: true,
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refresh(auth),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _provider,
        builder: (context, _) {
          if (_provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_provider.error != null) {
            return _ErrorView(
              message: _provider.error!,
              onRetry: () => _refresh(auth),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(auth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                // ── Greeting card ────────────────────────────────────────────
                AdminGreetingCard(
                  adminName: _provider.adminName,
                  orgName: _provider.orgName,
                  // #8: show the selected/default group's functional role.
                  roleLabel: _provider.selectedGroup?.functionalRole?.label,
                ),

                // ── Alert card (meal window closing) ─────────────────────────
                _MealWindowAlertCard(meals: _provider.todayMeals),

                const SizedBox(height: 22),

                // ── Stats row ────────────────────────────────────────────────
                const AppSectionTitle(
                  title: 'Overview',
                  subtitle: 'Live attendance for the selected group',
                ),
                const SizedBox(height: 12),
                // Issue #5/#8: per-group stats with a group switcher (default group).
                if (_provider.groups.length > 1) ...[
                  _GroupSelector(provider: _provider),
                  const SizedBox(height: 12),
                ],
                StatsSummaryRow(
                  totalMembers: _provider.totalMembers,
                  presentToday: _provider.presentToday,
                  absentToday: _provider.absentToday,
                  attendanceRate: _provider.attendanceRate,
                ),

                // ── Meal-wise attendance + preference breakdown (Issue 5) ────
                _MealWiseBreakdown(provider: _provider),

                const SizedBox(height: 22),

                // ── Quick actions ────────────────────────────────────────────
                const AppSectionTitle(title: 'Quick Actions'),
                const SizedBox(height: 12),
                const QuickActionGrid(),

                const SizedBox(height: 22),

                // ── Recent activity ──────────────────────────────────────────
                if (_provider.recentActivity.isNotEmpty) ...[
                  const AppSectionTitle(
                    title: 'Recent Activity',
                    subtitle: 'Last 5 attendance actions today',
                  ),
                  const SizedBox(height: 12),
                  _RecentActivityCard(records: _provider.recentActivity),
                  const SizedBox(height: 22),
                ],

                // ── Groups list ──────────────────────────────────────────────
                AppSectionTitle(
                  title: 'Your Groups',
                  actionLabel: 'See all',
                  onActionTap: () => context.push(RouteNames.adminGroups),
                ),
                const SizedBox(height: 12),

                if (_provider.groups.isEmpty)
                  const _EmptyGroups()
                else
                  ..._provider.groups.map((g) => _GroupTile(group: g)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Meal window alert card ─────────────────────────────────────────────────────

/// Shows a subtle warning card when any active meal attendance window is
/// closing within 60 minutes of the current time.
///
/// Reads actual close times from [meals] — no hardcoded hours.
class _MealWindowAlertCard extends StatelessWidget {
  const _MealWindowAlertCard({required this.meals});
  final List<MealModel> meals;

  /// Returns the first meal whose window closes within [withinMinutes] from
  /// now, or null if none.
  ({MealModel meal, int minutesLeft})? _closingSoon(
      List<MealModel> meals, int withinMinutes) {
    final now = DateTime.now();
    for (final meal in meals) {
      if (!meal.isActive) continue;
      final parts = meal.attendanceWindow.closeTime.split(':');
      if (parts.length < 2) continue;
      final closeHour = int.tryParse(parts[0]);
      final closeMin = int.tryParse(parts[1]);
      if (closeHour == null || closeMin == null) continue;
      final closeTime = DateTime(
          now.year, now.month, now.day, closeHour, closeMin);
      final diff = closeTime.difference(now).inMinutes;
      if (diff > 0 && diff <= withinMinutes) {
        return (meal: meal, minutesLeft: diff);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) return const SizedBox.shrink();

    final closing = _closingSoon(meals, 60);
    if (closing == null) return const SizedBox.shrink();

    final label = closing.minutesLeft <= 10
        ? 'Last chance — ${closing.meal.name} window closes in '
            '${closing.minutesLeft} min!'
        : '${closing.meal.name} attendance window closes in '
            '${closing.minutesLeft} min.';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Meal-wise breakdown (Issue 5) ───────────────────────────────────────────────

/// Per-meal-slot attendance + preference breakdown for the selected group.
///
/// Each meal slot shows its OWN Present / Absent / Skipped counts and its OWN
/// preference tags — counts reset for every slot so the admin can plan how much
/// food to prepare per meal (not a combined daily total). Data comes from the
/// existing GET /attendance/meal-summary endpoint via [AdminDashboardProvider].
class _MealWiseBreakdown extends StatelessWidget {
  const _MealWiseBreakdown({required this.provider});
  final AdminDashboardProvider provider;

  @override
  Widget build(BuildContext context) {
    final meals = provider.selectedGroupTodayMeals;
    if (meals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        const AppSectionTitle(
          title: 'Meal-wise Attendance',
          subtitle: 'Present, absent & preferences per meal slot',
        ),
        const SizedBox(height: 12),
        ...meals.map((m) {
          final summary = provider.mealSummary(m.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MealSummaryCard(meal: m, summary: summary),
          );
        }),
      ],
    );
  }
}

class _MealSummaryCard extends StatelessWidget {
  const _MealSummaryCard({required this.meal, required this.summary});
  final MealModel meal;
  final MealAttendanceSummary? summary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final present = summary?.presentCount ?? 0;
    final absent = summary?.absentCount ?? 0;
    final skipped = summary?.skippedCount ?? 0;
    final prefs = summary?.preferenceBreakdown ?? const <String, int>{};

    final sortedPrefs = prefs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meal name
          Row(
            children: [
              Icon(MealModel.slotIcon(meal.slotKey),
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  meal.name,
                  style: AppTypography.labelMedium
                      .copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Issue 1: the dashboard must mirror what was actually billed, never
              // a price edited AFTER the window closed (those edits apply to next
              // week's same weekday). Use the captured snapshot price; only fall
              // back to the live Meal.price while today's window is still open
              // (price not yet frozen / nothing billed yet).
              if ((summary?.snapshotPrice ??
                      (_mealWindowOpenNow(meal) ? meal.price : null)) !=
                  null)
                Text(
                  '₹${summary?.snapshotPrice ?? meal.price}',
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Present / Absent / Skipped counts
          Row(
            children: [
              _CountPill(
                  label: 'Present', value: present, color: AppColors.present),
              const SizedBox(width: 8),
              _CountPill(
                  label: 'Absent', value: absent, color: AppColors.absent),
              const SizedBox(width: 8),
              _CountPill(
                  label: 'Skipped', value: skipped, color: AppColors.skipped),
            ],
          ),
          // Per-meal preference breakdown
          if (sortedPrefs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.local_offer_rounded,
                    size: 13, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  'Preferences',
                  style: AppTypography.labelSmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sortedPrefs.map((e) {
                final disp = MealPreferenceOption.display(e.key);
                final label =
                    disp.emoji.isEmpty ? disp.label : '${disp.emoji} ${disp.label}';
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTypography.labelSmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${e.value}',
                          style: AppTypography.labelSmall.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent activity card ───────────────────────────────────────────────────────

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.records});
  final List<AttendanceModel> records;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = (isDark ? AppColors.borderDark : AppColors.border)
        .withValues(alpha: 0.4);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: records.indexed.map((entry) {
          final (i, record) = entry;
          return Column(
            children: [
              _ActivityRow(record: record),
              if (i < records.length - 1)
                Divider(height: 1, indent: 52, endIndent: 16,
                    color: borderColor),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.record});
  final AttendanceModel record;

  Color get _color {
    switch (record.status) {
      case AttendanceStatus.present: return AppColors.present;
      case AttendanceStatus.absent: return AppColors.absent;
      case AttendanceStatus.skipped: return AppColors.skipped;
      default: return AppColors.textTertiary;
    }
  }

  IconData get _icon {
    switch (record.status) {
      case AttendanceStatus.present: return Icons.check_circle_rounded;
      case AttendanceStatus.absent: return Icons.cancel_rounded;
      case AttendanceStatus.skipped: return Icons.remove_circle_outline_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = record.markedAt != null
        ? TimeFormat.tod12(TimeOfDay.fromDateTime(record.markedAt!))
        : '--:--';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, color: _color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Issue #4: show the member name, never the raw user id.
                  record.userName ?? 'Member',
                  style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  record.mealName ?? 'Attendance',
                  style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  record.status.name[0].toUpperCase() + record.status.name.substring(1),
                  style: AppTypography.labelSmall.copyWith(color: _color, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 3),
              Text(time, style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Error view ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty groups ───────────────────────────────────────────────────────────────

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(Icons.group_off_rounded, size: 36, color: secondaryText),
          const SizedBox(height: 10),
          Text('No groups yet',
              style: TextStyle(fontWeight: FontWeight.w600, color: secondaryText)),
          const SizedBox(height: 4),
          Text('Create your first group to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: secondaryText.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

// ── Group selector (Issue #5/#8) ────────────────────────────────────────────────

class _GroupSelector extends StatelessWidget {
  const _GroupSelector({required this.provider});
  final AdminDashboardProvider provider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: provider.selectedGroupId,
                hint: const Text('All groups'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All groups'),
                  ),
                  ...provider.groups.map(
                    (g) => DropdownMenuItem<String?>(
                      value: g.id,
                      child: Text(g.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: provider.selectGroup,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Group tile ─────────────────────────────────────────────────────────────────

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});
  final GroupModel group;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.4)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.group_rounded, size: 20, color: AppColors.primary),
        ),
        title: Text(group.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${group.memberCount} members · ${group.type.label}',
          style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: group.isActive
                ? AppColors.present.withValues(alpha: 0.1)
                : AppColors.textTertiary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            group.isActive ? 'Active' : 'Archived',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: group.isActive ? AppColors.present : AppColors.textTertiary,
            ),
          ),
        ),
        onTap: () => context.push('/admin/groups/${group.id}'),
      ),
    );
  }
}

/// Issue 1 helper: true when [meal]'s attendance window is open at the current
/// wall-clock minute. Used so the admin dashboard only shows a live (editable)
/// unit price while the window is open; once closed it shows the billed snapshot.
bool _mealWindowOpenNow(MealModel meal) {
  int? toMinutes(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  final open = toMinutes(meal.attendanceWindow.openTime);
  final close = toMinutes(meal.attendanceWindow.closeTime);
  if (open == null || close == null) return true;
  final now = TimeOfDay.now();
  final nowMinutes = now.hour * 60 + now.minute;
  return nowMinutes >= open && nowMinutes <= close;
}
