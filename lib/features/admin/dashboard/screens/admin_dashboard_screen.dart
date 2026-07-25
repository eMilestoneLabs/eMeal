import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/correction_requests_screen.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/vacation_requests_screen.dart';
import 'package:smart_meal_management/features/admin/dashboard/widgets/admin_greeting_card.dart';
import 'package:smart_meal_management/features/notices/screens/notice_composer_screen.dart';
import 'package:smart_meal_management/features/notices/widgets/notice_bell.dart';
import 'package:smart_meal_management/features/admin/dashboard/widgets/quick_action_grid.dart';
import 'package:smart_meal_management/features/admin/dashboard/widgets/stats_summary_row.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_attendance_summary.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/widgets/app_section_title.dart';
import 'package:smart_meal_management/shared/widgets/app_screen_states.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';
import 'package:smart_meal_management/shared/widgets/user_avatar.dart';

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
    // The provider is owned by [AdminShell] via [AdminDashboardScope] so its
    // in-memory state survives tab switches — returning to Home shows the last
    // data instantly instead of flashing zeros (Issue 1). This screen reads it
    // and triggers the (SWR) load: load() shows no spinner when data already
    // exists, so a return visit silently refreshes in the background.
    if (!_initialized) {
      _initialized = true;
      _provider = AdminDashboardScope.of(context);
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

  // No dispose of _provider — it is owned by [AdminShell] (AdminDashboardScope)
  // and lives for the whole admin session.

  // Issue 2: the refresh arrow re-fetches from the server every time (there is
  // no client cache), but with existing data on screen it never showed a
  // spinner and — within the backend's short Redis TTL — the numbers can be
  // identical, so the tap looked dead. This state drives visible feedback.
  bool _isRefreshing = false;

  Future<void> _refresh(AuthProvider auth) async {
    final user = auth.currentUser;
    if (user == null || _isRefreshing) return;
    setState(() => _isRefreshing = true);
    await _provider.refresh(
      adminId: user.id,
      organizationId: user.organizationId,
      name: user.name,
    );
    if (!mounted) return;
    setState(() => _isRefreshing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dashboard updated'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// FR-ADM-050: dashboard "Publish Notice" quick action — opens the composer
  /// scoped to the currently selected group (or org-wide when none).
  Future<void> _publishNotice(AuthProvider auth) async {
    final user = auth.currentUser;
    if (user == null) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NoticeComposerScreen(
          organizationId: user.organizationId,
          groupId: _provider.selectedGroupId,
        ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notice published')),
      );
    }
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
          // command_3: always-visible Notepad entry in the dashboard header.
          IconButton(
            tooltip: 'Notepad',
            icon: const Icon(Icons.edit_note_rounded),
            onPressed: () => context.push(RouteNames.notepad),
          ),
          if (auth.currentUser != null)
            NoticeBell(
              organizationId: auth.currentUser!.organizationId,
              groupId: _provider.selectedGroupId,
              isAdmin: true,
            ),
          _isRefreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              : IconButton(
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
            return const AppDashboardSkeleton();
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
                // Pass 15 (FR-ANL-022): "Updated X ago" surfaces only while the
                // shown KPIs are stale cache; it disappears once the live
                // refresh lands (FreshnessBadge self-hides when fresh).
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FreshnessBadge(lastUpdated: _provider.lastUpdated),
                  ),
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
                // FR-ADM-050 (ISSUE-15): "Publish Notice" + corrections queue
                // are first-class dashboard actions, not buried in sub-screens.
                QuickActionGrid(
                  onPublishNotice: () => _publishNotice(auth),
                  onReviewCorrections: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CorrectionRequestsScreen()),
                  ),
                  // command_3: vacation approvals one tap from the dashboard.
                  onVacationRequests: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const VacationRequestsScreen()),
                  ),
                ),

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceElevatedDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.4)),
        // Feather-light depth so cards float off the background (light mode
        // only — dark mode layers via the elevated surface color instead).
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meal name — premium gradient slot badge + name + price pill.
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.gradientViolet],
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.30),
                      blurRadius: 7,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(MealModel.slotIcon(meal.slotKey),
                    size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.primary.withValues(alpha: 0.22)
                        : AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: AppColors.primary
                          .withValues(alpha: isDark ? 0.45 : 0.25),
                    ),
                  ),
                  child: Text(
                    '₹${summary?.snapshotPrice ?? meal.price}',
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.primaryLight
                          : AppColors.primaryDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Live-Test-10 Kitchen Summary — MEMBERS block. Present / Absent /
          // Skip / Vacation (+ live Pending). A Wrap of fixed-width pills
          // (never Expanded — Wrap is not a Flex, Expanded inside it throws
          // and release builds paint the grey ErrorWidget) keeps the classic
          // equal-thirds grid and overflows extra pills to the next row.
          const _SectionLabel(
              icon: Icons.people_alt_rounded,
              label: 'MEMBERS',
              color: AppColors.primary),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final pillWidth = (constraints.maxWidth - 16) / 3;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountPill(
                    label: 'Present',
                    value: present,
                    color: AppColors.present,
                    width: pillWidth),
                _CountPill(
                    label: 'Absent',
                    value: absent,
                    color: AppColors.absent,
                    width: pillWidth),
                _CountPill(
                    label: 'Skip',
                    value: skipped,
                    color: AppColors.skipped,
                    width: pillWidth),
                _CountPill(
                    label: 'Vacation',
                    value: summary?.vacationCount ?? 0,
                    color: AppColors.info,
                    width: pillWidth),
                if ((summary?.pendingCount ?? 0) > 0)
                  _CountPill(
                      label: 'Pending',
                      value: summary!.pendingCount!,
                      color: AppColors.warning,
                      width: pillWidth),
              ],
            );
          }),
          // Pass 15 (FR-ANL-003): expected participants for this meal —
          // active, non-blocked members minus anyone on vacation. Shown as a
          // quiet caption so admins can read "present vs. expected" at a glance.
          if (summary?.expectedParticipants != null) ...[
            const SizedBox(height: 6),
            Text(
              'Expected ${summary!.expectedParticipants} of '
              '${summary!.totalMembers} members (excludes vacation)',
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
          // Live-Test-10 Kitchen Summary — GUEST SUMMARY ledger. Approved
          // bookings are the ONLY guests that feed kitchen/attendance/billing
          // totals; Awaiting / Cancelled / No-show are administrative rows.
          if (summary != null &&
              (summary!.guestTotalRequests > 0 || summary!.guestCount > 0)) ...[
            const SizedBox(height: 12),
            const _SectionLabel(
                icon: Icons.group_add_rounded,
                label: 'GUEST SUMMARY',
                color: AppColors.secondary),
            const SizedBox(height: 6),
            _LedgerRow(
                label: 'Approved / Present',
                value: summary!.guestCount,
                color: AppColors.present),
            if (summary!.guestPendingApproval > 0)
              _LedgerRow(
                  label: 'Awaiting Approval',
                  value: summary!.guestPendingApproval,
                  color: AppColors.warning),
            if (summary!.guestCancelled > 0)
              _LedgerRow(
                  label: 'Cancelled / Rejected',
                  value: summary!.guestCancelled,
                  color: AppColors.absent),
            if (summary!.guestNoShow > 0)
              _LedgerRow(
                  label: 'No-show',
                  value: summary!.guestNoShow,
                  color: AppColors.skipped),
            if (summary!.guestTotalRequests > 0) ...[
              const _LedgerDivider(),
              _LedgerRow(
                  label: 'Total guest requests',
                  value: summary!.guestTotalRequests,
                  color: AppColors.secondary,
                  bold: true),
            ],
            if (summary!.guestCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${summary!.guestAdults} adult · ${summary!.guestChildren} '
                  'child approved plates, hosted by members',
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ),
          ],
          // Live-Test-10 Kitchen Summary — TOTAL TO SERVE. Present members +
          // approved guests: the kitchen preparation count, no mental math.
          if (summary != null) ...[
            const SizedBox(height: 12),
            _ServePanel(
              members: summary!.presentCount,
              guests: summary!.guestCount,
              total: summary!.effectiveAttendingTotal,
            ),
          ],
          // Live-Test-10 Kitchen Summary — preference sections. Preference is
          // either DISABLED (no section at all) or MANDATORY: standalone
          // totals and every preference-group total must equal Present
          // members + approved guests; any deviation is a data-integrity
          // fault surfaced as a Dashboard Data Mismatch banner.
          ..._buildPreferenceSections(isDark),
        ],
      ),
    );
  }

  /// Distinct accent per section — enterprise dashboards colour-code groups.
  static const _sectionAccents = <Color>[
    AppColors.primary,
    AppColors.secondary,
    AppColors.violet,
    AppColors.info,
    AppColors.warning,
  ];

  /// Kitchen Summary preference sections. GROUPS mode: one validated section
  /// per configured group (member + guest picks merged per option, split
  /// shown). STANDALONE mode: a single validated section. Preference disabled
  /// (no data): no section at all.
  ///
  /// ISSUE-006 calculation rules (UI unchanged — validation only):
  ///  • The system NONE picks are HIDDEN from the visible rows but feed the
  ///    internal validation (visible + NONE == expected for Single Pick).
  ///  • Multiple Pick / Quantity groups display "X of Y" (total selections or
  ///    portions of expected members) — totals legitimately exceed headcount,
  ///    so they never raise a mismatch (per-record rules are enforced
  ///    server-side at write time).
  List<Widget> _buildPreferenceSections(bool isDark) {
    final s = summary;
    if (s == null) return const [];
    final expected = s.presentCount + s.guestCount;
    final memberGroups = s.preferenceGroupBreakdown;
    final guestGroups = s.guestPreferenceGroupBreakdown;
    final out = <Widget>[];

    if (memberGroups.isNotEmpty || guestGroups.isNotEmpty) {
      final labels = <String>[
        ...memberGroups.keys,
        ...guestGroups.keys.where((g) => !memberGroups.containsKey(g)),
      ];
      for (var i = 0; i < labels.length; i++) {
        // ISSUE-006: the group's configured rules govern which validation
        // applies. Snapshot labels are immutable, so a label lookup against
        // the live meal config is stable; a group renamed/removed since falls
        // back to the strict single-pick rule (fail-safe).
        PreferenceGroupModel? cfg;
        for (final g in meal.preferenceGroups) {
          if (g.label == labels[i]) {
            cfg = g;
            break;
          }
        }
        out.add(_PrefSection(
          title: labels[i],
          icon: Icons.tune_rounded,
          accent: _sectionAccents[i % _sectionAccents.length],
          memberCounts: memberGroups[labels[i]] ?? const {},
          guestCounts: guestGroups[labels[i]] ?? const {},
          expectedTotal: expected,
          // ISSUE-004: headcount validation uses DISTINCT RESPONDENTS (1
          // member = 1, however many options/plates they picked) — safe for
          // Multiple Pick AND Quantity mode. Falls back to pick rows
          // (ISSUE-016, quantity-safe only) then plate totals on cached
          // pre-fix payloads.
          memberPickCount: s.preferenceGroupRespondentCounts[labels[i]] ??
              s.preferenceGroupPickCounts[labels[i]],
          // ISSUE-002: distinct guest respondents — never the portion total.
          guestPickCount: s.guestPreferenceGroupRespondentCounts[labels[i]],
          resolveDisplay: false,
          multiPick: cfg != null && !cfg.isSingle,
          quantityEnabled: cfg?.quantityEnabled ?? false,
          requiredGroup: cfg?.required ?? true,
          isDark: isDark,
        ));
      }
      return out;
    }

    // Standalone mode — 'unspecified' means a REQUIRED pick is missing; it is
    // excluded from the rows so the shortfall drives the mismatch banner.
    final memberFlat = Map<String, int>.from(s.preferenceBreakdown)
      ..remove('unspecified');
    final guestFlat = Map<String, int>.from(s.guestPreferenceBreakdown)
      ..remove('unspecified');
    if (memberFlat.isNotEmpty || guestFlat.isNotEmpty) {
      out.add(_PrefSection(
        title: 'Standalone Preference',
        icon: Icons.local_offer_rounded,
        accent: AppColors.violet,
        memberCounts: memberFlat,
        guestCounts: guestFlat,
        expectedTotal: expected,
        resolveDisplay: true,
        isDark: isDark,
      ));
    }
    return out;
  }
}

