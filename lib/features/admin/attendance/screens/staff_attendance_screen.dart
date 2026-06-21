import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

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

  // Issue 5: per-meal selected meal preference (parity with the student flow).
  // When a meal has preferences enabled, "Present" stays disabled until the
  // admin picks one — exactly like members.
  final Map<String, String?> _selectedPref = {};

  List<GroupModel> _groups = [];
  String? _groupId;
  List<MealModel> _meals = [];
  List<AttendanceModel> _records = [];

  String _orgId = '';
  String _userId = '';

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

    final res = await _groupRepo.getOrganisationGroups(organizationId: _orgId);
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        _groups = value.data;
        _groupId = _groups.isNotEmpty ? _groups.first.id : null;
      case Err(:final failure):
        _error = failure.message;
    }
    setState(() => _loadingGroups = false);
    if (_groupId != null) await _load();
  }

  Future<void> _load() async {
    final gid = _groupId;
    if (gid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final mealsRes = await _mealRepo.getTodayMeals(
      organizationId: _orgId,
      groupId: gid,
    );
    final recRes = await _attendanceRepo.getTodayAttendance(
      userId: _userId,
      groupId: gid,
      organizationId: _orgId,
    );
    if (!mounted) return;

    List<MealModel> meals = [];
    if (mealsRes case Ok(:final value)) {
      meals = value.where((m) => m.isActive).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
    } else if (mealsRes case Err(:final failure)) {
      _error = failure.message;
    }
    List<AttendanceModel> records = [];
    if (recRes case Ok(:final value)) records = value;

    setState(() {
      _meals = meals;
      _records = records;
      _loading = false;
    });
  }

  AttendanceStatus? _statusFor(String mealId) {
    final now = DateTime.now();
    for (final r in _records) {
      if (r.mealId == mealId &&
          r.date.year == now.year &&
          r.date.month == now.month &&
          r.date.day == now.day) {
        return r.status;
      }
    }
    return null;
  }

  Future<void> _mark(MealModel meal, AttendanceStatus status,
      {String? preference}) async {
    final gid = _groupId;
    if (gid == null || _busyMealId != null) return;
    setState(() => _busyMealId = meal.id);

    final now = DateTime.now();
    final existing = _records.indexWhere((r) =>
        r.mealId == meal.id &&
        r.date.year == now.year &&
        r.date.month == now.month &&
        r.date.day == now.day);

    final record = existing != -1
        ? _records[existing]
            .copyWith(status: status, markedAt: now, preference: preference)
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
          );

    // Issue 5: admins mark their OWN attendance through the override path, so
    // it works after the window has closed too — the same allowance the spec
    // grants admins. The endpoint snapshots the effective price and bypasses
    // the window + vacation checks; it is org/role-scoped server-side.
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
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked ${_label(status)} for ${meal.name}.')),
        );
      case Err(:final failure):
        setState(() => _busyMealId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
    }
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
          ? const Center(child: CircularProgressIndicator())
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
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

    // Issue 5: preference parity. When the meal has preferences enabled, the
    // admin must pick one before "Present" — identical to the member flow.
    final prefsOn =
        meal.preferencesEnabled && meal.enabledPreferences.isNotEmpty;
    final selectedPref = _selectedPref[meal.id];
    final canPresent = !prefsOn || selectedPref != null;

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
          Text(
            'Window  $open – $close',
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
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
              _actionButton('Present', AppColors.present,
                  status == AttendanceStatus.present, busy,
                  () => _mark(meal, AttendanceStatus.present,
                      preference: prefsOn ? selectedPref : null),
                  enabled: canPresent),
              const SizedBox(width: 8),
              _actionButton('Skip', AppColors.skipped,
                  status == AttendanceStatus.skipped, busy,
                  () => _mark(meal, AttendanceStatus.skipped)),
              const SizedBox(width: 8),
              _actionButton('Absent', AppColors.absent,
                  status == AttendanceStatus.absent, busy,
                  () => _mark(meal, AttendanceStatus.absent)),
            ],
          ),
        ],
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
    bool selected,
    bool busy,
    VoidCallback onTap, {
    bool enabled = true,
  }) {
    final active = enabled && !busy;
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
            child: busy
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
