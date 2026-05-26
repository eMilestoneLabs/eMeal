import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/features/admin/groups/providers/admin_group_provider.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/widgets/app_glass_card.dart';
import 'package:smart_meal_management/shared/widgets/app_primary_button.dart';
import 'package:smart_meal_management/shared/widgets/app_status_chip.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Multi-step group creation screen.
///
/// Steps: Name+Type → Meal Toggle → Preferences → Capacity → Review+Create
class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final PageController _pageCtrl = PageController();
  late final AdminGroupProvider _provider;
  bool _initialized = false;
  String _orgId = '';

  // Form state
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  GroupType _groupType = GroupType.hostel;
  bool _mealsEnabled = true;
  bool _preferencesEnabled = false;
  final Set<MealPreferenceOption> _selectedPrefs = {};
  int? _maxMembers;
  int _currentStep = 0;

  static const int _totalSteps = 5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final auth = AuthProviderScope.of(context);
      final user = auth.currentUser;
      if (user == null) return;
      _orgId = user.organizationId;
      _provider = AdminGroupProvider();
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _provider.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _create() async {
    final group = await _provider.createGroup(
      organizationId: _orgId,
      name: _nameCtrl.text.trim(),
      type: _groupType,
      description: _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
      maxMembers: _maxMembers,
      mealConfig: GroupMealConfig(
        mealsEnabled: _mealsEnabled,
        preferencesEnabled: _preferencesEnabled,
        enabledPreferences: _selectedPrefs.toList(),
      ),
    );

    if (group == null) return;
    if (!mounted) return;

    // Capture router/navigator before async gap.
    final router = GoRouter.of(context);
    final nav = Navigator.of(context);

    // Show success sheet then pop.
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SuccessSheet(
        group: group,
        onDone: () {
          nav.pop(); // close sheet
          router.pop(); // go back to groups list
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Create Group'),
        centerTitle: false,
        leading: _currentStep == 0
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.pop(),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _prevStep,
              ),
      ),
      body: Column(
        children: [
          // Progress indicator
          LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 3,
          ),
          // Step label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Step ${_currentStep + 1} of $_totalSteps',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  _stepTitle(_currentStep),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Pages
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1NameType(
                  nameCtrl: _nameCtrl,
                  descCtrl: _descCtrl,
                  groupType: _groupType,
                  onTypeChanged: (t) => setState(() => _groupType = t),
                  onNext: _nextStep,
                ),
                _Step2MealToggle(
                  mealsEnabled: _mealsEnabled,
                  onChanged: (v) => setState(() => _mealsEnabled = v),
                  onNext: _nextStep,
                ),
                _Step3Preferences(
                  mealsEnabled: _mealsEnabled,
                  preferencesEnabled: _preferencesEnabled,
                  selectedPrefs: _selectedPrefs,
                  onPrefsToggle: (v) =>
                      setState(() => _preferencesEnabled = v),
                  onPrefToggle: (p) => setState(() {
                    if (_selectedPrefs.contains(p)) {
                      _selectedPrefs.remove(p);
                    } else {
                      _selectedPrefs.add(p);
                    }
                  }),
                  onNext: _nextStep,
                ),
                _Step4Capacity(
                  maxMembers: _maxMembers,
                  onChanged: (v) => setState(() => _maxMembers = v),
                  onNext: _nextStep,
                ),
                _Step5Review(
                  name: _nameCtrl.text,
                  desc: _descCtrl.text,
                  groupType: _groupType,
                  mealsEnabled: _mealsEnabled,
                  preferencesEnabled: _preferencesEnabled,
                  selectedPrefs: _selectedPrefs,
                  maxMembers: _maxMembers,
                  isCreating: _provider.isCreating,
                  error: _provider.error,
                  onCreate: _create,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _stepTitle(int step) => switch (step) {
        0 => 'Name & Type',
        1 => 'Meal System',
        2 => 'Preferences',
        3 => 'Capacity',
        _ => 'Review',
      };
}

// ── Step 1: Name + Type ────────────────────────────────────────────────────────

class _Step1NameType extends StatelessWidget {
  const _Step1NameType({
    required this.nameCtrl,
    required this.descCtrl,
    required this.groupType,
    required this.onTypeChanged,
    required this.onNext,
  });

  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final GroupType groupType;
  final ValueChanged<GroupType> onTypeChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final types = GroupType.values;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Name your group',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose a name and type that best describes your group.',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Group Name *',
            hintText: 'e.g. Block A Hostel',
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: descCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'Brief description...',
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Group Type',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: types.map((t) {
            final selected = groupType == t;
            return GestureDetector(
              onTap: () => onTypeChanged(t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : colorScheme.onSurface,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 32),
        AppPrimaryButton(
          label: 'Continue',
          trailingIcon: Icons.arrow_forward_rounded,
          onPressed: nameCtrl.text.trim().isEmpty ? null : onNext,
        ),
      ],
    );
  }
}

// ── Step 2: Meal Toggle ───────────────────────────────────────────────────────

class _Step2MealToggle extends StatelessWidget {
  const _Step2MealToggle({
    required this.mealsEnabled,
    required this.onChanged,
    required this.onNext,
  });

