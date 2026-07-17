import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/guest_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/features/student/attendance/widgets/guest_sheet.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/guest_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Module 22 (Pass 9) — admin hosted-guest management (FR-HG-042/062).
///
/// Shows every guest booked in [group] on [date] with:
///  - **Approve / Reject** for member bookings awaiting admin approval
///  - **Cancel** any booked guest (admins bypass the cutoff — FR-HG-052)
///  - **Add for member** — governed manage-on-behalf: the booking parks as
///    pendingApproval until the HOST confirms the charge (FR-FAIR-001).
Future<void> showAdminGuestsSheet(
  BuildContext context, {
  required GroupModel group,
  required DateTime date,
  required String organizationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AdminGuestsSheet(
      group: group,
      date: date,
      organizationId: organizationId,
    ),
  );
}

String _dateOnly(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _AdminGuestsSheet extends StatefulWidget {
  const _AdminGuestsSheet({
    required this.group,
    required this.date,
    required this.organizationId,
  });

  final GroupModel group;
  final DateTime date;
  final String organizationId;

  @override
  State<_AdminGuestsSheet> createState() => _AdminGuestsSheetState();
}

class _AdminGuestsSheetState extends State<_AdminGuestsSheet> {
  final GuestRepository _repo = GuestRepository();
  final MealRepository _mealRepo = MealRepository();
  final GroupRepository _groupRepo = GroupRepository();

  bool _loading = true;
  String? _error;
  List<MealGuestModel> _guests = const [];
  List<MealModel> _meals = const [];
  // Live-Test-8 ISSUE-004: the PUBLISHED day-effective meal view for
  // widget.date — preference groups narrowed/disabled by the day's schedule
  // entry, exactly what the server validates guest selections against. The
  // master list (_meals) stays only as a name-lookup fallback for bookings
  // whose meal was later removed from the day.
  List<MealModel> _dayMeals = const [];
  // True once the day-effective fetch SUCCEEDED — an empty day (holiday) is
  // then trusted as-is instead of silently falling back to master meals.
  bool _dayMealsLoaded = false;
  List<UserModel> _members = const [];

  String get _dateStr => _dateOnly(widget.date);

  bool get _isPastDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(widget.date.year, widget.date.month, widget.date.day);
    return d.isBefore(today);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _repo.listGuests(groupId: widget.group.id, date: _dateStr),
      _mealRepo.getGroupMeals(
        organizationId: widget.organizationId,
        groupId: widget.group.id,
      ),
      _groupRepo.getGroupMembers(
        organizationId: widget.organizationId,
        groupId: widget.group.id,
      ),
      // Live-Test-8 ISSUE-004: published day-effective meals for widget.date
      // (same parallel wave — zero extra wall time). Guest booking must show
      // the day's narrowed preference groups, not the master template's.
      _mealRepo.getDayMeals(
        organizationId: widget.organizationId,
        groupId: widget.group.id,
        date: _dateStr,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (results[0] case Ok(:final value)) {
        _guests = (value as List<MealGuestModel>)
            .where((g) => g.isBooked)
            .toList();
        _error = null;
      } else if (results[0] case Err(:final failure)) {
        _error = failure.message;
      }
      if (results[1] case Ok(:final value)) {
        _meals = value as List<MealModel>;
      }
      if (results[2] case Ok(:final value)) {
        _members = (value as PaginatedResponse<UserModel>).data;
      }
      if (results[3] case Ok(:final value)) {
        _dayMeals = value as List<MealModel>;
        _dayMealsLoaded = true;
      }
    });
  }

  String _mealName(String mealId) {
    for (final m in _meals) {
      if (m.id == mealId) return m.name;
    }
    return 'Meal';
  }

  String _hostName(String hostUserId) {
    for (final u in _members) {
      if (u.id == hostUserId) return u.name;
    }
    return 'Member';
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? AppColors.error : null,
    ));
  }

  Future<void> _act(
    Future<Result<MealGuestModel>> Function() action, {
    required String success,
  }) async {
    final result = await action();
    if (!mounted) return;
    switch (result) {
      case Ok():
        _snack(success);
        setState(() => _loading = true);
        await _load();
      case Err(:final failure):
        _snack(failure.message, isError: true);
    }
  }

  /// FR-HG-062: governed add-on-behalf — pick the member + meal, then reuse
  /// the shared guest sheet in admin mode (booking parks pendingApproval).
  Future<void> _addForMember() async {
    // Live-Test-8 ISSUE-004: the picker offers the PUBLISHED day-effective
    // meals for widget.date (day overrides applied: narrowed preference
    // groups, per-day windows/prices). An EMPTY published day (holiday) is
    // trusted as-is — the master list is a fallback ONLY when the day fetch
    // itself failed, never silently mixing the two sources.
    final pickerMeals = _dayMealsLoaded ? _dayMeals : _meals;
    final picked = await showDialog<({UserModel member, MealModel meal})>(
      context: context,
      builder: (_) => _PickHostDialog(members: _members, meals: pickerMeals),
    );
    if (picked == null || !mounted) return;
    final cfg = widget.group.mealConfig;
    final changed = await showGuestSheet(
      context,
      mealId: picked.meal.id,
      mealName: picked.meal.name,
      dateStr: _dateStr,
      config: cfg.guestConfig,
      pricingEnabled: cfg.mealPricingEnabled,
      // Day-effective flat tags: the overlay already narrowed/cleared these
      // per the published day entry (empty = day disabled preferences).
      enabledPreferences: picked.meal.enabledPreferences.isNotEmpty
          ? picked.meal.enabledPreferences
          : (picked.meal.preferencesEnabled
              ? cfg.enabledPreferences.map((e) => e.name).toList()
              : const []),
      // Live-Test-8 ISSUE-004: DAY-EFFECTIVE preference groups (published
      // schedule = single source of truth) — the exact set the server
      // validates each guest's selections against.
      preferenceGroups: picked.meal.preferenceGroups,
      mealPrice: picked.meal.price,
      hostUserId: picked.member.id,
      hostName: picked.member.name,
      asAdmin: true,
    );
    if (changed == true && mounted) {
      setState(() => _loading = true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    final pendingApproval = _guests
        .where((g) => g.isPending && !g.isAdminProposed)
        .toList();
    final awaitingMember =
        _guests.where((g) => g.isPending && g.isAdminProposed).toList();
    final confirmed = _guests.where((g) => g.isConfirmed).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.bottomSheetRadius),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.space20,
              AppConstants.space20,
              AppConstants.space12,
              AppConstants.space8,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.group_add_rounded,
                      size: 20, color: AppColors.secondary),
                ),
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hosted guests',
                        style: AppTypography.titleMedium.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${widget.group.name} · $_dateStr',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: _loading
                ? const AppSheetSkeleton(rows: 2, rowHeight: 72)
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.space20,
                      0,
                      AppConstants.space20,
                      AppConstants.space20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppConstants.space12),
                            child: Text(
                              _error!,
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.error),
                            ),
                          ),
                        if (!_isPastDate)
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppConstants.space12),
                            child: OutlinedButton.icon(
                              onPressed:
                                  _members.isEmpty || _meals.isEmpty
                                      ? null
                                      : _addForMember,
                              icon: const Icon(Icons.person_add_alt_rounded,
                                  size: 17),
                              label:
                                  const Text('Add guests for a member'),
                            ),
                          ),
                        if (_guests.isEmpty && _error == null)
                          Padding(
                            padding:
                                const EdgeInsets.all(AppConstants.space16),
                            child: Center(
                              child: Text(
                                'No guests booked for this date.',
                                style: AppTypography.bodySmall.copyWith(
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ..._section(
                          'Awaiting your approval',
                          pendingApproval,
                          isDark,
                          color: AppColors.warning,
                          trailing: (g) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Approve',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _act(
                                  () => _repo.approveGuest(g.id),
                                  success: 'Guest approved.',
                                ),
                                icon: const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 20,
                                    color: AppColors.present),
                              ),
                              IconButton(
                                tooltip: 'Reject',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _act(
                                  () => _repo.rejectGuest(g.id),
                                  success: 'Guest rejected.',
                                ),
                                icon: const Icon(Icons.highlight_off_rounded,
                                    size: 20, color: AppColors.absent),
                              ),
                            ],
                          ),
                        ),
                        ..._section(
                          'Awaiting member confirmation',
                          awaitingMember,
                          isDark,
                          color: AppColors.info,
                          trailing: (g) => IconButton(
                            tooltip: 'Withdraw',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _act(
                              () => _repo.cancelGuest(g.id),
                              success: 'Proposal withdrawn.',
                            ),
                            icon: const Icon(Icons.undo_rounded,
                                size: 19, color: AppColors.absent),
                          ),
                        ),
                        ..._section(
                          'Booked',
                          confirmed,
                          isDark,
                          trailing: (g) => IconButton(
                            tooltip: 'Cancel guest',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _act(
                              () => _repo.cancelGuest(g.id),
                              success: 'Guest cancelled.',
                            ),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 19, color: AppColors.absent),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(
    String title,
    List<MealGuestModel> rows,
    bool isDark, {
    Color? color,
    required Widget Function(MealGuestModel) trailing,
  }) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(
            top: AppConstants.space8, bottom: AppConstants.space8),
        child: Text(
          '$title (${rows.length})',
          style: AppTypography.labelMedium.copyWith(
            color: color ??
                (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      ...rows.map((g) => Container(
            margin: const EdgeInsets.only(bottom: AppConstants.space8),
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space12,
              vertical: AppConstants.space8,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              border: color != null
                  ? Border.all(color: color.withValues(alpha: 0.25))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (g.displayName?.isNotEmpty ?? false)
                            ? g.displayName!
                            : 'Guest (${g.typeLabel})',
                        style: AppTypography.bodyMedium.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          'Host: ${_hostName(g.hostUserId)}',
                          _mealName(g.mealId),
                          g.typeLabel,
                          if (g.mealPreference != null)
                            MealPreferenceOption.display(g.mealPreference!)
                                .label,
                          if (g.priceSnapshot != null) '₹${g.priceSnapshot}',
                        ].join(' · '),
                        style: AppTypography.labelSmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing(g),
              ],
            ),
          )),
    ];
  }
}

// ── Host + meal picker ─────────────────────────────────────────────────────────

class _PickHostDialog extends StatefulWidget {
  const _PickHostDialog({required this.members, required this.meals});

  final List<UserModel> members;
  final List<MealModel> meals;

  @override
  State<_PickHostDialog> createState() => _PickHostDialogState();
}

class _PickHostDialogState extends State<_PickHostDialog> {
  UserModel? _member;
  MealModel? _meal;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add guests for a member'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<UserModel>(
            initialValue: _member,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Member (host)'),
            items: widget.members
                .map((u) => DropdownMenuItem(
                      value: u,
                      child: Text(u.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (u) => setState(() => _member = u),
          ),
          const SizedBox(height: AppConstants.space12),
          DropdownButtonFormField<MealModel>(
            initialValue: _meal,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Meal'),
            items: widget.meals
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (m) => setState(() => _meal = m),
          ),
          const SizedBox(height: AppConstants.space8),
          Text(
            'The member must confirm — guests increase their bill.',
            style: AppTypography.labelSmall.copyWith(color: AppColors.warning),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _member != null && _meal != null
              ? () => Navigator.of(context)
                  .pop((member: _member!, meal: _meal!))
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