// ── Kitchen Summary building blocks (Live-Test-10) ─────────────────────────

/// Small-caps section label with a colored icon — MEMBERS / GUEST SUMMARY.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// One ledger line: colored status dot · label ····· value.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });
  final String label;
  final int value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: bold ? textColor : (isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary),
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$value',
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: bold ? color : textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerDivider extends StatelessWidget {
  const _LedgerDivider();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        height: 1,
        color: (isDark ? AppColors.borderDark : AppColors.border)
            .withValues(alpha: 0.6),
      ),
    );
  }
}

/// TOTAL TO SERVE — the kitchen preparation count on a vibrant gradient
/// panel: present members + approved guests, no mental math ever.
class _ServePanel extends StatelessWidget {
  const _ServePanel(
      {required this.members, required this.guests, required this.total});
  final int members;
  final int guests;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.gradientViolet],
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL TO SERVE',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Members $members · Guests $guests — kitchen '
                  'preparation count',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Text(
              '$total',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A validated preference section — per-option rows with Members · Guests
/// split, and a self-checking total: green ✓ when the sum equals Present
/// members + approved guests, red Dashboard Data Mismatch banner otherwise
/// (preferences are mandatory when enabled, so any deviation is a
/// data-integrity fault).
class _PrefSection extends StatelessWidget {
  const _PrefSection({
    required this.title,
    required this.icon,
    required this.accent,
    required this.memberCounts,
    required this.guestCounts,
    required this.expectedTotal,
    required this.resolveDisplay,
    required this.isDark,
    this.memberPickCount,
    this.guestPickCount,
    this.multiPick = false,
    this.quantityEnabled = false,
    this.requiredGroup = true,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Map<String, int> memberCounts;
  final Map<String, int> guestCounts;
  final int expectedTotal;

  /// ISSUE-004/016: member HEADCOUNT for this group — distinct respondents
  /// when the backend provides them (multi-pick + quantity safe; 1 member =
  /// 1), else pick rows. When present, validation uses this + guest plates
  /// instead of the pick/quantity-inflated display totals.
  final int? memberPickCount;

  /// ISSUE-002: distinct GUEST respondents for this group — the guest twin of
  /// [memberPickCount]. Null on legacy payloads, where the plate total is used.
  final int? guestPickCount;

  /// True for standalone tags — labels resolve through
  /// [MealPreferenceOption.display] for emoji + proper casing.
  final bool resolveDisplay;

  /// ISSUE-006 (CASE_4/6): Allow Multiple Picks is ON for this group — the
  /// totals are SELECTIONS (or portions), not people, so equality with the
  /// expected headcount is not a valid check. Displays "X of Y" instead; the
  /// per-record pick rules are already enforced server-side at write time.
  final bool multiPick;

  /// ISSUE-006 (CASE_5/6): quantities are ON — the totals are PORTIONS the
  /// kitchen prepares ("Chicken ×3 + ×2" shows 5, not 2).
  final bool quantityEnabled;

  /// ISSUE-006: an OPTIONAL group (required=false) may legitimately have
  /// fewer respondents than the expected headcount — no mismatch is raised.
  final bool requiredGroup;

  final bool isDark;

  /// ISSUE-005/006: the system NONE keys — hidden from every visible row,
  /// used internally so (visible + NONE == expected) validates Single Pick.
  /// Delegates to the app-wide single source of truth so the dashboard's
  /// hidden-NONE accounting can never drift from what the pickers offer.
  static bool _isNoneKey(String k) => MealPreferenceOption.isSystemNone(k);

  @override
  Widget build(BuildContext context) {
    // ISSUE-006: split the raw breakdowns into VISIBLE rows (real food items)
    // and the hidden system NONE tallies. NONE rows always carry quantity 1
    // per respondent, so their sum equals the number of NONE pickers.
    final memberVisible = <String, int>{
      for (final e in memberCounts.entries)
        if (!_isNoneKey(e.key)) e.key: e.value,
    };
    final guestVisible = <String, int>{
      for (final e in guestCounts.entries)
        if (!_isNoneKey(e.key)) e.key: e.value,
    };
    final memberNone = memberCounts.entries
        .where((e) => _isNoneKey(e.key))
        .fold<int>(0, (a, e) => a + e.value);
    final guestNone = guestCounts.entries
        .where((e) => _isNoneKey(e.key))
        .fold<int>(0, (a, e) => a + e.value);

    final options = <String>[
      ...memberVisible.keys,
      ...guestVisible.keys.where((k) => !memberVisible.containsKey(k)),
    ];
    final totals = <String, int>{
      for (final o in options)
        o: (memberVisible[o] ?? 0) + (guestVisible[o] ?? 0),
    };
    options.sort((a, b) => totals[b]!.compareTo(totals[a]!));
    // Visible total — real food items only (kitchen preparation numbers).
    final actual = totals.values.fold<int>(0, (a, b) => a + b);
    // ISSUE-016: with per-option quantities the display total is PLATES, not
    // people — validate headcount from pick rows (+ guest plates) when the
    // backend provides them; legacy payloads keep the plate-total check.
    // The respondent count from the backend ALREADY includes NONE pickers
    // (their selection rows ride the same aggregate); the raw guest total
    // (visible + NONE picks) is the guest headcount on single-pick groups.
    // ISSUE-002 (Live-Test-13): guest HEADCOUNT for this group.
    //
    // guestVisible/guestNone sum QUANTITY (portions the kitchen prepares), so
    // a guest ordering "Chicken ×3" used to count as THREE people here — the
    // headcount then exceeded the expected number of people and raised a
    // permanent red mismatch on every Quantity-enabled group. When the backend
    // supplies distinct guest respondents, use that; older cached payloads
    // fall back to the legacy plate total (unchanged behaviour).
    final guestActual = guestPickCount ??
        (guestVisible.values.fold<int>(0, (a, b) => a + b) + guestNone);
    final headcount = memberPickCount != null
        ? memberPickCount! + guestActual
        : actual + memberNone + guestActual;
    // ISSUE-006 validation:
    //  • Multiple Pick / Quantity (CASE_4/5/6): totals are selections or
    //    portions — per-record rules are server-enforced, never a mismatch.
    //  • Optional group: members may answer nothing — never a mismatch.
    //  • Single Pick required (CASE_2/3): every expected head must have
    //    answered (visible + hidden NONE == expected).
    final ok = multiPick || !requiredGroup || headcount == expectedTotal;
    // Multi-pick / quantity chips read "X of Y ✓" — X = selections/portions,
    // Y = expected heads (they legitimately differ, CASE_4/6).
    final showOfChip = multiPick || quantityEnabled;
    final hasGuestData = guestVisible.values.any((v) => v > 0);
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              // Validated total chip: ✓ N (green) or ⚠ (red).
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (ok ? AppColors.present : AppColors.absent)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (ok ? AppColors.present : AppColors.absent)
                          .withValues(alpha: 0.35)),
                ),
                child: Text(
                  // ISSUE-006: Multiple Pick / Quantity chips read
                  // "X of Y ✓" (X = selections/portions, Y = expected heads);
                  // Single Pick keeps the validated "Total N ✓".
                  showOfChip
                      ? (ok
                          ? '$actual of $expectedTotal ✓'
                          : '⚠ $actual of $expectedTotal')
                      : ok
                          ? 'Total $actual ✓'
                          : '⚠ $headcount of $expectedTotal',
                  style: AppTypography.labelSmall.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ok ? AppColors.present : AppColors.absent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...options.map((o) {
            String label = o;
            if (resolveDisplay) {
              final disp = MealPreferenceOption.display(o);
              label = disp.emoji.isEmpty
                  ? disp.label
                  : '${disp.emoji} ${disp.label}';
            }
            final m = memberCounts[o] ?? 0;
            final g = guestCounts[o] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (hasGuestData) ...[
                    Text(
                      'M $m · G $g',
                      style: AppTypography.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    '${totals[o]}',
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (!ok) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.absent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: AppColors.absent.withValues(alpha: 0.35)),
              ),
              child: Text(
                // ISSUE-004: the check compares people who ANSWERED (1 member
                // = 1, regardless of picks/quantities) against Present +
                // approved guests — plate totals may legitimately be larger.
                '⚠ Dashboard Data Mismatch — expected $expectedTotal '
                'answered, found $headcount. Preferences are mandatory; '
                'investigate this meal\'s records.',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.absent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(
      {required this.label,
      required this.value,
      required this.color,
      required this.width});
  final String label;
  final int value;
  final Color color;

  /// Explicit width — pills live inside a [Wrap], which is not a Flex, so
  /// [Expanded] is illegal there (ParentDataWidget error → grey ErrorWidget
  /// in release builds). The parent computes an equal-column width instead.
  final double width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          // Vibrant two-tone wash — richer at the top, airy at the bottom —
          // with a stronger accent border for that executive-tile pop.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: isDark ? 0.24 : 0.13),
              color.withValues(alpha: isDark ? 0.08 : 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: color.withValues(alpha: isDark ? 0.45 : 0.30)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            // One line, auto-scaled down on very narrow widths — the label
            // can never wrap (uneven pill heights) or clip on any device.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: AppTypography.labelSmall.copyWith(color: color),
              ),
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

  @override
  Widget build(BuildContext context) {
    final time = record.markedAt != null
        ? TimeFormat.tod12(TimeOfDay.fromDateTime(record.markedAt!))
        : '--:--';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // ISSUE-003: member profile photo with a status-tinted ring (the
          // status itself stays on the right-hand chip) — consistent with the
          // attendance roster rows. Initials fallback when no photo.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: _color.withValues(alpha: 0.55), width: 2),
            ),
            padding: const EdgeInsets.all(2),
            child: UserAvatar(
              name: record.userName ?? 'Member',
              avatarUrl: record.userAvatarUrl,
              radius: 15,
            ),
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
