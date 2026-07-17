import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/repositories/preference_repository.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Module 36 (FR-PG-080) + Live-Test-7 ISSUE-1: the Meal Preference Builder.
///
/// ONE screen composes everything preference-related for a meal, split into
/// two clearly separated, mutually exclusive modes (premium selection cards):
///
///  • STANDALONE — one simple tag list (Veg / Chicken / …); members pick one.
///    2–5 options, edited inline, saved straight to the meal.
///  • PREFERENCE GROUPS — multi-dimension choices with rules, veg flags and
///    price add-ons (Staple: Ruti/Rice · Non-Veg: Chicken/Mutton +₹30).
///
/// Enabling one mode automatically disables the other. Live-Test-8 ISSUE-001:
/// the switch is NON-DESTRUCTIVE — groups are suspended server-side (saved)
/// and restore exactly on switching back. Deletes are soft server-side;
/// history and past bills never change (FR-PG-072). Kitchen counts show
/// today's per-option totals.

/// ISSUE-2 window, mirrored from the server config (preferences.minOptions /
/// maxOptions): every preference group carries 2–5 options.
const int _kMinGroupOptions = 2;
const int _kMaxGroupOptions = 5;

class PreferenceGroupsScreen extends StatefulWidget {
  const PreferenceGroupsScreen({super.key, required this.meal});

  final MealModel meal;

  @override
  State<PreferenceGroupsScreen> createState() => _PreferenceGroupsScreenState();
}

class _PreferenceGroupsScreenState extends State<PreferenceGroupsScreen> {
  final _repo = PreferenceRepository();
  final _mealRepo = MealRepository();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<PreferenceGroupModel> _groups = [];
  // Live-Test-8 ISSUE-001: groups SAVED while Standalone mode is active —
  // nothing is deleted on a mode switch; these restore on switching back.
  List<PreferenceGroupModel> _suspendedGroups = [];
  late MealModel _meal;

  /// ISSUE-2: standalone preference sets carry 2–5 options (server-enforced;
  /// mirrored here so the admin sees the rule before a round-trip).
  static const int _minStandalone = 2;
  static const int _maxStandalone = 5;

