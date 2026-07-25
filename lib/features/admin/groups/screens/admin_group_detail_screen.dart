import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/core/utils/qr_payload_parser.dart';
import 'package:smart_meal_management/core/utils/qr_share.dart';
import 'package:smart_meal_management/features/admin/groups/providers/admin_group_provider.dart';
import 'package:smart_meal_management/features/admin/groups/screens/group_join_requests_screen.dart';
import 'package:smart_meal_management/features/admin/groups/widgets/group_member_tile.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/shared/widgets/app_glass_card.dart';
import 'package:smart_meal_management/shared/widgets/app_primary_button.dart';
import 'package:smart_meal_management/shared/widgets/app_status_chip.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Admin group detail screen with Members / Meals / Settings tabs.
class AdminGroupDetailScreen extends StatefulWidget {
  const AdminGroupDetailScreen({
    super.key,
    required this.groupId,
    required this.organizationId,
  });

  final String groupId;
  final String organizationId;

  @override
  State<AdminGroupDetailScreen> createState() => _AdminGroupDetailScreenState();
}

class _AdminGroupDetailScreenState extends State<AdminGroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AdminGroupProvider _provider;
  late final TabController _tabController;
  bool _initialized = false;
  String _currentUserId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _provider = AdminGroupProvider();
    _provider.addListener(_rebuild);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final auth = AuthProviderScope.of(context);
      _currentUserId = auth.currentUser?.id ?? '';
      _provider.selectGroup(
        groupId: widget.groupId,
        organizationId: widget.organizationId,
      );
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _provider.removeListener(_rebuild);
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = _provider.selectedGroup;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: group == null && _provider.isLoading
          ? const AppDetailSkeleton()
          : group == null
              ? const Center(child: Text('Group not found'))
              : _GroupDetailBody(
                  group: group,
                  provider: _provider,
                  tabController: _tabController,
                  currentUserId: _currentUserId,
                  organizationId: widget.organizationId,
                ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _GroupDetailBody extends StatelessWidget {
  const _GroupDetailBody({
    required this.group,
    required this.provider,
    required this.tabController,
    required this.currentUserId,
    required this.organizationId,
  });

  final GroupModel group;
  final AdminGroupProvider provider;
  final TabController tabController;
  final String currentUserId;
  final String organizationId;

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        _GroupAppBar(
          group: group,
          provider: provider,
          organizationId: organizationId,
          forceElevated: innerBoxIsScrolled,
        ),
      ],
      body: Column(
        children: [
          // Tab bar
          TabBar(
            controller: tabController,
            tabs: const [
              Tab(text: 'Members'),
              Tab(text: 'Meals'),
              Tab(text: 'Settings'),
            ],
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                _MembersTab(
                  group: group,
                  provider: provider,
                  currentUserId: currentUserId,
                  organizationId: organizationId,
                ),
                _MealsTab(
                  group: group,
                  provider: provider,
                  organizationId: organizationId),
                _SettingsTab(
                  group: group,
                  provider: provider,
                  organizationId: organizationId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────

class _GroupAppBar extends StatelessWidget {
  const _GroupAppBar({
    required this.group,
    required this.provider,
    required this.organizationId,
    required this.forceElevated,
  });

  final GroupModel group;
  final AdminGroupProvider provider;
  final String organizationId;
  final bool forceElevated;

  /// GRP-009: rename the group (Name is editable; Country/Timezone/Currency/
  /// MaxMembers/JoinApprovalMode remain immutable). The provider updates
  /// selectedGroup on success, so the header reflects the new name live.
  Future<void> _rename(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: group.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 50, // SRS GRP-003: Group Name 2–50 characters.
          decoration: const InputDecoration(
            labelText: 'Group name',
            hintText: 'e.g. Hostel Block A',
            helperText: '2–50 characters',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    // No change / cancelled / cleared → nothing to do.
    if (newName == null || newName.isEmpty || newName == group.name) return;
    // SRS GRP-003: enforce the 2-char floor client-side (max capped at 50 by
    // the field) so a too-short rename fails fast with a clear message.
    if (newName.length < 2) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Group name must be 2–50 characters'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final ok = await provider.updateGroup(
      organizationId: organizationId,
      groupId: group.id,
      name: newName,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Group renamed' : 'Could not rename group'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Live-Test-11 ISSUE-006: long group names must show in FULL. Measure how
    // many lines the name actually needs in the space beside the rename
    // pencil and the status chip, wrap to that many lines (up to 4 — beyond
    // that is pathological input) and grow the header to match. Responsive,
    // never a "Midnapore…" cut.
    const nameStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      height: 1.2,
    );
    final screenW = MediaQuery.of(context).size.width;
    // ISSUE-007: the name owns the FULL header width (only the horizontal
    // padding is reserved) — status, chips and the join code live on their
    // own rows below and can never squeeze the title.
    final nameMaxW = (screenW - 40).clamp(80.0, 600.0);
    final painter = TextPainter(
      text: TextSpan(text: group.name, style: nameStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: nameMaxW.toDouble());
    final nameLines = painter.computeLineMetrics().length.clamp(1, 4);

    return SliverAppBar(
      // ISSUE-007: base height covers name (1 line) + edit/status row + meta
      // row; each extra measured name line grows the header dynamically.
      expandedHeight: 186 + (nameLines - 1) * 26.0,
      floating: false,
      pinned: true,
      forceElevated: forceElevated,
      backgroundColor: colorScheme.surface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        // MEM-006/007: group-specific join-request approvals with a live badge.
        IconButton(
          tooltip: 'Join requests',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupJoinRequestsScreen(
                groupId: group.id,
                groupName: group.name,
              ),
            ),
          ),
          icon: Badge(
            isLabelVisible: group.pendingCount > 0,
            label: Text('${group.pendingCount}'),
            child: const Icon(Icons.how_to_reg_rounded),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.qr_code_rounded),
          tooltip: 'Show QR Code',
          onPressed: () => _showQrSheet(context),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.08),
                AppColors.primaryContainer,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // ISSUE-007: the group name owns the full header width and
                  // wraps to as many lines as the measurement above allows —
                  // ellipsis only guards truly pathological names. Nothing
                  // shares this row, so the title is never squeezed.
                  Text(
                    group.name,
                    style: nameStyle,
                    maxLines: nameLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // GRP: rename the group (Name is editable per SRS
                      // GRP-009). Shown for active groups; hidden archived.
                      if (group.isActive)
                        InkWell(
                          onTap: () => _rename(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.edit_rounded,
                                    size: 15, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  'Edit name',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Spacer(),
                      AppStatusChip.label(
                        label: group.isActive ? 'Active' : 'Archived',
                        color: group.isActive
                            ? AppColors.present
                            : AppColors.textTertiary,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // ISSUE-007: meta chips flow in a Wrap — long member counts
                  // or join codes overflow to the next line instead of
                  // clipping on narrow screens.
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppStatusChip.label(
                        label: group.type.label,
                        color: AppColors.primary,
                        compact: true,
                      ),
                      AppStatusChip.label(
                        label: '${group.memberCount} members',
                        color: AppColors.secondary,
                        compact: true,
                      ),
                      if (group.joinCode != null) ...[
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: group.joinCode!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Join code copied'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.copy_rounded,
                                    size: 11, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  group.joinCode!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showQrSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _QrBottomSheet(
        group: group,
        provider: provider,
        organizationId: organizationId,
      ),
    );
  }
}

// ── QR bottom sheet ───────────────────────────────────────────────────────────

class _QrBottomSheet extends StatefulWidget {
  const _QrBottomSheet({
    required this.group,
    required this.provider,
    required this.organizationId,
  });

  final GroupModel group;
  final AdminGroupProvider provider;
  final String organizationId;

  @override
  State<_QrBottomSheet> createState() => _QrBottomSheetState();
}

class _QrBottomSheetState extends State<_QrBottomSheet> {
  // Keyed RepaintBoundary around the QR card so the COMPLETE card (QR + code)
  // can be captured and shared as an image (FR-GRP QR share).
  final GlobalKey _qrCardKey = GlobalKey();
  bool _sharing = false;

  GroupModel get group => widget.group;
  AdminGroupProvider get provider => widget.provider;

  Future<void> _shareQrImage(String code) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Issue 3: render the branded QR straight to PNG (no widget-capture race)
      // so admins can share the premium QR image to WhatsApp — not just text.
      final qrData = QrPayloadParser.encodeGroupQr(
        groupId: group.id,
        joinToken: code,
      );
      await QrShare.shareGroupQr(
        qrData: qrData,
        joinCode: code,
        groupName: group.name,
        text: 'Join "${group.name}" on MealAttend!\n\n'
            'Use code: $code\n\n'
            'Open the app → Scan QR or enter code to join.',
        subject: 'Join ${group.name}',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final code = group.joinCode ?? '------';
    // Encode as structured payload for QR pattern generation.
    // When backend is added, replace joinToken with a real JWT.
    final qrData = QrPayloadParser.encodeGroupQr(
      groupId: group.id,
      joinToken: code,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 12, 24, 24 + MediaQuery.viewPaddingOf(context).bottom),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Text('Group Join QR',
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Members scan this to join ${group.name}',
            style: AppTypography.bodySmall.copyWith(
                color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // ── QR visual card ─────────────────────────────────────────────────
          RepaintBoundary(
            key: _qrCardKey,
            child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Real scannable QR code — encoded with QrPayloadParser structured format.
                // Students scan this with QrScannerView; QrPayloadParser decodes the payload.
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black87,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                // Join code display
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 7,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                // Expiry info
                const Text(
                  'Valid until regenerated',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black38,
                  ),
                ),
              ],
            ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Action buttons ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton.outlined(
                  label: 'Copy Code',
                  icon: Icons.copy_rounded,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Join code copied'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppPrimaryButton.outlined(
                  label: _sharing ? 'Sharing…' : 'Share QR',
                  icon: Icons.share_rounded,
                  onPressed: () => _shareQrImage(code),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppPrimaryButton(
            label: 'Regenerate Code',
            icon: Icons.refresh_rounded,
            onPressed: () async {
              final nav = Navigator.of(context);
              await provider.regenerateQR(group.id);
              nav.pop();
            },
          ),
        ],
      ),
          ),
        ),
    );
  }
}

// _QrPatternPainter removed — replaced by real qr_flutter QrImageView.
// Admin QR codes are now fully scannable by QrScannerView + QrPayloadParser.

// ── Members tab ───────────────────────────────────────────────────────────────

class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.group,
    required this.provider,
    required this.currentUserId,
    required this.organizationId,
  });

  final GroupModel group;
  final AdminGroupProvider provider;
  final String currentUserId;
  final String organizationId;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoadingMembers) {
      return const AppListSkeleton(rows: 6, rowHeight: 64, withAvatar: true);
    }

    final members = provider.selectedGroupMembers;
    if (members.isEmpty) {
      return const AppEmptyState(
        icon: Icons.group_off_rounded,
        title: 'No members yet',
        subtitle: 'Share the join code or QR to invite members.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: members.length,
      itemBuilder: (context, i) {
        final member = members[i];
        final isBlocked = provider.isMemberBlocked(member.id);
        return GroupMemberTile(
          member: member,
          isCurrentUser: member.id == currentUserId,
          isBlocked: isBlocked,
          onPromote: member.role.isAdmin
              ? null
              : () => _confirmPromote(context, member),
          onBlock: (member.id == currentUserId || isBlocked)
              ? null
              : () => _confirmBlock(context, member),
          onUnblock: isBlocked
              ? () => _unblock(context, member)
              : null,
          onRemove: member.id == currentUserId
              ? null
              : () => _confirmRemove(context, member),
        );
      },
    );
  }

  Future<void> _confirmBlock(BuildContext context, UserModel member) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block Member?'),
        content: Text(
          '${member.name} will not be able to mark attendance or access group features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.blockMember(groupId: group.id, userId: member.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${member.name} blocked'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _unblock(BuildContext context, UserModel member) async {
    final messenger = ScaffoldMessenger.of(context);
    await provider.unblockMember(groupId: group.id, userId: member.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('${member.name} unblocked'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmPromote(
      BuildContext context, UserModel member) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promote to Admin?'),
        content: Text(
          '${member.name} will gain admin access to this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Promote'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await provider.promoteToAdmin(
        groupId: group.id,
        userId: member.id,
      );
      if (ok) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${member.name} promoted to admin'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context, UserModel member) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text(
          '${member.name} will be removed from this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await provider.removeMember(
        groupId: group.id,
        userId: member.id,
        organizationId: organizationId,
      );
      if (ok) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${member.name} removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ── Meals tab ─────────────────────────────────────────────────────────────────

/// Dynamically shows all configured meals for the group.
///
/// Meals are loaded from [AdminGroupProvider.selectedGroupMeals] via
/// [MealRepository] — never hardcoded to Breakfast/Lunch/Snacks/Dinner.
/// The admin can configure any number of meals with custom names and windows.
class _MealsTab extends StatelessWidget {
  const _MealsTab({
    required this.group,
    required this.provider,
    required this.organizationId,
  });

  final GroupModel group;
  final AdminGroupProvider provider;
  final String organizationId;

  @override
  Widget build(BuildContext context) {
    final config = group.mealConfig;
    final colorScheme = Theme.of(context).colorScheme;
    // Guidebook §2: the shared meal cache now carries the SUPERSET (active +
    // disabled) so the Master Meal Template can re-enable a disabled meal.
    // This read-only summary tab shows ACTIVE meals only — its previous
    // behaviour, preserved by filtering at the display site rather than
    // narrowing the shared cache.
    final meals = provider.selectedGroupMeals
        .where((m) => m.isActive)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Meal system status ─────────────────────────────────────────────
        AppGlassCard(
          glassEnabled: false,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    config.mealsEnabled
                        ? Icons.restaurant_rounded
                        : Icons.no_meals_rounded,
                    color: config.mealsEnabled
                        ? AppColors.secondary
                        : AppColors.textTertiary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      config.mealsEnabled
                          ? 'Meal System: Enabled'
                          : 'Attendance-Only Mode',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (config.mealsEnabled)
                    AppStatusChip.label(
                      label: '${meals.length} meals',
                      color: AppColors.secondary,
                      compact: true,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                config.mealsEnabled
                    ? 'Members can view the weekly menu and mark meal attendance.'
                    : 'Meals are disabled. Members only mark daily attendance.',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Dynamic meal list ──────────────────────────────────────────────
        if (config.mealsEnabled) ...[
          if (provider.isLoadingMeals)
            const AppSheetSkeleton(rows: 2, rowHeight: 56, padding: EdgeInsets.symmetric(vertical: 12))
          else if (meals.isEmpty)
            AppGlassCard(
              glassEnabled: false,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_menu_rounded,
                    size: 32,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No meals configured yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Go to Master Meal Template to add meals for this group.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          else
            AppGlassCard(
              glassEnabled: false,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Text(
                          'Configured Meals',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const Spacer(),
                        Text(
                          '${meals.length} meal${meals.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...meals.asMap().entries.map((entry) {
                    final i = entry.key;
                    final meal = entry.value;
                    final isLast = i == meals.length - 1;
                    return _MealRow(meal: meal, isLast: isLast);
                  }),
                ],
              ),
            ),
          const SizedBox(height: 12),

          // ── Preferences ──────────────────────────────────────────────────
          AppGlassCard(
            glassEnabled: false,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Meal Preferences',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const Spacer(),
                    AppStatusChip.label(
                      label: config.preferencesEnabled ? 'On' : 'Off',
                      color: config.preferencesEnabled
                          ? AppColors.present
                          : AppColors.textTertiary,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  config.preferencesEnabled
                      ? 'Members select a preference (Veg/Chicken/Fish/etc.) when marking attendance.'
                      : 'Disabled — members just mark present/absent.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (config.preferencesEnabled &&
                    config.enabledPreferences.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: config.enabledPreferences
                        .map((p) => Chip(
                              label: Text(
                                '${p.emoji} ${p.label}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Action button ──────────────────────────────────────────────────
        AppPrimaryButton(
          label: 'Manage Master Meal Template',
          icon: Icons.settings_rounded,
          onPressed: () => context.push(RouteNames.adminMealConfig),
        ),
        // Weekly Meal Mode and Day-Wise Meal Mode are mutually exclusive. The
        // schedule entry point mirrors the active mode and is hidden entirely
        // when meals are off or the weekly menu is disabled (so the weekly menu
        // is hidden from the admin too, matching the student side).
        if (config.mealsEnabled && config.dayWiseMealsEnabled) ...[
          const SizedBox(height: 8),
          AppPrimaryButton.outlined(
            label: 'Daily Plan',
            icon: Icons.today_rounded,
            onPressed: () => context.push(
              '${RouteNames.adminMealSchedule}?groupId=${group.id}&mode=daywise',
            ),
          ),
        ] else if (config.mealsEnabled && config.weeklyMenuEnabled) ...[
          const SizedBox(height: 8),
          AppPrimaryButton.outlined(
            label: 'Weekly Schedule',
            icon: Icons.calendar_month_rounded,
            onPressed: () => context.push(
              '${RouteNames.adminMealSchedule}?groupId=${group.id}',
            ),
          ),
        ],
      ],
    );
  }
}

/// A single dynamic meal row — shows meal name, type chip, and attendance window.
class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal, required this.isLast});
  final MealModel meal;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final window = TimeFormat.window12(
        meal.attendanceWindow.openTime, meal.attendanceWindow.closeTime);

    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  meal.icon,
                  size: 17,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meal.slotKey,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    window,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppStatusChip.label(
                    label: meal.isActive ? 'Active' : 'Inactive',
                    color: meal.isActive
                        ? AppColors.present
                        : AppColors.textTertiary,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1),
    ],
  );
}
}

// ── Settings tab ──────────────────────────────────────────────────────────────

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({
    required this.group,
    required this.provider,
    required this.organizationId,
  });

  final GroupModel group;
  final AdminGroupProvider provider;
  final String organizationId;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _togglingMeals = false;
  bool _togglingWeeklyMenu = false;
  bool _togglingDayWise = false;
  bool _archiving = false;
  // GRP-018/019: restore + permanent-delete busy flags.
  bool _restoring = false;

  Future<void> _toggleMeals(bool newValue) async {
    setState(() => _togglingMeals = true);
    final mc = widget.group.mealConfig;
    // Enabling the meal system must activate a delivery mode if none is set
    // (truth table: Meals ON requires exactly one of Weekly / Day-Wise ON).
    final needsMode =
        newValue && !mc.weeklyMenuEnabled && !mc.dayWiseMealsEnabled;
    final newConfig = mc.copyWith(
      mealsEnabled: newValue,
      weeklyMenuEnabled: needsMode ? true : mc.weeklyMenuEnabled,
    );
    final ok = await widget.provider.updateGroup(
      organizationId: widget.organizationId,
      groupId: widget.group.id,
      mealConfig: newConfig,
    );
    if (!mounted) return;
    setState(() => _togglingMeals = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (newValue ? 'Meal system enabled' : 'Meal system disabled')
            : 'Failed to update meal settings'),
      ),
    );
  }

  Future<void> _toggleWeeklyMenu(bool newValue) async {
    setState(() => _togglingWeeklyMenu = true);
    final newConfig = widget.group.mealConfig.copyWith(
      weeklyMenuEnabled: newValue,
      // Strict one-of-two: Weekly ON disables Day-Wise; Weekly OFF enables
      // Day-Wise (the meal system always keeps exactly one delivery mode).
      dayWiseMealsEnabled: !newValue,
    );
    final ok = await widget.provider.updateGroup(
      organizationId: widget.organizationId,
      groupId: widget.group.id,
      mealConfig: newConfig,
    );
    if (!mounted) return;
    setState(() => _togglingWeeklyMenu = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (newValue ? 'Weekly menu enabled' : 'Weekly menu disabled')
            : 'Failed to update weekly menu setting'),
      ),
    );
  }

  Future<void> _toggleDayWiseMeals(bool newValue) async {
    setState(() => _togglingDayWise = true);
    final newConfig = widget.group.mealConfig.copyWith(
      dayWiseMealsEnabled: newValue,
      // Strict one-of-two: Day-Wise ON disables Weekly Menu; Day-Wise OFF
      // re-enables Weekly (the meal system always keeps exactly one mode).
      weeklyMenuEnabled: !newValue,
    );
    final ok = await widget.provider.updateGroup(
      organizationId: widget.organizationId,
      groupId: widget.group.id,
      mealConfig: newConfig,
    );
    if (!mounted) return;
    setState(() => _togglingDayWise = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (newValue
                ? 'Day-Wise meal mode enabled'
                : 'Day-Wise meal mode disabled')
            : 'Failed to update day-wise setting'),
      ),
    );
  }

  // ISSUE-011: the per-group preference toggle + type-chip updaters were
  // removed — Meal Preference configuration now lives ONLY in the Master
  // Meal Template (single source of truth). Settings shows a pointer card.

  Future<void> _confirmArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Group?'),
        content: Text(
          'Archiving "${widget.group.name}" hides it and removes all member '
          'access. You can restore it later from the archived group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Ultra-smooth (same pattern as permanent delete): the provider updates the
    // shared list caches optimistically, so return to the list IMMEDIATELY —
    // no blocking spinner — while the server confirms in the background. On the
    // rare failure the snackbar surfaces it and the list's silent network
    // refresh restores the group.
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _archiving = true);
    final future = widget.provider.archiveGroup(
      widget.group.id,
      organizationId: widget.organizationId,
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Group archived')),
    );
    nav.pop();
    final ok = await future;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Failed to archive — the group is still active')),
      );
    }
  }

  /// GRP-018: restore an archived group.
  Future<void> _confirmRestore() async {
    setState(() => _restoring = true);
    final ok = await widget.provider.restoreGroup(
      widget.group.id,
      organizationId: widget.organizationId,
    );
    if (!mounted) return;
    setState(() => _restoring = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group restored')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.provider.createError ?? 'Failed to restore')),
      );
    }
  }

  /// GRP-019: permanently delete a group — irreversible, danger-confirmed by
  /// typing the group name.
  Future<void> _confirmPermanentDelete() async {
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Permanently delete group?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes "${widget.group.name}" and ALL of its '
                'data (members, meals, attendance, billing). This CANNOT be '
                'undone.\n\nType the group name to confirm:',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  hintText: widget.group.name,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: confirmCtrl.text.trim() == widget.group.name
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('Delete forever'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Ultra-smooth (additive): the provider removes the group from the list
    // synchronously, so we return to the list IMMEDIATELY — no 5–6s spinner —
    // while the backend cascade finishes in the background. On the rare failure
    // the provider rolls back (the group re-appears) and we surface the error.
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final future = widget.provider.permanentDeleteGroup(
      widget.group.id,
      organizationId: widget.organizationId,
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Group permanently deleted')),
    );
    nav.pop();
    final ok = await future;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.provider.createError ?? 'Delete failed — group restored',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final group = widget.group;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Join requests (MEM-006/007) — group-specific approvals entry ──────
        _JoinRequestsTile(group: group),
        const SizedBox(height: 12),
        // ── Join code ─────────────────────────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Join Code',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.joinCode ?? '------',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 6,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await widget.provider.regenerateQR(group.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('New join code generated')),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Regenerate'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Meal system toggle ────────────────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          child: SwitchListTile(
            title: const Text('Meals Enabled',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              group.mealConfig.mealsEnabled
                  ? 'Students can view the weekly menu and mark meal attendance.'
                  : 'Attendance only mode — meal UI is hidden for students.',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            value: group.mealConfig.mealsEnabled,
            onChanged: _togglingMeals ? null : _toggleMeals,
            secondary: _togglingMeals
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ),

        // ── Meal sub-toggles (shown only when meals are enabled) ──────────────
        if (group.mealConfig.mealsEnabled) ...[
          const SizedBox(height: 10),
          // Weekly menu toggle
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Weekly Menu',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                group.mealConfig.weeklyMenuEnabled
                    ? 'Members can view the published weekly meal schedule.'
                    : 'Weekly menu hidden from members.',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              value: group.mealConfig.weeklyMenuEnabled,
              onChanged: _togglingWeeklyMenu ? null : _toggleWeeklyMenu,
              secondary: _togglingWeeklyMenu
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calendar_month_rounded,
                      color: AppColors.primary, size: 20),
            ),
          ),
          const SizedBox(height: 10),
          // Day-Wise Meals toggle (mutually exclusive with Weekly Menu)
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Day-Wise Meals',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                group.mealConfig.dayWiseMealsEnabled
                    ? 'Members see only the meals configured for today. Weekly Menu is hidden.'
                    : 'Disabled — enable to run meals per calendar day instead of a weekly plan.',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              value: group.mealConfig.dayWiseMealsEnabled,
              onChanged: _togglingDayWise ? null : _toggleDayWiseMeals,
              secondary: _togglingDayWise
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.today_rounded,
                      color: AppColors.primary, size: 20),
            ),
          ),
          const SizedBox(height: 10),
          // ISSUE-011: Meal Preference configuration now lives ONLY in the
          // Master Meal Template (single source of truth). The old per-group
          // toggle + Active Preference Types chips are gone — this pointer
          // card sends admins to the right place.
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading:
                  const Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
              title: const Text('Meal Preferences',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Managed centrally in Meals → Master Meal Template → Meal '
                'System. The global switch there governs every meal; each '
                'meal can add its own tags or preference groups.',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              trailing:
                  const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => context.go(RouteNames.adminMealConfig),
            ),
          ),
        ],

        const SizedBox(height: 16),

        // ── Danger zone (GRP-016/018/019) — premium, theme-adaptive ───────────
        Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: colorScheme.error),
            const SizedBox(width: 8),
            Text(
              'Danger Zone',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (group.isActive)
          _DangerTile(
            icon: Icons.archive_rounded,
            color: AppColors.warning,
            title: 'Archive Group',
            subtitle:
                'Hide the group and remove member access. Restorable later.',
            busy: _archiving,
            onTap: _archiving ? null : _confirmArchive,
          )
        else
          _DangerTile(
            icon: Icons.unarchive_rounded,
            color: AppColors.present,
            title: 'Restore Group',
            subtitle: 'Make this group active again with all its data.',
            busy: _restoring,
            onTap: _restoring ? null : _confirmRestore,
          ),
        const SizedBox(height: 12),
        // GRP-019: permanent delete — always available, irreversible.
        _DangerTile(
          icon: Icons.delete_forever_rounded,
          color: colorScheme.error,
          title: 'Delete Permanently',
          subtitle: 'Remove the group and ALL its data. Cannot be undone.',
          // Ultra-smooth: delete returns to the list instantly (optimistic),
          // so no busy/disabled state is needed here.
          busy: false,
          onTap: _confirmPermanentDelete,
        ),
      ],
    );
  }

}

