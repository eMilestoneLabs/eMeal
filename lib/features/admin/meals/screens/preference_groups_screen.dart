import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/preference_repository.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Module 36 (FR-PG-080): per-meal preference-group builder.
///
/// Admins compose choice dimensions for one meal — e.g. Staple (choose 1:
/// Ruti/Rice) + Non-Veg (choose 1: Chicken +₹0 / Mutton +₹30) — with rules,
/// veg flags and price deltas. Deletes are soft server-side; history and past
/// bills never change (FR-PG-072). The kitchen-counts action shows today's
/// per-option totals (FR-PG-050/051).
class PreferenceGroupsScreen extends StatefulWidget {
  const PreferenceGroupsScreen({super.key, required this.meal});

  final MealModel meal;

  @override
  State<PreferenceGroupsScreen> createState() => _PreferenceGroupsScreenState();
}

class _PreferenceGroupsScreenState extends State<PreferenceGroupsScreen> {
  final _repo = PreferenceRepository();
  bool _loading = true;
  String? _error;
  List<PreferenceGroupModel> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _repo.getForMeal(widget.meal.id);
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _groups = value;
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

  Future<bool?> _confirm(String title, String message) {
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
              child: const Text('Remove')),
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
        title: Text('${widget.meal.name} · Preferences'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGroup,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label:
            const Text('Add group', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
              : _groups.isEmpty
                  ? _EmptyState(onAdd: _addGroup)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: _groups.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          if (i == 0) return const _HelpBanner();
                          final g = _groups[i - 1];
                          return _GroupCard(
                            group: g,
                            onAddOption: () => _addOption(g),
                            onRemoveOption: (o) => _removeOption(g, o),
                            onRemoveGroup: () => _removeGroup(g),
                          );
                        },
                      ),
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
  });

  final PreferenceGroupModel group;
  final VoidCallback onAddOption;
  final void Function(PreferenceOptionModel) onRemoveOption;
  final VoidCallback onRemoveGroup;

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
                  PopupMenuItem(
                      value: 'remove', child: Text('Remove from meal')),
                ],
                onSelected: (_) => onRemoveGroup(),
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
  const _GroupEditorSheet();

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
    if (_options.isEmpty) {
      setState(() => _error = 'Add at least one option.');
      return;
    }
    final keys = _options.map((o) => o['key']).toSet();
    if (keys.length != _options.length) {
      setState(() => _error = 'Option names must be unique.');
      return;
    }
    Navigator.pop(context, {
      'label': label,
      'selectionType': _multiple ? 'multiple' : 'single',
      'minSelect': _required ? 1 : 0,
      'maxSelect': _multiple ? _maxSelect : 1,
      'required': _required,
      'quantityEnabled': _quantity,
      'vegOnly': _vegOnly,
      'options': _options,
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
              const _SheetHeader(
                icon: Icons.tune_rounded,
                title: 'New preference group',
                subtitle:
                    'A group is one choice members make when marking Present — '
                    'e.g. "Staple" with Ruti / Rice. Add its options below and '
                    'pick how many they may choose.',
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
                      onPressed: () => setState(() => _maxSelect++),
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
              const SizedBox(height: 8),
              Text('Options', style: AppTypography.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _options.length; i++)
                    InputChip(
                      label: Text(_options[i]['label'] as String,
                          style: AppTypography.labelSmall),
                      onDeleted: () => setState(() => _options.removeAt(i)),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded,
                        size: 16, color: AppColors.primary),
                    label: Text('Add option',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.primary)),
                    onPressed: _addOptionRow,
                  ),
                ],
              ),
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
                  child: const Text('Create group'),
                ),
              ),
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
