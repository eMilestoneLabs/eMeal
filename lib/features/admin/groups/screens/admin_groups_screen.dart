import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/admin/groups/providers/admin_group_provider.dart';
import 'package:smart_meal_management/features/admin/groups/widgets/group_card.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';
import 'package:smart_meal_management/features/admin/groups/screens/group_join_requests_screen.dart';
import 'package:smart_meal_management/data/services/group_order_service.dart';

/// Admin groups list screen.
///
/// Lists all groups for the admin's organisation. The FAB opens a creation
/// bottom sheet — never navigates to a non-existent `:groupId` route.
class AdminGroupsScreen extends StatefulWidget {
  const AdminGroupsScreen({super.key});

  @override
  State<AdminGroupsScreen> createState() => _AdminGroupsScreenState();
}

class _AdminGroupsScreenState extends State<AdminGroupsScreen> {
  late final AdminGroupProvider _provider;
  bool _initialized = false;
  // GRP-016/018: toggle the archived-groups view (for restore / permanent delete).
  bool _showArchived = false;
  // GRP-007: device-local drag-and-drop order of groups (per user).
  List<String> _order = const [];
  String _userId = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _provider = AdminGroupProvider();
      _provider.addListener(_rebuild);
      final auth = AuthProviderScope.of(context);
      final user = auth.currentUser;
      if (user == null) return;
      _userId = user.id;
      _provider.loadGroups(
        organizationId: user.organizationId,
      );
      // GRP-007: load the saved drag order (device-local).
      GroupOrderService.instance.load(_userId).then((o) {
        if (mounted) setState(() => _order = o);
      });
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// GRP-007: groups in the user's saved drag order (new groups first).
  List<GroupModel> get _orderedGroups =>
      GroupOrderService.instance.applyToGroups(_provider.groups, _order);

