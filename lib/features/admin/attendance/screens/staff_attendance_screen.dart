import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/data/services/selected_group_store.dart';
import 'package:smart_meal_management/data/services/selected_group_subscription.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/utils/attendance_window.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';
import 'package:smart_meal_management/shared/widgets/preference_group_selector.dart';
// Live-Test-14 ISSUE-001: the admin reuses the MEMBER sheets verbatim — one
// correction flow and one guest flow for the whole product, no admin-only fork.
import 'package:smart_meal_management/features/student/attendance/widgets/correction_request_sheet.dart';
import 'package:smart_meal_management/features/student/attendance/widgets/guest_sheet.dart';

/// Issue 5 — Staff (admin / manager) self-attendance.
///
/// Additive, self-contained screen. It reuses the EXISTING attendance endpoint
/// (`markAttendance`) which already authorises any active group member — admins
/// and managers are members, so no backend / contract / schema change is needed.
/// A staff member picks one of their groups, sees today's active meals, and
/// marks Present / Skip / Absent exactly like a student. The backend enforces
/// the attendance window (returns a friendly error if closed), so this never
/// bypasses the rules.
class StaffAttendanceScreen extends StatefulWidget {
  const StaffAttendanceScreen({super.key});

  @override
  State<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends State<StaffAttendanceScreen> {
  final _groupRepo = GroupRepository();
  final _mealRepo = MealRepository();
  final _attendanceRepo = AttendanceRepository();

  bool _loadingGroups = true;
  bool _loading = false;
  String? _error;
  String? _busyMealId;
  // Issue 2: which action is in flight, so only the tapped button animates.
  AttendanceStatus? _busyStatus;

  // Issue 5: per-meal selected meal preference (parity with the student flow).
  // When a meal has preferences enabled, "Present" stays disabled until the
  // admin picks one — exactly like members.
  final Map<String, String?> _selectedPref = {};

  // FR-PG parity: per-meal preference-GROUP selections (Module 36). When the
  // meal carries explicit preference groups, they take precedence over the
  // flat chips (same rule as the member card) and "Present" stays disabled
  // until every required group is satisfied.
  final Map<String, List<PreferenceSelection>> _groupSelections = {};
  final Map<String, bool> _groupSelectionsComplete = {};

  List<GroupModel> _groups = [];
  String? _groupId;
  List<MealModel> _meals = [];
  List<AttendanceModel> _records = [];

  /// ISSUE-001: when [_meals] arrived, so the shared window gate can advance the
  /// SERVER's org clock by elapsed device time instead of trusting the phone's
  /// wall clock (a wrong timezone must never open or close a window).
  DateTime? _mealsFetchedAt;

  /// The selected group's row — carries `mealConfig` (guest policy, pricing,
  /// preferences), so the guest action needs NO extra request: it rides the
  /// `admin_groups:{org}` list this screen already loads.
  GroupModel? get _selectedGroup {
    for (final g in _groups) {
      if (g.id == _groupId) return g;
    }
    return null;
  }

  String _orgId = '';
  String _userId = '';

  // ── ISSUE-003 app-wide group selection ─────────────────────────────────────

  SelectedGroupSubscription? _groupSelSub;

  /// Org the subscription is bound to — an ORG switch must rebind.
  String? _groupSelOrgId;

  /// The app-wide selected group when it exists in [list]; first group is only
  /// a fallback for a fresh install / stale-or-foreign stored id.
  String? _resolveSelected(List<GroupModel> list) {
    final saved = SelectedGroupStore.instance.peek(_orgId);
    if (saved != null && list.any((g) => g.id == saved)) return saved;
    return list.isNotEmpty ? list.first.id : null;
  }

  /// Follow group switches made on ANY other tab.
  void _bindGroupSelection(String organizationId) {
    if (_groupSelSub != null && _groupSelOrgId == organizationId) return;
    _groupSelSub?.cancel();
    _groupSelOrgId = organizationId;
    _groupSelSub = SelectedGroupSubscription.bind(
      organizationId: organizationId,
      isCurrent: (id) => _groupId == id,
      onChanged: (id) {
        if (!mounted) return;
        if (_groups.isNotEmpty && !_groups.any((g) => g.id == id)) return;
        setState(() => _groupId = id);
        unawaited(_load());
      },
    );
  }

  @override
  void dispose() {
    _groupSelSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null) {
      setState(() {
        _loadingGroups = false;
        _error = 'You must be signed in to mark attendance.';
      });
      return;
    }
    _orgId = user.organizationId;
    _userId = user.id;
    // ISSUE-003: prime the store so _resolveSelected's sync peek sees the
    // persisted selection, and follow switches made on any other tab.
    await SelectedGroupStore.instance.read(_orgId);
    if (!mounted) return;
    _bindGroupSelection(_orgId);

    // Cache-first: paint the group selector from the shared org-groups cache
    // and start today's data immediately — the network refresh below runs in
    // the same wave and reconciles silently.
    // Miss-vs-empty aware: a cached EMPTY org (no groups yet) paints its real
    // empty state instantly; only a true cache MISS keeps the loader.
    final cached = await ResponseCacheService.instance.readListOrNull(
        'admin_groups:$_orgId', GroupModel.fromJson,
        maxAge: const Duration(hours: 12));
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _groups = cached;
        // ISSUE-003: the app-wide selected group wins; first group is only a
        // fallback. Defaulting to the first group made this tab silently
        // disagree with Home/Meals/Billing (the exact TYPE-1 symptom).
        _groupId = _resolveSelected(cached);
        _loadingGroups = false;
      });
      if (_groupId != null) unawaited(_load());
    }

    final prevSel = _groupId;
    final res = await _groupRepo.getOrganisationGroups(organizationId: _orgId);
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        _groups = value.data;
        _groupId ??= _resolveSelected(_groups);
      case Err(:final failure):
        if (_groups.isEmpty) _error = failure.message;
    }
    setState(() => _loadingGroups = false);
    // Avoid a duplicate fetch when the cached path already loaded this group.
    if (_groupId != null && _groupId != prevSel) await _load();
  }

  Future<void> _load() async {
    final gid = _groupId;
    if (gid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    // Independent reads — one parallel wave, not two sequential round-trips.
    final mealsF = _mealRepo.getTodayMeals(
      organizationId: _orgId,
      groupId: gid,
    );
    final recF = _attendanceRepo.getTodayAttendance(
      userId: _userId,
      groupId: gid,
      organizationId: _orgId,
    );
    final mealsRes = await mealsF;
    final recRes = await recF;
    if (!mounted) return;

    List<MealModel> meals = [];
    if (mealsRes case Ok(:final value)) {
      meals = value.where((m) => m.isActive).toList()
        ..sort(MealModel.compareChronological);
    } else if (mealsRes case Err(:final failure)) {
      _error = failure.message;
    }
    List<AttendanceModel> records = [];
    if (recRes case Ok(:final value)) {
      // GET /attendance/today is role-scoped server-side: for an admin it
      // returns GROUP-WIDE records (every member). This screen marks the
      // ADMIN'S OWN attendance, so keep ONLY the signed-in admin's records —
      // otherwise a member's status would surface as the admin's own.
      records = value.where((r) => r.userId == _userId).toList();
    }

    setState(() {
      _meals = meals;
      _records = records;
      // ISSUE-001: only a LIVE payload carries orgClockMinutes; stamping it here
      // is what makes the window gate server-authoritative.
      _mealsFetchedAt = DateTime.now();
      _loading = false;
    });
  }

  AttendanceStatus? _statusFor(String mealId) => _recordFor(mealId)?.status;

  /// Today's own record for [mealId], or null when nothing has been marked.
  AttendanceModel? _recordFor(String mealId) {
    final now = DateTime.now();
    for (final r in _records) {
      if (r.mealId == mealId &&
          r.date.year == now.year &&
          r.date.month == now.month &&
          r.date.day == now.day) {
        return r;
      }
    }
    return null;
  }

  Future<void> _mark(MealModel meal, AttendanceStatus status,
      {String? preference, List<PreferenceSelection>? selections}) async {
    final gid = _groupId;
    if (gid == null || _busyMealId != null) return;
    setState(() {
      _busyMealId = meal.id;
      _busyStatus = status;
    });

    final now = DateTime.now();
    final existing = _records.indexWhere((r) =>
        r.mealId == meal.id &&
        r.date.year == now.year &&
        r.date.month == now.month &&
        r.date.day == now.day);

    final record = existing != -1
        ? _records[existing].copyWith(
            status: status,
            markedAt: now,
            preference: preference,
            selections: selections)
        : AttendanceModel(
            id: 'temp_${meal.id}_${now.millisecondsSinceEpoch}',
            mealId: meal.id,
            userId: _userId,
            groupId: gid,
            organizationId: _orgId,
            status: status,
            date: now,
            markedAt: now,
            preference: preference,
            selections: selections,
          );

    // SRS Module 03 ATT-004: the endpoint now treats an admin marking their
    // OWN attendance as member behaviour — the server delegates to the normal
    // marking path, so windows/vacation rules apply to admins exactly like
    // every member. After close, admins use Correction Requests too.
    final res = await _attendanceRepo.adminOverride(record: record);
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        final i = _records.indexWhere((r) =>
            r.mealId == meal.id &&
            r.date.year == now.year &&
            r.date.month == now.month &&
            r.date.day == now.day);
        setState(() {
          if (i != -1) {
            _records = List.of(_records)..[i] = value;
          } else {
            _records = [..._records, value];
          }
          _busyMealId = null;
          _busyStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked ${_label(status)} for ${meal.name}.')),
        );
      case Err(:final failure):
        setState(() {
          _busyMealId = null;
          _busyStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
    }
  }

  /// ISSUE-001: the meal's ORG business date (never the phone's calendar) —
  /// the same date the backend keyed today's attendance under.
  String _orgDateStr(MealModel meal) {
    final s = meal.orgDate;
    if (s != null && s.length >= 10) return s.substring(0, 10);
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// ISSUE-001 — same-day CORRECTION for the admin's own record.
  ///
  /// Reuses the member correction sheet unchanged. The difference is entirely
  /// server-side and deliberate: `CorrectionsService.createRequest` detects that
  /// the requester holds an admin role and applies the change IMMEDIATELY
  /// ("admin no need to any approval"), so the sheet comes back already
  /// approved. Every other rule still binds — same calendar day only, window
  /// must have closed, full preference validation, no claim while on vacation.
  Future<void> _openCorrectionSheet(MealModel meal) async {
    final created = await showCorrectionRequestSheet(
      context,
      meals: _meals,
      initialMeal: meal,
    );
    if (!mounted || created == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(created.isApproved
            ? 'Applied — your record has been corrected.'
            : 'Request sent — awaiting review.'),
      ),
    );
    // An applied correction changed today's record — repaint from the server.
    if (created.isApproved) await _load();
  }

  /// ISSUE-001 — the admin's OWN hosted guests, at parity with members.
  ///
  /// The admin is the host here, not an admin acting on someone's behalf, so the
  /// member sheet is used as-is (`asAdmin: false`). The backend already treats
  /// an admin booking guests for themselves as self-approved (Live-Test-11
  /// ISSUE-003 `adminSelf`), which is exactly the "no approval needed" rule.
  Future<void> _openGuestSheet(MealModel meal) async {
    final config = _selectedGroup?.mealConfig ?? const GroupMealConfig();
    final record = _recordFor(meal.id);
    final enabledPrefs = meal.enabledPreferences.isNotEmpty
        ? meal.enabledPreferences
        : config.enabledPreferences.map((e) => e.name).toList();
    final changed = await showGuestSheet(
      context,
      mealId: meal.id,
      mealName: meal.name,
      dateStr: _orgDateStr(meal),
      config: config.guestConfig,
      pricingEnabled: config.mealPricingEnabled,
      enabledPreferences: enabledPrefs,
      preferenceGroups: meal.preferenceGroups,
      mealPrice: record?.price ?? meal.price,
      currentUserId: _userId,
    );
    // Guests change the host's counters and billing — refresh silently.
    if (changed == true && mounted) await _load();
  }

  String _label(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.skipped:
        return 'Skipped';
      default:
        return s.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Mark My Attendance')),
      body: _loadingGroups
          ? const AppListSkeleton(rows: 4, rowHeight: 120, headerHeight: 48)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    'Mark your own meal attendance for today, just like a member.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_groups.isNotEmpty) _groupSelector(isDark),
                  const SizedBox(height: 16),
                  if (_loading)
                    const AppSheetSkeleton(rows: 3, rowHeight: 110, padding: EdgeInsets.symmetric(vertical: 24))
                  else if (_error != null)
                    _infoCard(isDark, _error!, AppColors.error)
                  else if (_meals.isEmpty)
                    _infoCard(
                      isDark,
                      'No active meals configured for this group today.',
                      AppColors.primary,
                    )
                  else
                    ..._meals.map((m) => _mealCard(m, isDark)),
                ],
              ),
            ),
    );
  }

  Widget _groupSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.6),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _groupId,
          items: _groups
              .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
              .toList(),
          onChanged: (v) {
            if (v == null || v == _groupId) return;
            setState(() => _groupId = v);
            // ISSUE-003: an explicit switch here IS the app-wide selection.
            unawaited(SelectedGroupStore.instance.write(_orgId, v));
            _load();
          },
        ),
      ),
    );
  }

  Widget _infoCard(bool isDark, String message, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: AppTypography.bodySmall.copyWith(color: color),
      ),
    );
  }

  Widget _mealCard(MealModel meal, bool isDark) {
    final status = _statusFor(meal.id);
    final busy = _busyMealId == meal.id;
    final open = meal.attendanceWindow.openTime;
    final close = meal.attendanceWindow.closeTime;

    // FR-PG parity (Module 36): explicit preference GROUPS take precedence
    // over the flat chips — exactly the member card's rule. Present unlocks
    // once every required group is satisfied (meals with no required group
    // start unlocked, mirroring the correction sheet).
    final hasGroups = meal.preferenceGroups.isNotEmpty;
    // Live-Test-6 ISSUE-2: the shared no-picks rule (visibleWhen + fail-safe
    // aware) — the selector re-reports on mount and every change.
    final groupsComplete = _groupSelectionsComplete[meal.id] ??
        PreferenceGroupSelector.initialComplete(meal.preferenceGroups);

    // Issue 5: preference parity. When the meal has preferences enabled, the
    // admin must pick one before "Present" — identical to the member flow.
    final prefsOn = !hasGroups &&
        meal.preferencesEnabled &&
        meal.enabledPreferences.isNotEmpty;
    final selectedPref = _selectedPref[meal.id];
    final prefsSatisfied =
        hasGroups ? groupsComplete : (!prefsOn || selectedPref != null);

    // ── ISSUE-001: window gating (shared gate, identical to the member card) ──
    //
    // Present/Absent used to render ENABLED at all times. After close the tap
    // reached the server, which correctly refused with "cannot mark attendance,
    // window from xx to xx" — an always-failing button. The buttons now follow
    // the real window state, and once it has closed the same-day CORRECTION
    // action below is the only (and correct) route, exactly as for members.
    final windowOpen =
        AttendanceWindow.isOpen(meal, fetchedAt: _mealsFetchedAt);
    final windowPast =
        AttendanceWindow.isPast(meal, fetchedAt: _mealsFetchedAt);
    final canMark = windowOpen && !busy;
    final canPresent = prefsSatisfied && canMark;

    final config = _selectedGroup?.mealConfig ?? const GroupMealConfig();
    // Guest hosting mirrors the member rule: guest-enabled Meal-Mode group, and
    // the host must actually be Present for the meal they are bringing guests to.
    final canHostGuests =
        config.guestsEnabled && status == AttendanceStatus.present;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meal.name,
                  style: AppTypography.labelLarge
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (status != null) _statusPill(status),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Window  ${TimeFormat.window12(open, close)}',
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              // ISSUE-001: say WHY the buttons are disabled, instead of letting
              // the admin discover it by tapping and getting an error.
              if (!windowOpen)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (windowPast ? AppColors.textTertiary : AppColors.info)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        windowPast
                            ? Icons.lock_clock_rounded
                            : Icons.schedule_rounded,
                        size: 12,
                        color: windowPast
                            ? AppColors.textSecondary
                            : AppColors.info,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        windowPast ? 'Closed' : 'Not open yet',
                        style: AppTypography.labelSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: windowPast
                              ? AppColors.textSecondary
                              : AppColors.info,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // ── Preference groups (FR-PG parity with the member card) ─────────
          if (hasGroups) ...[
            const SizedBox(height: 12),
            PreferenceGroupSelector(
              groups: meal.preferenceGroups,
              enabled: !busy,
              onChanged: (selections, delta, complete) => setState(() {
                _groupSelections[meal.id] = selections;
                _groupSelectionsComplete[meal.id] = complete;
              }),
            ),
          ],
          // ── Preference chips (Issue 5 parity) ─────────────────────────────
          if (prefsOn) ...[
            const SizedBox(height: 12),
            Text(
              'Meal preference (required)',
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: meal.enabledPreferences.map((opt) {
                final isSelected = selectedPref == opt;
                final disp = MealPreferenceOption.display(opt);
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedPref[meal.id] = isSelected ? null : opt;
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : isDark
                              ? AppColors.surfaceVariantDark
                              : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.borderDark : AppColors.border)
                                .withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(disp.emoji, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Text(
                          disp.label,
                          style: AppTypography.labelSmall.copyWith(
                            color: isSelected
                                ? Colors.white
                                : isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _actionButton(
                'Present',
                AppColors.present,
                status == AttendanceStatus.present,
                loading: busy && _busyStatus == AttendanceStatus.present,
                enabled: canPresent,
                onTap: () => _mark(meal, AttendanceStatus.present,
                    preference: prefsOn ? selectedPref : null,
                    // FR-PG-031: Present sends the selection set; Absent
                    // needs none (identical to the member card).
                    selections: hasGroups
                        ? (_groupSelections[meal.id] ??
                            const <PreferenceSelection>[])
                        : null),
              ),
              const SizedBox(width: 8),
              // Q17/Q21: Skip button removed — Present or Absent only.
              _actionButton(
                'Absent',
                AppColors.absent,
                status == AttendanceStatus.absent,
                loading: busy && _busyStatus == AttendanceStatus.absent,
                enabled: canMark,
                onTap: () => _mark(meal, AttendanceStatus.absent),
              ),
            ],
          ),
          // ── ISSUE-001: same-day correction + hosted guests ──────────────────
          // These are the two member capabilities the admin's own screen was
          // missing entirely. Correction appears exactly when it becomes the
          // only way to change the record (window closed, still today); Guests
          // appears under the same rule members get.
          if (windowPast || canHostGuests) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (windowPast)
                  Expanded(
                    child: _secondaryAction(
                      icon: Icons.edit_calendar_rounded,
                      label: 'Correction',
                      color: AppColors.primary,
                      enabled: !busy,
                      onTap: () => _openCorrectionSheet(meal),
                    ),
                  ),
                if (windowPast && canHostGuests) const SizedBox(width: 8),
                if (canHostGuests)
                  Expanded(
                    child: _secondaryAction(
                      icon: Icons.group_add_rounded,
                      label: 'Guests',
                      color: AppColors.secondary,
                      enabled: !busy,
                      onTap: () => _openGuestSheet(meal),
                    ),
                  ),
              ],
            ),
            if (windowPast)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'The window has closed. Corrections are allowed for today '
                  'only and, as an admin, yours apply immediately — no '
                  'approval needed.',
                  style: AppTypography.labelSmall.copyWith(
                    height: 1.4,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// ISSUE-001: outlined companion to [_actionButton] — Correction / Guests are
  /// secondary next to the primary Present / Absent pair, so they read as
  /// available without competing for attention.
  Widget _secondaryAction({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: enabled ? 0.08 : 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: enabled ? 0.35 : 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16, color: color.withValues(alpha: enabled ? 1 : 0.4)),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color.withValues(alpha: enabled ? 1 : 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(AttendanceStatus status) {
    Color c;
    switch (status) {
      case AttendanceStatus.present:
        c = AppColors.present;
      case AttendanceStatus.absent:
        c = AppColors.absent;
      case AttendanceStatus.skipped:
        c = AppColors.skipped;
      default:
        c = AppColors.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label(status),
        style: AppTypography.labelSmall
            .copyWith(color: c, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _actionButton(
    String label,
    Color color,
    bool selected, {
    required bool loading,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final active = enabled && !loading;
    return Expanded(
      child: Material(
        color: selected
            ? color
            : color.withValues(alpha: enabled ? 0.10 : 0.04),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: active ? onTap : null,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.white
                          : color.withValues(alpha: enabled ? 1 : 0.4),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