  bool get _standaloneActive =>
      _meal.preferencesEnabled && _groups.isEmpty;
  bool get _groupsActive => _groups.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _meal = widget.meal;
    _load();
  }

  /// Persists a standalone-preference change and keeps the local meal fresh.
  Future<bool> _patchStandalone({List<String>? tags}) async {
    setState(() => _saving = true);
    final res = await _mealRepo.updateMeal(
      organizationId: _meal.organizationId,
      groupId: _meal.groupId,
      mealId: _meal.id,
      availablePreferences: tags,
    );
    if (!mounted) return false;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _meal = value;
          _saving = false;
        });
        return true;
      case Err(:final failure):
        setState(() => _saving = false);
        _toast(failure.message);
        return false;
    }
  }

  /// Live-Test-8 ISSUE-001 mutual exclusivity, NON-DESTRUCTIVE: activating
  /// Standalone SUSPENDS the meal's preference groups (one server call —
  /// nothing is deleted). Switching back to Groups restores them exactly.
  Future<void> _activateStandalone() async {
    if (_standaloneActive || _saving) return;
    if (_groups.isNotEmpty) {
      final ok = await _confirm(
        'Switch to Standalone?',
        '${_groups.length} preference group(s) will be SAVED — not deleted. '
        'Members pick ONE simple tag instead. Switch back to Preference '
        'Groups any time and your groups return exactly as configured.',
        confirmLabel: 'Switch',
      );
      if (ok != true) return;
      setState(() => _saving = true);
      final res = await _repo.setMealBindingsActive(_meal.id, active: false);
      if (!mounted) return;
      setState(() => _saving = false);
      if (res case Err(:final failure)) {
        _toast(failure.message);
        return;
      }
    }
    // Seed a valid minimum set when the meal has fewer than 2 stored tags.
    final tags = _meal.enabledPreferences.length >= _minStandalone
        ? _meal.enabledPreferences.take(_maxStandalone).toList()
        : <String>['Veg', 'Non-Veg'];
    if (await _patchStandalone(tags: tags)) await _load();
  }

  /// Live-Test-8 ISSUE-001 mutual exclusivity: activating Groups silently
  /// turns the flat standalone list off (tags preserved server-side) and
  /// RESTORES any suspended groups; the creator opens only when the meal has
  /// no saved groups to restore.
  Future<void> _activateGroups() async {
    if (_saving) return;
    if (_meal.preferencesEnabled) {
      if (!await _patchStandalone(tags: const [])) return;
    }
    if (_suspendedGroups.isNotEmpty) {
      setState(() => _saving = true);
      final res = await _repo.setMealBindingsActive(_meal.id, active: true);
      if (!mounted) return;
      setState(() => _saving = false);
      if (res case Err(:final failure)) {
        _toast(failure.message);
        return;
      }
      _toast('${_suspendedGroups.length} saved group(s) restored');
      await _load();
      return;
    }
    if (_groups.isNotEmpty) {
      // Already in Groups mode with live groups — nothing to create.
      await _load();
      return;
    }
    await _addGroup();
  }

  /// Inline standalone tag editing — 2..5 window enforced before the trip.
  Future<void> _removeStandaloneTag(String tag) async {
    if (_meal.enabledPreferences.length <= _minStandalone) {
      _toast('Standalone preferences need at least $_minStandalone options.');
      return;
    }
    final next = List.of(_meal.enabledPreferences)..remove(tag);
    await _patchStandalone(tags: next);
  }

  Future<void> _addStandaloneTag(String tag) async {
    final t = tag.trim();
    if (t.isEmpty) return;
    if (_meal.enabledPreferences.length >= _maxStandalone) {
      _toast('Standalone preferences carry at most $_maxStandalone options.');
      return;
    }
    if (_meal.enabledPreferences
        .any((e) => e.toLowerCase() == t.toLowerCase())) {
      _toast('"$t" already exists.');
      return;
    }
    await _patchStandalone(tags: [..._meal.enabledPreferences, t]);
  }

  Future<void> _load() async {
    final res = await _repo.getForMealWithSuspended(widget.meal.id);
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _groups = value.active;
          _suspendedGroups = value.suspended;
          _loading = false;
          _error = null;
        });
      case Err(:final failure):
        setState(() {
          _loading = false;
          _error = failure.message;
        });
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addGroup() async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GroupEditorSheet(),
    );
    if (body == null) return;
    final res = await _repo.createForMeal(mealId: widget.meal.id, body: body);
    if (!mounted) return;
    switch (res) {
      case Ok():
        _toast('Preference group added');
        await _load();
      case Err(:final failure):
        _toast(failure.message);
    }
  }

  Future<void> _addOption(PreferenceGroupModel g) async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OptionEditorSheet(quantityEnabled: g.quantityEnabled),
    );
    if (body == null) return;
    final res = await _repo.addOption(g.id, body);
    if (!mounted) return;
    switch (res) {
      case Ok():
        await _load();
      case Err(:final failure):
        _toast(failure.message);
    }
  }

  Future<void> _removeOption(
    PreferenceGroupModel g,
    PreferenceOptionModel o,
  ) async {
    final ok = await _confirm(
      'Remove "${o.label}"?',
      'Past selections keep their history — this only hides the option going forward.',
    );
    if (ok != true) return;
    final res = await _repo.deactivateOption(o.id);
    if (!mounted) return;
    if (res case Err(:final failure)) {
      _toast(failure.message);
      return;
    }
    await _load();
  }

  Future<void> _removeGroup(PreferenceGroupModel g) async {
    final ok = await _confirm(
      'Remove "${g.label}" from this meal?',
      'Members will no longer choose it. Past records and bills stay exactly as they were.',
    );
    if (ok != true) return;
    final res = await _repo.unbindFromMeal(widget.meal.id, g.id);
    if (!mounted) return;
    if (res case Err(:final failure)) {
      _toast(failure.message);
      return;
    }
    await _load();
  }

  Future<bool?> _confirm(String title, String message,
      {String confirmLabel = 'Remove'}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
  }

  /// FR-PG-050/051: today's per-group-per-option counts for this meal.
  Future<void> _showKitchenCounts() async {
    final now = DateTime.now();
    final dateStr = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final res = await _repo.getCrossTab(
      groupId: widget.meal.groupId,
      date: dateStr,
      mealId: widget.meal.id,
    );
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _KitchenCountsSheet(
            mealName: widget.meal.name,
            date: dateStr,
            data: (value['data'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList(),
          ),
        );
      case Err(:final failure):
        _toast(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('${widget.meal.name} · Preference Builder'),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Kitchen counts (today)',
            icon: const Icon(Icons.soup_kitchen_rounded),
            onPressed: _showKitchenCounts,
          ),
        ],
      ),
      // The FAB belongs to Groups mode only — in Standalone mode options are
      // added inline, and showing "Add group" there contradicted exclusivity.
      floatingActionButton: _standaloneActive
          ? null
          : FloatingActionButton.extended(
              // Groups mode: straight to the creator. No mode yet: the mode
              // switch handles restore-or-create.
              onPressed:
                  _saving ? null : (_groupsActive ? _addGroup : _activateGroups),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Add group',
                  style: TextStyle(color: Colors.white)),
            ),
      body: _loading
          ? const AppListSkeleton(rows: 4, rowHeight: 96)
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall),
                        TextButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      // ISSUE-1: the two modes, side by side, immediately
                      // recognisable — selected state is visually obvious.
                      _ModeSelector(
                        standaloneActive: _standaloneActive,
                        groupsActive: _groupsActive,
                        disabled: _saving,
                        onStandalone: _activateStandalone,
                        onGroups: _activateGroups,
                      ),
                      const SizedBox(height: 12),
                      // Live-Test-8 ISSUE-001: smooth animated swap between
                      // the two mode bodies (no hard jump on switch).
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SizeTransition(
                              sizeFactor: anim, child: child),
                        ),
                        child: _standaloneActive
                            ? Column(
                                key: const ValueKey('standalone'),
                                children: [
                                  _StandaloneCard(
                                    tags: _meal.enabledPreferences,
                                    minOptions: _minStandalone,
                                    maxOptions: _maxStandalone,
                                    saving: _saving,
                                    onAdd: _addStandaloneTag,
                                    onRemove: _removeStandaloneTag,
                                  ),
                                  // ISSUE-001: groups are SAVED on switch,
                                  // never deleted — show them so the admin
                                  // trusts the restore.
                                  if (_suspendedGroups.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _SavedGroupsPanel(
                                      groups: _suspendedGroups,
                                      saving: _saving,
                                      onRestore: _activateGroups,
                                    ),
                                  ],
                                ],
                              )
                            : _groupsActive
                                ? Column(
                                    key: const ValueKey('groups'),
                                    children: [
                                      const _HelpBanner(),
                                      const SizedBox(height: 12),
                                      for (final g in _groups) ...[
                                        _GroupCard(
                                          group: g,
                                          onAddOption: () => _addOption(g),
                                          onRemoveOption: (o) =>
                                              _removeOption(g, o),
                                          onRemoveGroup: () =>
                                              _removeGroup(g),
                                          onEditRules: () =>
                                              _editGroupRules(g),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                    ],
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('empty'),
                                    child: Column(children: [
                                      _EmptyState(onAdd: _activateGroups),
                                      if (_suspendedGroups.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        _SavedGroupsPanel(
                                          groups: _suspendedGroups,
                                          saving: _saving,
                                          onRestore: _activateGroups,
                                        ),
                                      ],
                                    ]),
                                  ),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// ISSUE-1: edit an existing group's rules (name, picks, flags) in the same
  /// premium sheet used to create it — options stay managed on the card.
  Future<void> _editGroupRules(PreferenceGroupModel g) async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroupEditorSheet(initial: g),
    );
    if (body == null) return;
    final res = await _repo.updateGroup(g.id, body);
    if (!mounted) return;
    switch (res) {
      case Ok():
        _toast('Group updated');
        await _load();
      case Err(:final failure):
        _toast(failure.message);
    }
  }
}