  /// GRP-007: persist a new drag order after a reorder gesture.
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final list = _orderedGroups;
    if (newIndex > oldIndex) newIndex -= 1;
    final ids = list.map((g) => g.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() => _order = ids);
    await GroupOrderService.instance.save(_userId, ids);
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    super.dispose();
  }

  /// GRP-016/018: toggle between the active and archived group views.
  void _toggleArchived() {
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null) return;
    setState(() => _showArchived = !_showArchived);
    _provider.loadGroups(
      organizationId: user.organizationId,
      includeInactive: _showArchived,
    );
  }

  /// Shows the create-group bottom sheet.
  ///
  /// On success, navigates straight to the new group's detail screen.
  Future<void> _showCreateSheet() async {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    final orgId = user.organizationId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateGroupSheet(
        provider: _provider,
        organizationId: orgId,
        onCreated: (group) {
          if (!mounted) return;
          context.push(
            RouteNames.adminGroupDetail.replaceAll(':groupId', group.id),
          );
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
        title: Text('Groups', style: AppTypography.titleLarge),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          // GRP-016/018: premium archived-view toggle. Amber tonal fill when
          // active so the state reads clearly (and richly) in light + dark.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _showArchived
                ? IconButton.filledTonal(
                    tooltip: 'Show active groups',
                    icon: const Icon(Icons.inventory_2_rounded),
                    onPressed: _toggleArchived,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          AppColors.warning.withValues(alpha: 0.18),
                      foregroundColor: AppColors.warning,
                    ),
                  )
                : IconButton(
                    tooltip: 'Show archived groups',
                    icon: const Icon(Icons.inventory_2_outlined),
                    onPressed: _toggleArchived,
                  ),
          ),
          // MODULE_02 (MEM-006/007): open the pending join-request approvals.
          IconButton(
            tooltip: 'Join requests',
            icon: const Icon(Icons.how_to_reg_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const GroupJoinRequestsScreen(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Group'),
      ),
      body: Column(
        children: [
          if (_showArchived) const _ArchivedBanner(),
          Expanded(
            child: _provider.isLoading
          ? const AppListSkeleton(rows: 4, rowHeight: 108)
          : _provider.error != null
              ? AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load groups',
                  subtitle: _provider.error,
                  action: TextButton(
                    onPressed: () {
                      final user = AuthProviderScope.of(context).currentUser;
                      if (user == null) return;
                      _provider.loadGroups(
                        organizationId: user.organizationId,
                      );
                    },
                    child: const Text('Retry'),
                  ),
                )
              : _provider.groups.isEmpty
                  ? AppEmptyState(
                      icon: Icons.group_outlined,
                      title: 'No groups yet',
                      subtitle: 'Create your first group to get started.',
                      action: FilledButton.icon(
                        onPressed: _showCreateSheet,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create Group'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        final user = AuthProviderScope.of(context).currentUser;
                        if (user == null) return;
                        await _provider.loadGroups(
                          organizationId: user.organizationId,
                        );
                      },
                      // GRP-007: drag-and-drop reordering (persisted per user).
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _orderedGroups.length,
                        onReorder: _onReorder,
                        proxyDecorator: (child, index, animation) => Material(
                          color: Colors.transparent,
                          elevation: 6,
                          borderRadius: BorderRadius.circular(16),
                          child: child,
                        ),
                        itemBuilder: (context, i) {
                          final group = _orderedGroups[i];
                          return Padding(
                            key: ValueKey(group.id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GroupCard(
                              group: group,
                              onTap: () => context.push(
                                RouteNames.adminGroupDetail
                                    .replaceAll(':groupId', group.id),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

// ── Archived-mode banner ────────────────────────────────────────────────────────

/// Premium banner shown while browsing archived groups — makes the mode obvious
/// and rich in both light and dark (amber accent matches the archived toggle).
class _ArchivedBanner extends StatelessWidget {
  const _ArchivedBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            AppColors.warning.withValues(alpha: 0.16),
            AppColors.warning.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.inventory_2_rounded,
                color: AppColors.warning, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Archived groups',
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Open a group to restore it or delete it permanently.',
                  style: AppTypography.bodySmall
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Create Group Bottom Sheet ──────────────────────────────────────────────────

/// Modal bottom sheet for creating a new group.
///
/// Collects name + type, calls [AdminGroupProvider.createGroup], then invokes
/// [onCreated] so the parent can navigate to the freshly created group.
class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({
    required this.provider,
    required this.organizationId,
    required this.onCreated,
  });

  final AdminGroupProvider provider;
  final String organizationId;
  final void Function(GroupModel group) onCreated;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _maxMembersCtrl = TextEditingController();
  // GRP-003: extended metadata captured at creation (immutable afterward).
  final _countryCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  final _qrExpiryCtrl = TextEditingController();
  bool _showMoreOptions = false;
  GroupType _type = GroupType.hostel;
  bool _mealsEnabled = true;
  // MODULE_02 (GRP-003/MEM-004): require admin approval for join requests.
  bool _requireApproval = false;
  bool _saving = false;

  // #1: the admin's per-group functional role/title (display-only). Seeded from
  // the group type until the admin explicitly overrides it. Sent to the backend
  // which stores it on GroupMember.functionalRole and shows it everywhere.
  UserRole _functionalRole = UserRole.hostelAdmin;
  bool _roleManuallySet = false;

  // Admin-level titles only — member roles (student/member/guest) belong to the
  // JOIN flow, never to the group creator.
  static const List<UserRole> _roleOptions = [
    UserRole.hostelAdmin,
    UserRole.hostelManager,
    UserRole.messManager,
    UserRole.organizationManager,
    UserRole.eventAdmin,
  ];

  UserRole _defaultRoleForType(GroupType t) {
    switch (t) {
      case GroupType.mess:
      case GroupType.cafeteria:
        return UserRole.messManager;
      case GroupType.hostel:
      case GroupType.pg:
        return UserRole.hostelAdmin;
      case GroupType.event:
        return UserRole.eventAdmin;
      default:
        return UserRole.organizationManager;
    }
  }

  void _onTypeChanged(GroupType t) {
    setState(() {
      _type = t;
      if (!_roleManuallySet) _functionalRole = _defaultRoleForType(t);
    });
  }

  @override
  void initState() {
    super.initState();
    // GRP-004: load config-driven role member limits so the Maximum Members
    // field can validate against the selected role live. Also rebuild as the
    // admin types so the range error / Create-enabled state stay in sync.
    widget.provider.loadLimits().then((_) {
      if (mounted) setState(() {});
    });
    _maxMembersCtrl.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // GRP-004: config-driven range for the CURRENTLY selected role.
  int get _roleMax => widget.provider.memberLimitForRole(_functionalRole);
  int get _minMembers => widget.provider.minMembers;

  /// Validation message for Maximum Members (null = valid). Empty is invalid
  /// (the field is mandatory) but only surfaced as errorText once the admin
  /// starts typing — the disabled Create button conveys "required" beforehand.
  String? get _maxMembersError {
    final raw = _maxMembersCtrl.text.trim();
    if (raw.isEmpty) return 'Required';
    final v = int.tryParse(raw);
    if (v == null) return 'Enter a number';
    if (v < _minMembers || v > _roleMax) {
      return 'Value must be $_minMembers to $_roleMax';
    }
    return null;
  }

  bool get _canSubmit =>
      !_saving &&
      _nameCtrl.text.trim().isNotEmpty &&
      _maxMembersError == null;

  @override
  void dispose() {
    _maxMembersCtrl.removeListener(_rebuild);
    _nameCtrl.dispose();
    _maxMembersCtrl.dispose();
    _countryCtrl.dispose();
    _stateCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _currencyCtrl.dispose();
    _qrExpiryCtrl.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Widget _metaField(
    TextEditingController ctrl,
    String label,
    ColorScheme colorScheme, {
    bool number = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      textCapitalization:
          number ? TextCapitalization.none : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    // GRP-004: name + a valid role-capped Maximum Members are both mandatory.
    if (name.isEmpty || _maxMembersError != null) return;

    setState(() => _saving = true);

    final maxMembers = int.parse(_maxMembersCtrl.text.trim());

    final qrExpiry = int.tryParse(_qrExpiryCtrl.text.trim());

    final group = await widget.provider.createGroup(
      organizationId: widget.organizationId,
      name: name,
      type: _type,
      functionalRole: _functionalRole,
      mealConfig: GroupMealConfig(mealsEnabled: _mealsEnabled),
      maxMembers: maxMembers,
      joinApprovalRequired: _requireApproval,
      // GRP-003: extended metadata (immutable after creation).
      country: _trimOrNull(_countryCtrl),
      state: _trimOrNull(_stateCtrl),
      city: _trimOrNull(_cityCtrl),
      address: _trimOrNull(_addressCtrl),
      currency: _trimOrNull(_currencyCtrl),
      qrExpiryDays: (qrExpiry != null && qrExpiry > 0) ? qrExpiry : null,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (group != null) {
      Navigator.of(context).pop();
      widget.onCreated(group);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.provider.error ?? 'Failed to create group'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottom),
      // Scrollable so the whole form (and the Create button) is always reachable
      // — including with the keyboard up on short screens.
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Create New Group',
            style: AppTypography.titleMedium
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Set up a hostel, mess, cafeteria or any group.',
            style: AppTypography.bodySmall
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // ── Group Name ─────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Group Name *',
              hintText: 'e.g. Hostel Block A, Office Cafeteria',
              filled: true,
              fillColor: colorScheme.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Group Type ─────────────────────────────────────────────────
          Text(
            'Group Type',
            style: AppTypography.labelMedium
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _TypeGrid(
            selected: _type,
            onSelected: _onTypeChanged,
          ),
          const SizedBox(height: 16),

          // ── #1: Your role in this group (per-group display title) ──────
          Text(
            'Your Role in this Group',
            style: AppTypography.labelMedium
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Shown everywhere for this group. You can hold a different role '
            'in each group. Display only — it never changes your permissions.',
            style: AppTypography.bodySmall
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _roleOptions.map((r) {
              final selected = _functionalRole == r;
              return GestureDetector(
                onTap: () => setState(() {
                  _functionalRole = r;
                  _roleManuallySet = true;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) ...[
                        const Icon(Icons.check_rounded,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        r.label,
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ── Meals toggle ───────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              title: Text(
                'Enable Meal System',
                style: AppTypography.labelMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _mealsEnabled
                    ? 'Students can view menus and mark meal attendance.'
                    : 'Attendance only — no meal features.',
                style: AppTypography.bodySmall
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
              value: _mealsEnabled,
              onChanged: (v) => setState(() => _mealsEnabled = v),
            ),
          ),
          const SizedBox(height: 16),

          // ── Maximum Members (GRP-004) — mandatory, capped by SELECTED role ─
          TextField(
            controller: _maxMembersCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: 'Maximum Members *',
              hintText:
                  'Between $_minMembers and $_roleMax (${_functionalRole.label})',
              helperText: 'Cap follows your selected role.',
              // Only surface the range/format error once the admin types.
              errorText:
                  _maxMembersCtrl.text.isEmpty ? null : _maxMembersError,
              filled: true,
              fillColor: colorScheme.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Join Approval Mode (GRP-003 / MEM-004) ────────────────────────
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              title: Text(
                'Require Approval to Join',
                style: AppTypography.labelMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _requireApproval
                    ? 'New members wait for your approval before joining.'
                    : 'Anyone with the code/QR joins immediately.',
                style: AppTypography.bodySmall
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
              value: _requireApproval,
              onChanged: (v) => setState(() => _requireApproval = v),
            ),
          ),
          const SizedBox(height: 8),

          // ── More options (GRP-003 location/currency/QR expiry) ────────────
          InkWell(
            onTap: () => setState(() => _showMoreOptions = !_showMoreOptions),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _showMoreOptions
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'More options (location, currency, QR expiry)',
                    style: AppTypography.labelMedium
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (_showMoreOptions) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _metaField(_countryCtrl, 'Country', colorScheme)),
              const SizedBox(width: 10),
              Expanded(child: _metaField(_stateCtrl, 'State', colorScheme)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _metaField(_cityCtrl, 'City', colorScheme)),
              const SizedBox(width: 10),
              Expanded(
                  child: _metaField(_currencyCtrl, 'Currency (e.g. INR)',
                      colorScheme)),
            ]),
            const SizedBox(height: 10),
            _metaField(_addressCtrl, 'Address', colorScheme),
            const SizedBox(height: 10),
            _metaField(
              _qrExpiryCtrl,
              'QR expiry in days (blank = never)',
              colorScheme,
              number: true,
            ),
          ],
          const SizedBox(height: 24),

          // ── Save ───────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _canSubmit ? _save : null,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Create Group',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ── Group type grid ────────────────────────────────────────────────────────────

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({required this.selected, required this.onSelected});

  final GroupType selected;
  final ValueChanged<GroupType> onSelected;

  static const _types = [
    (GroupType.hostel,          'Hostel',      Icons.apartment_rounded),
    (GroupType.mess,            'Mess',        Icons.restaurant_rounded),
    (GroupType.cafeteria,       'Cafeteria',   Icons.local_cafe_rounded),
    (GroupType.pg,              'PG',          Icons.home_rounded),
    (GroupType.office,          'Office',      Icons.business_rounded),
    (GroupType.coachingInstitute,'Coaching',   Icons.school_rounded),
    (GroupType.factory_,        'Factory',     Icons.factory_rounded),
    (GroupType.community,       'Community',   Icons.people_rounded),
    (GroupType.event,           'Event',       Icons.celebration_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _types.map((entry) {
        final (type, label, icon) = entry;
        final isSelected = selected == type;
        return _TypeChip(
          label: label,
          icon: icon,
          isSelected: isSelected,
          onTap: () => onSelected(type),
        );
      }).toList(),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.10)
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? AppColors.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppColors.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
