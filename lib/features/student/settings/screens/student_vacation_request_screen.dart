import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/repositories/vacation_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';
import 'package:smart_meal_management/features/student/settings/utils/vacation_today_availability.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/models/vacation_request_model.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Issue 3 — Student "Request Vacation" screen.
///
/// A member submits a date-range vacation request that an admin approves or
/// rejects. Additive: the existing self-service Vacation Mode toggle still
/// works independently; this adds the approval workflow on top.
///
/// Pass 11 (FR-VACX-003): optional meal-granular boundaries — "leaving after
/// lunch" / "back before dinner". Slot chips appear only when the group's
/// meals load (best-effort); otherwise requests cover whole days, exactly the
/// previous behaviour.
class StudentVacationRequestScreen extends StatefulWidget {
  const StudentVacationRequestScreen({
    super.key,
    this.organizationId,
    this.groupId,
  });

  /// Optional group context used to load meal slots for boundary chips.
  final String? organizationId;
  final String? groupId;

  @override
  State<StudentVacationRequestScreen> createState() =>
      _StudentVacationRequestScreenState();
}

class _StudentVacationRequestScreenState
    extends State<StudentVacationRequestScreen> {
  final _repo = VacationRepository();
  final _reasonCtrl = TextEditingController();

  DateTime? _start;
  DateTime? _end;
  bool _submitting = false;
  bool _loading = true;
  String? _error;
  List<VacationRequestModel> _mine = [];

  // Pass 11 (FR-VACX-003): meal-granular boundary slots. Best-effort — the
  // chips only render when the group's meals load; null = whole day.
  List<MealModel> _slotMeals = [];
  String? _startSlot;
  String? _endSlot;

  // Live-Test-16 ISSUE-19: vacation is GROUP-scoped — one request per group.
  // Groups come from the signed-in session (no network call).
  List<UserGroupBrief> _groups = const [];
  String? _groupId;
  String? _orgId;
  String? _userId;
  bool _groupsResolved = false;
  // "Your requests" group filter (null = all groups).
  String? _listGroupFilter;

  // Live-Test-16 ISSUE-2: which of today's meals can still be covered.
  VacationTodayAvailability? _today;

  // ISSUE-2: the shell's dashboard provider, looked up ONCE without
  // subscribing (this screen only reads its already-loaded data; listening
  // would rebuild the form on every dashboard/realtime update).
  StudentDashboardProvider? _dash;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_groupsResolved) return;
    _groupsResolved = true;
    final user = AuthProviderScope.of(context).currentUser;
    _dash = context
        .getInheritedWidgetOfExactType<StudentDashboardScope>()
        ?.notifier;
    _groups = user?.groups ?? const [];
    _orgId = widget.organizationId ?? user?.organizationId;
    _userId = user?.id;
    // Default to the group the caller / shell is showing; else the session's.
    final ids = _groups.map((g) => g.id).toSet();
    final candidates = [
      widget.groupId,
      _dash?.loadedGroupId,
      user?.groupId,
      if (_groups.isNotEmpty) _groups.first.id,
    ];
    _groupId = candidates.firstWhere(
      (id) => id != null && id.isNotEmpty && (ids.isEmpty || ids.contains(id)),
      orElse: () => null,
    );
    _loadSlots();
  }

  /// ISSUE-19: switch the group the NEXT request is for. Everything
  /// group-specific (slot chips, today's availability, chosen dates) resets.
  void _selectGroup(String groupId) {
    if (groupId == _groupId) return;
    setState(() {
      _groupId = groupId;
      _slotMeals = [];
      _today = null;
      _start = null;
      _end = null;
      _startSlot = null;
      _endSlot = null;
      _error = null;
    });
    _loadSlots();
  }

  String _groupName(String? id) {
    if (id == null) return 'All groups';
    for (final g in _groups) {
      if (g.id == id) return g.name;
    }
    return 'Group';
  }

  Future<void> _loadSlots() async {
    final orgId = _orgId;
    final groupId = _groupId;
    if (orgId == null || orgId.isEmpty || groupId == null || groupId.isEmpty) {
      return;
    }
    // ISSUE-2: today's availability — reuse the dashboard's ALREADY-LOADED
    // meals + records when it shows this same group (zero network); else
    // one parallel wave with the slot read.
    final dash = _dash;
    final reuse = dash != null && dash.loadedGroupId == groupId;
    final slotsF =
        MealRepository().getGroupMeals(organizationId: orgId, groupId: groupId);
    final todayMealsF = reuse
        ? null
        : MealRepository().getTodayMeals(organizationId: orgId, groupId: groupId);
    final todayRecsF = reuse || _userId == null
        ? null
        : AttendanceRepository().getTodayAttendance(
            userId: _userId!, groupId: groupId, organizationId: orgId);
    final fetchedAt = DateTime.now();
    final res = await slotsF;
    VacationTodayAvailability? today;
    if (reuse) {
      today = VacationTodayAvailability.compute(
        todayMeals: dash.todayMeals,
        myTodayRecords: dash.todayAttendance,
        fetchedAt: dash.mealsFetchedAt,
      );
    } else if (todayMealsF != null) {
      final tm = await todayMealsF;
      final tr = todayRecsF == null ? null : await todayRecsF;
      if (tm case Ok(value: final meals)) {
        final recs = <AttendanceModel>[];
        if (tr case Ok(value: final list)) {
          recs.addAll(list.where((r) => r.userId == _userId));
        }
        today = VacationTodayAvailability.compute(
          todayMeals: meals,
          myTodayRecords: recs,
          fetchedAt: fetchedAt,
        );
      }
    }
    if (!mounted || groupId != _groupId) return; // stale group switch
    setState(() {
      _today = today;
      if (res case Ok(:final value)) {
        final meals = value.where((m) => m.isActive).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        // Boundary chips only make sense with 2+ distinct slots.
        final seen = <String>{};
        final distinct = meals.where((m) => seen.add(m.slotKey)).toList();
        _slotMeals = distinct.length >= 2 ? distinct : [];
      }
      // A start/end picked before this load finished is re-validated now.
      _normalizeTodaySlots();
    });
  }

  /// ISSUE-2: the org business day (server), device day as fallback.
  DateTime get _todayDay {
    final o = _today?.orgToday;
    if (o != null) return DateTime(o.year, o.month, o.day);
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isToday(DateTime? d) =>
      d != null &&
      d.year == _todayDay.year &&
      d.month == _todayDay.month &&
      d.day == _todayDay.day;

  /// ISSUE-2: keeps today's slot choices valid — a meal already past or
  /// taken can never be the boundary, and "Whole day" gives way to the first
  /// upcoming meal once anything today is decided.
  void _normalizeTodaySlots() {
    final t = _today;
    if (t == null || _slotMeals.isEmpty) return;
    String? firstUpcoming() {
      for (final m in _slotMeals) {
        if (t.upcomingSlotKeys.contains(m.slotKey)) return m.slotKey;
      }
      return null;
    }

    if (_isToday(_start)) {
      if (_startSlot == null
          ? !t.wholeDayTodayAllowed
          : t.blockedSlotKeys.contains(_startSlot)) {
        _startSlot = firstUpcoming();
      }
    }
    if (_isToday(_end) &&
        _endSlot != null &&
        t.blockedSlotKeys.contains(_endSlot)) {
      _endSlot = null;
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    setState(() => _loading = true);
    final res = await _repo.list();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _mine = value.data;
          _loading = false;
        });
      case Err(:final failure):
        setState(() {
          _error = failure.message;
          _loading = false;
        });
    }
  }

  Future<void> _pick(bool isStart) async {
    // ISSUE-005: date-only anchors (no time component) so the picker can
    // never render/return an off-by-one day around midnight, and the END
    // picker can never go before the chosen start (19/07 → 18/07 bug).
    // Live-Test-16 ISSUE-2: org business day; when every meal today is past
    // or taken, vacation can start tomorrow at the earliest.
    final today = _todayDay;
    final earliest = (_today?.hasUpcomingToday ?? true)
        ? today
        : today.add(const Duration(days: 1));
    final minDate = isStart ? earliest : (_start ?? earliest);
    var initial = isStart
        ? (_start ?? today)
        : (_end ?? _start ?? today.add(const Duration(days: 1)));
    if (initial.isBefore(minDate)) initial = minDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minDate,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
      _normalizeTodaySlots();
    });
  }

  /// ISSUE-005: boundary slots display the MEAL NAME, never a raw slotKey
  /// ("(dinner+)" stays readable even for custom slots like test_meal_03).
  String _slotName(String slotKey) {
    for (final m in _slotMeals) {
      if (m.slotKey == slotKey) return m.name;
    }
    return slotKey;
  }

  Future<void> _submit() async {
    if (_start == null || _end == null) {
      setState(() => _error = 'Pick both a start and end date.');
      return;
    }
    // Live-Test-16 ISSUE-2: never submit a boundary on a meal already past or
    // taken today (the server re-checks — VACATION_MEAL_ALREADY_TAKEN).
    final t = _today;
    if (t != null && _isToday(_start)) {
      final invalid = _startSlot == null
          ? !t.wholeDayTodayAllowed
          : t.blockedSlotKeys.contains(_startSlot);
      if (invalid) {
        setState(() => _error =
            'Vacation can only start from an upcoming meal today.');
        return;
      }
    }
    // Premium confirmation so the member understands what vacation mode does and
    // that it only activates after an admin approves the request.
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const _VacationRequestConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await _repo.createRequest(
      startDate: _start!,
      endDate: _end!,
      reason: _reasonCtrl.text.trim(),
      // Live-Test-16 ISSUE-19: the request covers THIS group only.
      groupId: _groupId,
      // FR-VACX-003: boundary slots (null = whole day).
      startSlotKey: _startSlot,
      endSlotKey: _endSlot,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (res) {
      case Ok():
        _reasonCtrl.clear();
        setState(() {
          _start = null;
          _end = null;
          _startSlot = null;
          _endSlot = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vacation request submitted.')),
        );
        _loadMine();
      case Err(:final failure):
        setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Request Vacation', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          // Live-Test-16 ISSUE-19: which group this request is for.
          if (_groups.isNotEmpty) ...[
            _groupPicker(isDark),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(child: _dateField('Start', _start, () => _pick(true), isDark)),
              const SizedBox(width: 12),
              Expanded(child: _dateField('End', _end, () => _pick(false), isDark)),
            ],
          ),
          // FR-VACX-003: optional meal-granular boundaries.
          if (_slotMeals.isNotEmpty) ...[
            const SizedBox(height: 16),
            _slotPicker(
              'First covered meal on the start day',
              _isToday(_start) && _today != null && !_today!.wholeDayTodayAllowed
                  ? 'Meals already taken or closed today are hidden'
                  : 'e.g. leaving after lunch → pick Dinner',
              _startSlot,
              (v) => setState(() => _startSlot = v),
              isDark,
              forToday: _isToday(_start),
            ),
            const SizedBox(height: 12),
            _slotPicker(
              'Last covered meal on the end day',
              'e.g. back before dinner → pick Lunch',
              _endSlot,
              (v) => setState(() => _endSlot = v),
              isDark,
              forToday: _isToday(_end),
              isEnd: true,
            ),
          ],
          const SizedBox(height: 16),
          Text('Reason (optional)',
              style: AppTypography.labelMedium
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'e.g. Travelling home for the week',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(backgroundColor: AppColors.vacation),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.beach_access_rounded),
              label: Text(_submitting ? 'Submitting...' : 'Submit request'),
            ),
          ),
          const SizedBox(height: 28),
          Text('Your requests',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w700)),
          // ISSUE-19: filter the list per group when the member has several.
          if (_groups.length > 1) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('All', _listGroupFilter == null,
                      () => setState(() => _listGroupFilter = null), isDark),
                  for (final g in _groups)
                    _filterChip(g.name, _listGroupFilter == g.id,
                        () => setState(() => _listGroupFilter = g.id), isDark),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_loading)
            const AppSheetSkeleton(rows: 3, rowHeight: 72, padding: EdgeInsets.symmetric(vertical: 8))
          else if (_visibleMine.isEmpty)
            Text('No requests yet.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary))
          else
            ..._visibleMine.map((r) => _requestTile(r, isDark)),
        ],
      ),
    );
  }

  /// ISSUE-19: requests shown for the selected group filter. A legacy
  /// org-level request (no group) covers every group, so it always shows.
  List<VacationRequestModel> get _visibleMine => _listGroupFilter == null
      ? _mine
      : _mine
          .where((r) => r.groupId == null || r.groupId == _listGroupFilter)
          .toList();

  /// Live-Test-16 ISSUE-19: premium group selector — vacation is requested
  /// per group; a member in several groups makes one request per group.
  Widget _groupPicker(bool isDark) {
    final single = _groups.length == 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.vacation.withValues(alpha: isDark ? 0.22 : 0.12),
            AppColors.primary.withValues(alpha: isDark ? 0.14 : 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.vacation.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded,
                  size: 18, color: AppColors.vacation),
              const SizedBox(width: 8),
              Text(single ? 'Vacation for' : 'Request vacation for',
                  style: AppTypography.labelMedium
                      .copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            single
                ? 'Applies to this group only.'
                : 'Applies to the selected group only — request each group separately.',
            style: AppTypography.labelSmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in _groups)
                _slotChip(
                  label: g.name,
                  selected: g.id == _groupId,
                  onTap: () => _selectGroup(g.id),
                  isDark: isDark,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
      String label, bool selected, VoidCallback onTap, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.vacation.withValues(alpha: 0.18),
        labelStyle: AppTypography.labelSmall.copyWith(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected
              ? AppColors.vacation
              : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
        ),
        side: BorderSide(
          color: selected
              ? AppColors.vacation
              : (isDark ? AppColors.borderDark : AppColors.border),
        ),
        showCheckmark: false,
      ),
    );
  }

  /// FR-VACX-003: "Whole day" + one chip per group meal slot. Premium card +
  /// high-contrast selectable chips (command_3): the old default ChoiceChips
  /// were near-invisible in both light and dark mode.
  ///
  /// Live-Test-16 ISSUE-2: on TODAY ([forToday]) meals already past or taken
  /// are omitted, and "Whole day" is offered on the start day only while
  /// nothing today is decided yet.
  Widget _slotPicker(
    String title,
    String hint,
    String? selected,
    ValueChanged<String?> onChanged,
    bool isDark, {
    bool forToday = false,
    bool isEnd = false,
  }) {
    final t = forToday ? _today : null;
    // Today: only meals actually SERVED today and still upcoming. A master
    // slot absent from today's published day is not offered (it would be an
    // unresolvable boundary). No published meals today → whole day only.
    final slots = t == null
        ? _slotMeals
        : _slotMeals
            .where((m) => t.upcomingSlotKeys.contains(m.slotKey))
            .toList();
    final showWholeDay = t == null || isEnd || t.wholeDayTodayAllowed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTypography.labelMedium
                  .copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(hint,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (showWholeDay)
                _slotChip(
                  label: 'Whole day',
                  selected: selected == null,
                  onTap: () => onChanged(null),
                  isDark: isDark,
                ),
              ...slots.map(
                (m) => _slotChip(
                  label: m.name,
                  selected: selected == m.slotKey,
                  onTap: () => onChanged(m.slotKey),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// High-contrast Material-3 selectable chip. Selected = filled vacation
  /// accent + white label + check; unselected = surface + visible border +
  /// primary-text label. Readable in BOTH themes (fixes the reported bug).
  Widget _slotChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    const accent = AppColors.vacation;
    final unselectedBg =
        (isDark ? AppColors.backgroundDark : AppColors.background);
    final unselectedFg =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final unselectedBorder =
        (isDark ? AppColors.borderDark : AppColors.border);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? accent : unselectedBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : unselectedBorder,
              width: selected ? 1.5 : 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ],
              // Live-Test-16 ISSUE-19: this chip now also carries GROUP names
              // (can be long). A label that fits renders exactly as before; a
              // longer one ellipsizes instead of overflowing on small phones.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: selected ? Colors.white : unselectedFg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField(
      String label, DateTime? value, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded,
                size: 18, color: AppColors.vacation),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textSecondary)),
                Text(
                  value == null ? 'Select' : _fmt(value),
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestTile(VacationRequestModel r, bool isDark) {
    final c = switch (r.status) {
      'approved' => AppColors.present,
      'rejected' => AppColors.absent,
      'cancelled' => AppColors.textTertiary,
      _ => AppColors.warning,
    };
    // ISSUE-2B (USER-LOCKED): approved + ended => permanent record, never
    // cancellable. Shared getter, identical to the admin screen + server rule.
    final canCancel = r.isCancellable;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${_fmt(r.startDate)}${r.startSlotKey != null ? ' (from ${_slotName(r.startSlotKey!)})' : ''}'
                    '  →  '
                    '${_fmt(r.endDate)}${r.endSlotKey != null ? ' (till ${_slotName(r.endSlotKey!)})' : ''}',
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                if (r.reason != null && r.reason!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(r.reason!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
                // ISSUE-19: which group this request covers.
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.vacation.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.groups_rounded,
                          size: 12, color: AppColors.vacation),
                      const SizedBox(width: 4),
                      Text(_groupName(r.groupId),
                          style: AppTypography.labelSmall.copyWith(
                              color: AppColors.vacation,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(r.status[0].toUpperCase() + r.status.substring(1),
                style: AppTypography.labelSmall
                    .copyWith(color: c, fontWeight: FontWeight.w700)),
          ),
          if (canCancel)
            TextButton(
              onPressed: () async {
                final res = await _repo.cancel(r.id);
                if (!mounted) return;
                if (res case Err(:final failure)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(failure.message)));
                } else {
                  _loadMine();
                }
              },
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}


// ── Premium vacation-request confirmation dialog ───────────────────────────────
//
// Reuses the original premium "Vacation Mode" dialog design (previously shown for
// the self-enable toggle). It now appears when a member SUBMITS a vacation
// request, so they understand that — once an admin approves — attendance tracking
// and meal reminders pause for the selected dates.
class _VacationRequestConfirmDialog extends StatelessWidget {
  const _VacationRequestConfirmDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.dialogRadius),
          border: Border.all(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.vacation.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.beach_access_rounded,
                color: AppColors.vacation,
                size: 26,
              ),
            ),
            const SizedBox(height: AppConstants.space16),
            Text(
              'Submit Vacation Request?',
              style: AppTypography.titleMedium.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'Once your admin approves, attendance tracking and all meal '
              'reminders will be paused for the selected dates. You can turn it '
              'off early if you return.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              isDark ? AppColors.borderDark : AppColors.border,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppConstants.buttonRadius),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: AppTypography.labelMedium.copyWith(
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.vacation,
                        borderRadius:
                            BorderRadius.circular(AppConstants.buttonRadius),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.vacation.withValues(alpha: 0.30),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Submit Request',
                          style: AppTypography.labelMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