// ── ISSUE-1: mode selection cards ────────────────────────────────────────────

/// Two premium cards — Standalone vs Preference Groups — with clear
/// selected / unselected / disabled states in both themes. The active mode is
/// visually obvious without reading any description.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.standaloneActive,
    required this.groupsActive,
    required this.disabled,
    required this.onStandalone,
    required this.onGroups,
  });

  final bool standaloneActive;
  final bool groupsActive;
  final bool disabled;
  final VoidCallback onStandalone;
  final VoidCallback onGroups;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: _modeCard(
            context,
            isDark: isDark,
            selected: standaloneActive,
            icon: Icons.style_rounded,
            title: 'Standalone',
            description: 'One simple list — members pick a single tag',
            onTap: onStandalone,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _modeCard(
            context,
            isDark: isDark,
            selected: groupsActive,
            icon: Icons.tune_rounded,
            title: 'Preference Groups',
            description: 'Multi-choice dimensions, rules & ₹ add-ons',
            onTap: onGroups,
          ),
        ),
      ],
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required bool isDark,
    required bool selected,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    const accent = AppColors.primary;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = selected
        ? accent
        : (isDark ? AppColors.borderDark : AppColors.border);
    final titleColor = selected
        ? accent
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary);
    // Live-Test-8 ISSUE-001: premium animated selection — the card's fill,
    // border, glow and check-mark all animate on mode change, with explicit
    // high-contrast colors in BOTH themes (nothing blends into the
    // background). AnimatedScale gives a subtle press-in emphasis on select.
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.98,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: disabled ? null : onTap,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: isDark ? 0.16 : 0.07)
                    : surface,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: border, width: selected ? 1.6 : 1),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accent.withValues(
                              alpha: isDark ? 0.30 : 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accent.withValues(
                              alpha: selected
                                  ? (isDark ? 0.30 : 0.16)
                                  : (isDark ? 0.22 : 0.12)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 18, color: accent),
                      ),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          key: ValueKey(selected),
                          size: 20,
                          color: selected
                              ? accent
                              : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textTertiary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(title,
                      style: AppTypography.labelLarge.copyWith(
                          color: titleColor, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── ISSUE-1: standalone preference editor card ────────────────────────────────

/// Premium inline editor for the flat standalone tag list (2–5 options).
class _StandaloneCard extends StatefulWidget {
  const _StandaloneCard({
    required this.tags,
    required this.minOptions,
    required this.maxOptions,
    required this.saving,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tags;
  final int minOptions;
  final int maxOptions;
  final bool saving;
  final Future<void> Function(String) onAdd;
  final Future<void> Function(String) onRemove;

  @override
  State<_StandaloneCard> createState() => _StandaloneCardState();
}

class _StandaloneCardState extends State<_StandaloneCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitAdd() async {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    await widget.onAdd(t);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final atFloor = widget.tags.length <= widget.minOptions;
    final atCap = widget.tags.length >= widget.maxOptions;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary
                      .withValues(alpha: isDark ? 0.20 : 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.style_rounded,
                    size: 19, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Standalone options',
                        style: AppTypography.titleSmall
                            .copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      '${widget.tags.length} of ${widget.maxOptions} · members pick ONE',
                      style: AppTypography.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.saving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in widget.tags)
                Container(
                  padding: const EdgeInsets.only(
                      left: 12, right: 4, top: 6, bottom: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.backgroundDark
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            isDark ? AppColors.borderDark : AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t,
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                          )),
                      InkWell(
                        onTap: (widget.saving || atFloor)
                            ? null
                            : () => widget.onRemove(t),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: atFloor
                                ? AppColors.textTertiary
                                    .withValues(alpha: 0.35)
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!atCap)
            TextField(
              controller: _controller,
              enabled: !widget.saving,
              maxLength: 30,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitAdd(),
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                hintText: 'Add option (e.g. Fish)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_rounded,
                      color: AppColors.primary),
                  onPressed: widget.saving ? null : _submitAdd,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              atFloor
                  ? 'Keep at least ${widget.minOptions} options — one option is not a choice.'
                  : atCap
                      ? 'Limit reached — a standalone list carries at most ${widget.maxOptions} options.'
                      : 'Shown exactly as published — nothing is added or substituted.',
              style: AppTypography.labelSmall.copyWith(
                color: (atFloor || atCap)
                    ? AppColors.warning
                    : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Group card ────────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.onAddOption,
    required this.onRemoveOption,
    required this.onRemoveGroup,
    required this.onEditRules,
  });

  final PreferenceGroupModel group;
  final VoidCallback onAddOption;
  final void Function(PreferenceOptionModel) onRemoveOption;
  final VoidCallback onRemoveGroup;
  final VoidCallback onEditRules;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.primary;
    // Count caption independent of required-ness — the Required/Optional pill
    // carries that status separately, so no wording is duplicated.
    final countCaption = (group.isSingle || group.maxSelect <= 1)
        ? 'Choose 1'
        : (group.minSelect == group.maxSelect
            ? 'Choose ${group.minSelect}'
            : 'Choose ${group.minSelect}–${group.maxSelect}');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.20 : 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.tune_rounded, size: 19, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(group.label,
                    style: AppTypography.titleSmall
                        .copyWith(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 18),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit rules')),
                  PopupMenuItem(
                      value: 'remove', child: Text('Remove from meal')),
                ],
                onSelected: (v) =>
                    v == 'edit' ? onEditRules() : onRemoveGroup(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Selection rule + required/optional + flags — clear, first-time-friendly.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _metaPill(countCaption, accent, Icons.checklist_rounded, isDark),
              // Live-Test-8 ISSUE-001: same "N of 5" counter language as the
              // Standalone card, with an explicit warning under the 2-option
              // floor (a 1-option "choice" is not a choice — server rejects).
              _metaPill(
                '${group.options.length} of $_kMaxGroupOptions options',
                group.options.length < _kMinGroupOptions
                    ? AppColors.warning
                    : AppColors.info,
                group.options.length < _kMinGroupOptions
                    ? Icons.warning_amber_rounded
                    : Icons.category_rounded,
                isDark,
              ),
              _metaPill(
                group.isSingle ? 'Single pick' : 'Multiple picks',
                accent,
                group.isSingle
                    ? Icons.looks_one_rounded
                    : Icons.done_all_rounded,
                isDark,
              ),
              _metaPill(
                group.required ? 'Required' : 'Optional',
                group.required ? AppColors.present : AppColors.textTertiary,
                group.required
                    ? Icons.priority_high_rounded
                    : Icons.remove_circle_outline_rounded,
                isDark,
              ),
              if (group.vegOnly)
                _metaPill('Veg-only', AppColors.present, Icons.eco_rounded,
                    isDark),
              if (group.quantityEnabled)
                _metaPill('Quantities', AppColors.info, Icons.numbers_rounded,
                    isDark),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
              height: 1,
              color: (isDark ? AppColors.borderDark : AppColors.border)
                  .withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in group.options) _optionChip(o, isDark),
              _addOptionChip(),
            ],
          ),
        ],
      ),
    );
  }

  /// Small rounded status/flag pill used in the group header.
  Widget _metaPill(String label, Color color, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: AppTypography.labelSmall
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// High-contrast option chip: veg/non-veg dot + label + optional +₹ pill +
  /// remove affordance. Readable in both themes (fixes the washed-out chips).
  Widget _optionChip(PreferenceOptionModel o, bool isDark) {
    final hasPrice = o.priceDelta > 0;
    final priceStr =
        '+₹${(o.priceDelta / 100).toStringAsFixed(o.priceDelta % 100 == 0 ? 0 : 2)}';
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: o.isVeg ? AppColors.present : AppColors.error,
            ),
          ),
          const SizedBox(width: 6),
          Text(o.displayLabel,
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              )),
          if (hasPrice) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(priceStr,
                  style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
          InkWell(
            onTap: () => onRemoveOption(o),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 15, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  /// Outlined "+ Option" CTA — clearly distinct from the value chips.
  Widget _addOptionChip() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAddOption,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 4),
              Text('Option',
                  style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.tune_rounded,
            size: 44, color: AppColors.textTertiary),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'No preference groups yet.\nAdd dimensions like "Staple (Ruti/Rice)" '
              'or "Non-Veg (Chicken/Mutton +₹30)" — members will pick one from '
              'each when marking Present.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add first group'),
          ),
        ),
      ],
    );
  }
}