  final bool mealsEnabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Meal System',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Do members need to manage meals, or only mark attendance?',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          _ModeCard(
            icon: Icons.restaurant_rounded,
            title: 'Meals + Attendance',
            subtitle:
                'Configure breakfast, lunch, dinner etc. Members view weekly menus and mark meal attendance.',
            color: AppColors.secondary,
            isSelected: mealsEnabled,
            onTap: () => onChanged(true),
          ),
          const SizedBox(height: 12),
          _ModeCard(
            icon: Icons.how_to_reg_rounded,
            title: 'Attendance Only',
            subtitle:
                'No meal configuration. Members mark daily attendance. Great for coaching institutes and offices.',
            color: AppColors.primary,
            isSelected: !mealsEnabled,
            onTap: () => onChanged(false),
          ),
          const Spacer(),
          AppPrimaryButton(
            label: 'Continue',
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color
                : Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isSelected ? color : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Step 3: Preferences ───────────────────────────────────────────────────────

class _Step3Preferences extends StatelessWidget {
  const _Step3Preferences({
    required this.mealsEnabled,
    required this.preferencesEnabled,
    required this.selectedPrefs,
    required this.onPrefsToggle,
    required this.onPrefToggle,
    required this.onNext,
  });

  final bool mealsEnabled;
  final bool preferencesEnabled;
  final Set<MealPreferenceOption> selectedPrefs;
  final ValueChanged<bool> onPrefsToggle;
  final ValueChanged<MealPreferenceOption> onPrefToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allPrefs = MealPreferenceOption.values;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Meal Preferences',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          mealsEnabled
              ? 'Allow members to tag their preference (Veg, Chicken, Fish, etc.) when marking attendance.'
              : 'Preferences require meals to be enabled. Skipping this step.',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (mealsEnabled) ...[
          // Toggle row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded,
                    color: colorScheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enable Preferences',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Members tag their meal choice before marking attendance',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: preferencesEnabled,
                  onChanged: onPrefsToggle,
                ),
              ],
            ),
          ),
          if (preferencesEnabled) ...[
            const SizedBox(height: 16),
            const Text(
              'Select available preferences:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allPrefs.map((p) {
                final selected = selectedPrefs.contains(p);
                return GestureDetector(
                  onTap: () => onPrefToggle(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.10)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : colorScheme.outlineVariant
                                .withValues(alpha: 0.4),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      '${p.emoji} ${p.label}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.primary : null,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
        const SizedBox(height: 32),
        AppPrimaryButton(
          label: 'Continue',
          trailingIcon: Icons.arrow_forward_rounded,
          onPressed: onNext,
        ),
      ],
    );
  }
}

// ── Step 4: Capacity ──────────────────────────────────────────────────────────

class _Step4Capacity extends StatefulWidget {
  const _Step4Capacity({
    required this.maxMembers,
    required this.onChanged,
    required this.onNext,
  });

  final int? maxMembers;
  final ValueChanged<int?> onChanged;
  final VoidCallback onNext;

  @override
  State<_Step4Capacity> createState() => _Step4CapacityState();
}

class _Step4CapacityState extends State<_Step4Capacity> {
  final _ctrl = TextEditingController();
  bool _limited = false;

  @override
  void initState() {
    super.initState();
    if (widget.maxMembers != null) {
      _limited = true;
      _ctrl.text = widget.maxMembers!.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Member Capacity',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Set a maximum member count, or leave it unlimited.',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.people_rounded,
                    color: colorScheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Limit member count',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: _limited,
                  onChanged: (v) {
                    setState(() {
                      _limited = v;
                      if (!v) {
                        _ctrl.clear();
                        widget.onChanged(null);
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          if (_limited) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Max Members',
                hintText: 'e.g. 150',
                filled: true,
                fillColor: colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) {
                final n = int.tryParse(v);
                widget.onChanged(n);
              },
            ),
          ],
          const Spacer(),
          AppPrimaryButton(
            label: 'Continue',
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: widget.onNext,
          ),
        ],
      ),
    );
  }
}

// ── Step 5: Review + Create ───────────────────────────────────────────────────

class _Step5Review extends StatelessWidget {
  const _Step5Review({
    required this.name,
    required this.desc,
    required this.groupType,
    required this.mealsEnabled,
    required this.preferencesEnabled,
    required this.selectedPrefs,
    required this.maxMembers,
    required this.isCreating,
    required this.error,
    required this.onCreate,
  });

  final String name;
  final String desc;
  final GroupType groupType;
  final bool mealsEnabled;
  final bool preferencesEnabled;
  final Set<MealPreferenceOption> selectedPrefs;
  final int? maxMembers;
  final bool isCreating;
  final String? error;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Review & Create',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Confirm your group details before creating.',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        AppGlassCard(
          glassEnabled: false,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _ReviewRow('Name', name),
              if (desc.isNotEmpty) _ReviewRow('Description', desc),
              _ReviewRow('Type', groupType.label),
              _ReviewRow(
                'Meal System',
                mealsEnabled ? 'Meals + Attendance' : 'Attendance Only',
              ),
              if (mealsEnabled)
                _ReviewRow(
                  'Preferences',
                  preferencesEnabled
                      ? selectedPrefs.isEmpty
                          ? 'Enabled (none selected)'
                          : selectedPrefs.map((p) => p.label).join(', ')
                      : 'Disabled',
                ),
              _ReviewRow(
                'Capacity',
                maxMembers != null ? '$maxMembers members' : 'Unlimited',
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              error!,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        AppPrimaryButton(
          label: 'Create Group',
          icon: Icons.add_rounded,
          isLoading: isCreating,
          onPressed: isCreating ? null : onCreate,
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Success sheet ─────────────────────────────────────────────────────────────

class _SuccessSheet extends StatelessWidget {
  const _SuccessSheet({required this.group, required this.onDone});
  final GroupModel group;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.present,
            size: 60,
          ),
          const SizedBox(height: 16),
          Text(
            '${group.name} created!',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Share the join code with members.',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (group.joinCode != null)
            AppStatusChip.label(
              label: '  ${group.joinCode}  ',
              color: AppColors.primary,
            ),
          const SizedBox(height: 24),
          AppPrimaryButton(
            label: 'Done',
            onPressed: () => context.go('/student/dashboard'),
          ),
        ],
      ),
    );
  }
}
