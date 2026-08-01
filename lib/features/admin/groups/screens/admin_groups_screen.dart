import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:smart_meal_management/features/admin/groups/providers/admin_group_provider.dart';
import 'package:smart_meal_management/features/admin/groups/widgets/group_card.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';
import 'package:smart_meal_management/data/services/group_order_service.dart';

/// Admin groups list screen.
///
/// Lists all groups for the admin's organisation. The FAB opens a creation
/// bottom sheet — never navigates to a non-existent `:groupId` route.
class AdminGroupsScreen extends StatefulWidget {
  const AdminGroupsScreen({super.key, this.initialArchived = false});

  /// Issue 6: when opened from the "Archived Groups" quick action the screen
  /// starts directly in the archived view (GRP-016/018) — no extra tap.
  final bool initialArchived;

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
      // Issue 6: honor the archived-groups quick action deep-link.
      _showArchived = widget.initialArchived;
      _provider.loadGroups(
        organizationId: user.organizationId,
        includeInactive: _showArchived,
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

  /// GRP-007: ALL groups in the user's saved drag order (used for reorder math).
  List<GroupModel> get _orderedGroups =>
      GroupOrderService.instance.applyToGroups(_provider.groups, _order);

  /// Groups for the CURRENT view only. The archived view shows ONLY archived
  /// groups and the active view shows ONLY active ones, so the two never mix in
  /// the same list (live-test bug: archived toggle was showing active groups too).
  List<GroupModel> get _visibleGroups => _orderedGroups
      .where((g) => _showArchived ? !g.isActive : g.isActive)
      .toList();

  /// GRP-007: persist a new drag order after a reorder gesture. Reorder happens
  /// within the VISIBLE subset; hidden groups keep their positions in the full
  /// saved order (so reordering in one view never scrambles the other).
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final visible = _visibleGroups;
    if (newIndex > oldIndex) newIndex -= 1;
    final visibleIds = visible.map((g) => g.id).toList();
    final moved = visibleIds.removeAt(oldIndex);
    visibleIds.insert(newIndex, moved);
    final visibleSet = visible.map((g) => g.id).toSet();
    var vi = 0;
    final merged = _orderedGroups
        .map((g) => visibleSet.contains(g.id) ? visibleIds[vi++] : g.id)
        .toList();
    setState(() => _order = merged);
    await GroupOrderService.instance.save(_userId, merged);
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
      // Issue 2 (follow-up): the sheet's own drag-to-dismiss was claiming every
      // DOWNWARD drag, so the inner form scrolled up but never back down. Disable
      // the sheet drag → the inner SingleChildScrollView owns all vertical
      // gestures (scrolls both ways). Dismiss still works via tap-outside / the
      // Create button / the system back gesture.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateGroupSheet(
        provider: _provider,
        organizationId: orgId,
        // Read HERE, not inside the sheet: the modal route is pushed above
        // AdminDashboardScope, so the sheet itself cannot see it.
        // `maybeOf` because this screen is ALSO reachable as a plain
        // MaterialPageRoute from the notice feed, where no scope exists —
        // `of` would null-check crash in release. Null → rule simply skipped.
        orgName: AdminDashboardScope.maybeOf(context)?.orgName,
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
          // Issue 5: join requests are a GROUP-scoped feature — the entry lives
          // in each group's header + Settings (admin_group_detail_screen). The
          // org-level shortcut here was removed to avoid mixing org/group scope.
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
                        includeInactive: _showArchived, // stay in this scope
                      );
                    },
                    child: const Text('Retry'),
                  ),
                )
              : _visibleGroups.isEmpty
                  ? AppEmptyState(
                      icon: _showArchived
                          ? Icons.inventory_2_outlined
                          : Icons.group_outlined,
                      title:
                          _showArchived ? 'No archived groups' : 'No groups yet',
                      subtitle: _showArchived
                          ? 'Groups you archive will appear here.'
                          : 'Create your first group to get started.',
                      action: _showArchived
                          ? TextButton(
                              onPressed: _toggleArchived,
                              child: const Text('Show active groups'),
                            )
                          : FilledButton.icon(
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
                          includeInactive: _showArchived, // stay in this scope
                        );
                      },
                      // GRP-007: drag-and-drop reordering (persisted per user).
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _visibleGroups.length,
                        onReorder: _onReorder,
                        proxyDecorator: (child, index, animation) => Material(
                          color: Colors.transparent,
                          elevation: 6,
                          borderRadius: BorderRadius.circular(16),
                          child: child,
                        ),
                        itemBuilder: (context, i) {
                          final group = _visibleGroups[i];
                          return Padding(
                            key: ValueKey(group.id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GroupCard(
                              group: group,
                              onTap: () async {
                                // Await the detail route so archive/delete done
                                // there reflect here INSTANTLY on return: the
                                // provider wrote through the shared cache —
                                // repaint from it (local, ~ms), then refresh
                                // silently from the network.
                                await context.push(
                                  RouteNames.adminGroupDetail
                                      .replaceAll(':groupId', group.id),
                                );
                                if (!context.mounted) return;
                                final user = AuthProviderScope.of(context)
                                    .currentUser;
                                if (user == null) return;
                                await _provider.repaintFromCache(
                                  organizationId: user.organizationId,
                                  includeInactive: _showArchived,
                                );
                                _provider.loadGroups(
                                  organizationId: user.organizationId,
                                  includeInactive: _showArchived,
                                );
                              },
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
    this.orgName,
  });

  final AdminGroupProvider provider;
  final String organizationId;

  /// The ORGANISATION's name, so a group cannot be created with it. Null when
  /// it has not resolved yet — the rule is then skipped rather than guessed,
  /// so it can never produce a false rejection.
  final String? orgName;
  final void Function(GroupModel group) onCreated;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _maxMembersCtrl = TextEditingController();
  // GRP-003 (Issue 8): location + join-code policy captured at creation.
  // Country defaults to India and currency to INR (India-only release), so the
  // form only collects State, City, PIN and QR expiry (all mandatory) plus an
  // optional Address (≤30 chars). These are always visible — no longer hidden
  // behind a "More options" toggle since they are required.
  final _stateCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _qrExpiryCtrl = TextEditingController();
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
    // Issue 8: keep validation + Create-enabled state live as the admin types
    // any mandatory field.
    for (final c in [
      _maxMembersCtrl,
      _stateCtrl,
      _cityCtrl,
      _pinCtrl,
      _qrExpiryCtrl,
    ]) {
      c.addListener(_rebuild);
    }
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

  // Issue 8: mandatory State / City / PIN / QR-expiry validation (null = valid).
  String? get _stateError =>
      _stateCtrl.text.trim().isEmpty ? 'Required' : null;
  String? get _cityError => _cityCtrl.text.trim().isEmpty ? 'Required' : null;
  String? get _pinError {
    final v = _pinCtrl.text.trim();
    if (v.isEmpty) return 'Required';
    if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Enter a 6-digit PIN';
    return null;
  }

  /// QR expiry is mandatory but 0 is valid and means "Never expires". Only new
  /// joins are gated by expiry — existing members are never affected.
  String? get _qrExpiryError {
    final v = _qrExpiryCtrl.text.trim();
    if (v.isEmpty) return 'Required (0 = never)';
    final n = int.tryParse(v);
    if (n == null || n < 0) return 'Enter 0 or more days';
    return null;
  }

  // SRS GRP-003: Group Name is 2–50 characters (max enforced by the input
  // limiter; min surfaced here once the admin starts typing).
  String? get _nameError {
    final v = _nameCtrl.text.trim();
    if (v.isEmpty) return 'Required';
    if (v.length < 2) return 'At least 2 characters';
    // A group may not carry the ORGANISATION's own name — every bare-name
    // surface (dashboard header, notices, exports) would become ambiguous.
    // Inline so it blocks Create before a round trip; skipped when the org name
    // is unknown, so it never rejects wrongly.
    final org = widget.orgName?.trim() ?? '';
    if (org.isNotEmpty && v.toLowerCase() == org.toLowerCase()) {
      return 'This is the organisation name — choose another';
    }
    return null;
  }

  bool get _canSubmit =>
      !_saving &&
      _nameError == null &&
      _maxMembersError == null &&
      _stateError == null &&
      _cityError == null &&
      _pinError == null &&
      _qrExpiryError == null;

  @override
  void dispose() {
    for (final c in [
      _maxMembersCtrl,
      _stateCtrl,
      _cityCtrl,
      _pinCtrl,
      _qrExpiryCtrl,
    ]) {
      c.removeListener(_rebuild);
    }
    _nameCtrl.dispose();
    _maxMembersCtrl.dispose();
    _stateCtrl.dispose();
    _cityCtrl.dispose();
    _pinCtrl.dispose();
    _addressCtrl.dispose();
    _qrExpiryCtrl.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  /// Issue 8: metadata field with optional live [error] + [helper] text and a
  /// digits-only / length cap. Used for the always-visible Location & Join Code
  /// section (State/City/PIN/QR-expiry mandatory, Address optional ≤30).
  Widget _reqField(
    TextEditingController ctrl,
    String label,
    ColorScheme colorScheme, {
    bool number = false,
    int? maxLen,
    String? error,
    String? helper,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      textCapitalization:
          number ? TextCapitalization.none : TextCapitalization.words,
      inputFormatters: [
        if (number) FilteringTextInputFormatter.digitsOnly,
        if (maxLen != null) LengthLimitingTextInputFormatter(maxLen),
      ],
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        errorText: error,
        helperText: helper,
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _save() async {
    // Issue 8: name + Max Members + State + City + PIN + QR-expiry are all
    // mandatory and validated live (_canSubmit).
    if (!_canSubmit) return;
    final name = _nameCtrl.text.trim();

    setState(() => _saving = true);

    final maxMembers = int.parse(_maxMembersCtrl.text.trim());
    // 0 = Never expires (backend maps <=0 → no expiry). Only NEW joins are
    // gated by expiry; existing members are never affected.
    final qrExpiry = int.parse(_qrExpiryCtrl.text.trim());

    final group = await widget.provider.createGroup(
      organizationId: widget.organizationId,
      name: name,
      type: _type,
      functionalRole: _functionalRole,
      mealConfig: GroupMealConfig(mealsEnabled: _mealsEnabled),
      maxMembers: maxMembers,
      joinApprovalRequired: _requireApproval,
      // GRP-003 (Issue 8): India-only release — country/currency are fixed; the
      // admin supplies State, City, PIN (mandatory) + optional Address (≤30).
      country: 'India',
      state: _trimOrNull(_stateCtrl),
      city: _trimOrNull(_cityCtrl),
      pin: _trimOrNull(_pinCtrl),
      address: _trimOrNull(_addressCtrl),
      currency: 'INR',
      qrExpiryDays: qrExpiry,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (group != null) {
      Navigator.of(context).pop();
      widget.onCreated(group);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(widget.provider.createError ?? 'Failed to create group'),
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
      // Issue 2: bound the sheet to ~92% of the screen height. Without a max
      // height the sheet grew to its full content height and pushed the top off
      // screen, so the inner SingleChildScrollView never got a bounded viewport
      // to scroll within. Constraining it makes the internal scroll engage and
      // the whole form (incl. the Create button) reachable on every device.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
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
            // SRS GRP-003: cap at 50 characters.
            inputFormatters: [LengthLimitingTextInputFormatter(50)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Group Name *',
              hintText: 'e.g. Hostel Block A, Office Cafeteria',
              helperText: '2–50 characters',
              errorText: _nameCtrl.text.isEmpty ? null : _nameError,
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

          // ── Location & Join Code (GRP-003 / Issue 8) — India only ─────────
          Text(
            'Location & Join Code',
            style: AppTypography.labelMedium
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'India only (currency ₹ INR). State, City, PIN and QR expiry are '
            'required.',
            style: AppTypography.bodySmall
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _reqField(
                _stateCtrl,
                'State *',
                colorScheme,
                error: _stateCtrl.text.isEmpty ? null : _stateError,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _reqField(
                _cityCtrl,
                'City *',
                colorScheme,
                error: _cityCtrl.text.isEmpty ? null : _cityError,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _reqField(
                _pinCtrl,
                'PIN Code *',
                colorScheme,
                number: true,
                maxLen: 6,
                error: _pinCtrl.text.isEmpty ? null : _pinError,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _reqField(
                _qrExpiryCtrl,
                'QR expiry (days) *',
                colorScheme,
                number: true,
                maxLen: 4,
                error: _qrExpiryCtrl.text.isEmpty ? null : _qrExpiryError,
                helper: '0 = never',
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _reqField(
            _addressCtrl,
            'Address (optional)',
            colorScheme,
            maxLen: 30,
            helper: 'Up to 30 characters',
          ),
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