// ── Group editor sheet (FR-PG-080/081) ────────────────────────────────────────

class _GroupEditorSheet extends StatefulWidget {
  /// ISSUE-1: [initial] switches the sheet to RULES-EDIT mode for an existing
  /// group (name, picks, flags) — options stay managed on the group card.
  const _GroupEditorSheet({this.initial});

  final PreferenceGroupModel? initial;

  @override
  State<_GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _GroupEditorSheetState extends State<_GroupEditorSheet> {
  final _label = TextEditingController();
  bool _multiple = false;
  int _maxSelect = 2;
  bool _required = true;
  bool _quantity = false;
  bool _vegOnly = false;
  final List<Map<String, dynamic>> _options = [];
  String? _error;

  bool get _isEdit => widget.initial != null;

  /// ISSUE-2: a group carries 2–5 options (server-enforced; mirrored here).
  static const int _minOptions = 2;
  static const int _maxOptions = 5;

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    if (g != null) {
      _label.text = g.label;
      _multiple = !g.isSingle;
      _maxSelect = g.maxSelect < 2 ? 2 : g.maxSelect;
      _required = g.required;
      _quantity = g.quantityEnabled;
      _vegOnly = g.vegOnly;
    }
  }

  /// Canonical lowercase key from a label (FR-PG-011).
  static String _keyOf(String label) => label
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Future<void> _addOptionRow() async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OptionEditorSheet(quantityEnabled: _quantity),
    );
    if (body != null) setState(() => _options.add(body));
  }

  void _submit() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Group name is required.');
      return;
    }
    if (!_isEdit) {
      // ISSUE-2: 2–5 options per group, asserted before the round-trip.
      if (_options.length < _minOptions) {
        setState(() =>
            _error = 'Add at least $_minOptions options — one option is not a choice.');
        return;
      }
      if (_options.length > _maxOptions) {
        setState(() => _error = 'A group carries at most $_maxOptions options.');
        return;
      }
      final keys = _options.map((o) => o['key']).toSet();
      if (keys.length != _options.length) {
        setState(() => _error = 'Option names must be unique.');
        return;
      }
    }
    Navigator.pop(context, {
      'label': label,
      'selectionType': _multiple ? 'multiple' : 'single',
      'minSelect': _required ? 1 : 0,
      'maxSelect': _multiple ? _maxSelect : 1,
      'required': _required,
      'quantityEnabled': _quantity,
      'vegOnly': _vegOnly,
      if (!_isEdit) 'options': _options,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SheetHeader(
                icon: Icons.tune_rounded,
                title: _isEdit
                    ? 'Edit "${widget.initial!.label}"'
                    : 'New preference group',
                subtitle: _isEdit
                    ? 'Rename the group or change its selection rules — '
                        'options are managed on the group card.'
                    : 'A group is one choice members make when marking Present — '
                        'e.g. "Staple" with Ruti / Rice. Add 2–5 options below '
                        'and pick how many they may choose.',
              ),
              TextField(
                controller: _label,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Group name (e.g. Staple, Non-Veg)',
                  counterText: '',
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow multiple picks'),
                value: _multiple,
                onChanged: (v) => setState(() => _multiple = v),
              ),
              if (_multiple)
                Row(
                  children: [
                    Text('Max picks', style: AppTypography.bodySmall),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: _maxSelect > 2
                          ? () => setState(() => _maxSelect--)
                          : null,
                    ),
                    Text('$_maxSelect', style: AppTypography.labelMedium),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      // PREF-005: Max Picks is capped server-side (default 3)
                      // — mirror it so the sheet can't submit a doomed value.
                      onPressed: _maxSelect < 3
                          ? () => setState(() => _maxSelect++)
                          : null,
                    ),
                  ],
                ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Required to mark Present'),
                value: _required,
                onChanged: (v) => setState(() => _required = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Per-option quantities (e.g. Ruti ×3)'),
                value: _quantity,
                onChanged: (v) => setState(() => _quantity = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Veg-only group'),
                value: _vegOnly,
                onChanged: (v) => setState(() => _vegOnly = v),
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 8),
                Text(
                  'Options  ·  ${_options.length} of $_maxOptions',
                  style: AppTypography.labelMedium.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                // Live-Test-6 ISSUE-1: premium high-contrast draft chips —
                // explicit colors for BOTH themes (the raw InputChip/ActionChip
                // labels were washed out / invisible in light mode). Mirrors the
                // group-card option chips: veg dot + label + optional +₹ pill.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _options.length; i++)
                      _draftOptionChip(i, isDark),
                    if (_options.length < _maxOptions) _addOptionCta(),
                  ],
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(_isEdit ? 'Save changes' : 'Create group'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Premium draft-option chip (Live-Test-6 ISSUE-1): explicit surface, border
  /// and text colors per theme + veg/non-veg dot + optional +₹ pill + remove ×.
  Widget _draftOptionChip(int index, bool isDark) {
    final o = _options[index];
    final label = (o['label'] as String?) ?? '';
    final emoji = (o['emoji'] as String?) ?? '';
    final isVeg = o['isVeg'] != false;
    final deltaPaise = (o['priceDelta'] as int?) ?? 0;
    final priceStr =
        '+₹${(deltaPaise / 100).toStringAsFixed(deltaPaise % 100 == 0 ? 0 : 2)}';
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isVeg ? AppColors.present : AppColors.error,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            emoji.isNotEmpty ? '$emoji $label' : label,
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w600,
              color:
                  isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          if (deltaPaise > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(priceStr,
                  style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
          InkWell(
            onTap: () => setState(() => _options.removeAt(index)),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 15, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  /// Outlined "+ Add option" CTA — same premium affordance as the group card.
  Widget _addOptionCta() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _addOptionRow,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 4),
              Text('Add option',
                  style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }
}

// ── Option editor sheet ───────────────────────────────────────────────────────

class _OptionEditorSheet extends StatefulWidget {
  const _OptionEditorSheet({required this.quantityEnabled});
  final bool quantityEnabled;

  @override
  State<_OptionEditorSheet> createState() => _OptionEditorSheetState();
}

class _OptionEditorSheetState extends State<_OptionEditorSheet> {
  final _label = TextEditingController();
  final _price = TextEditingController();
  final _emoji = TextEditingController();
  bool _isVeg = true;
  int _maxQty = 1;
  String? _error;

  void _submit() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Option name is required.');
      return;
    }
    final rupees = double.tryParse(
            _price.text.trim().isEmpty ? '0' : _price.text.trim()) ??
        -1;
    if (rupees < 0) {
      setState(() => _error = 'Extra price must be 0 or more.');
      return;
    }
    Navigator.pop(context, {
      'key': _GroupEditorSheetState._keyOf(label),
      'label': label,
      if (_emoji.text.trim().isNotEmpty) 'emoji': _emoji.text.trim(),
      'isVeg': _isVeg,
      'priceDelta': (rupees * 100).round(),
      if (widget.quantityEnabled && _maxQty > 1) 'maxQty': _maxQty,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHeader(
              icon: Icons.add_circle_outline_rounded,
              title: 'New option',
              subtitle:
                  'One choice inside this group. Add an optional extra price (₹) — '
                  'members see it while choosing.',
            ),
            TextField(
              controller: _label,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. Ruti, Chicken)',
                counterText: '',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Extra price ₹ (0 = none)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _emoji,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Emoji',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Vegetarian'),
              value: _isVeg,
              onChanged: (v) => setState(() => _isVeg = v),
            ),
            if (widget.quantityEnabled)
              Row(
                children: [
                  Text('Max quantity', style: AppTypography.bodySmall),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed:
                        _maxQty > 1 ? () => setState(() => _maxQty--) : null,
                  ),
                  Text('$_maxQty', style: AppTypography.labelMedium),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => setState(() => _maxQty++),
                  ),
                ],
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Add option'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _price.dispose();
    _emoji.dispose();
    super.dispose();
  }
}

// ── Premium sheet header (shared by group + option editors) ──────────────────

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.textTertiary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(subtitle,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary, height: 1.4)),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── First-timer explainer banner ─────────────────────────────────────────────

class _HelpBanner extends StatelessWidget {
  const _HelpBanner();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Each group is one choice members make when marking Present. '
              'A meal can have several — e.g. Staple (Choose 1) + Non-Veg (Optional).',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live-Test-8 ISSUE-001: saved (suspended) groups panel ────────────────────

/// Shown while Standalone mode is active: the meal's preference groups are
/// SAVED — not deleted — and restore exactly on switching back. High-contrast
/// dimmed cards in both themes so the admin trusts the non-destructive switch.
class _SavedGroupsPanel extends StatelessWidget {
  const _SavedGroupsPanel({
    required this.groups,
    required this.saving,
    required this.onRestore,
  });

  final List<PreferenceGroupModel> groups;
  final bool saving;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded,
                  size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${groups.length} preference group(s) saved',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: saving ? null : onRestore,
                child: const Text('Restore'),
              ),
            ],
          ),
          Text(
            'Nothing was deleted — switch back to Preference Groups and these '
            'return exactly as configured.',
            style: AppTypography.labelSmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in groups)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.backgroundDark
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.border,
                    ),
                  ),
                  child: Text(
                    '${g.label} · ${g.options.length} options',
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Kitchen counts sheet (FR-PG-050/051) ─────────────────────────────────────

class _KitchenCountsSheet extends StatelessWidget {
  const _KitchenCountsSheet({
    required this.mealName,
    required this.date,
    required this.data,
  });

  final String mealName;
  final String date;
  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kitchen counts — $mealName',
              style: AppTypography.titleMedium),
          Text(date,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 12),
          if (data.isEmpty)
            Text(
              'No selections yet today — counts appear as members mark Present.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            )
          else
            for (final g in data) ...[
              Text(g['groupLabel']?.toString() ?? '',
                  style: AppTypography.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final o in (g['options'] as List<dynamic>? ?? [])
                  .whereType<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(o['label']?.toString() ?? '',
                            style: AppTypography.bodySmall),
                      ),
                      Text(
                        '${o['count']} member(s)'
                        '${(o['totalQuantity'] as num? ?? 0) != (o['count'] as num? ?? 0) ? ' · qty ${o['totalQuantity']}' : ''}',
                        style: AppTypography.labelMedium
                            .copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}