/// Premium group-specific "Join Requests" entry for the Settings tab — shows a
/// live pending count and opens the scoped approvals screen. Legible in both
/// themes; the accent turns amber when requests are waiting.
class _JoinRequestsTile extends StatelessWidget {
  const _JoinRequestsTile({required this.group});
  final GroupModel group;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pending = group.pendingCount;
    final hasPending = pending > 0;
    final accent = hasPending ? AppColors.warning : AppColors.primary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupJoinRequestsScreen(
              groupId: group.id,
              groupName: group.name,
            ),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.18 : 0.10),
                accent.withValues(alpha: isDark ? 0.07 : 0.04),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.42 : 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.how_to_reg_rounded, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Join Requests',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hasPending
                            ? '$pending waiting for your approval'
                            : 'No one is waiting to join',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (hasPending)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$pending',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: accent.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Premium, theme-adaptive danger-zone action tile.
///
/// Renders a tinted gradient surface with a rounded icon badge, ripple, and a
/// subtle press-scale — legible and rich in BOTH light and dark themes. The
/// accent [color] drives the whole tile (amber = archive, green = restore, red
/// = delete); subtitle uses onSurfaceVariant so it stays readable on the tint.
class _DangerTile extends StatefulWidget {
  const _DangerTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_DangerTile> createState() => _DangerTileState();
}

class _DangerTileState extends State<_DangerTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = widget.color;

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.withValues(alpha: isDark ? 0.20 : 0.10),
                  c.withValues(alpha: isDark ? 0.08 : 0.04),
                ],
              ),
              border: Border.all(
                color: c.withValues(alpha: isDark ? 0.45 : 0.30),
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: isDark ? 0.22 : 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: widget.busy
                        ? Padding(
                            padding: const EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: c),
                          )
                        : Icon(widget.icon, color: c, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: c.withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
