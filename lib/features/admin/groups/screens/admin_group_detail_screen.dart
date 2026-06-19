import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/qr_payload_parser.dart';
import 'package:smart_meal_management/features/admin/groups/providers/admin_group_provider.dart';
import 'package:smart_meal_management/features/admin/groups/widgets/group_member_tile.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/shared/widgets/app_glass_card.dart';
import 'package:smart_meal_management/shared/widgets/app_primary_button.dart';
import 'package:smart_meal_management/shared/widgets/app_status_chip.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

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
          ? const Center(child: CircularProgressIndicator())
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: true,
      forceElevated: forceElevated,
      backgroundColor: colorScheme.surface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
                  Row(
                    children: [
                      AppStatusChip.label(
                        label: group.type.label,
                        color: AppColors.primary,
                        compact: true,
                      ),
                      const SizedBox(width: 8),
                      AppStatusChip.label(
                        label: '${group.memberCount} members',
                        color: AppColors.secondary,
                        compact: true,
                      ),
                      if (group.joinCode != null) ...[
                        const SizedBox(width: 8),
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

class _QrBottomSheet extends StatelessWidget {
  const _QrBottomSheet({
    required this.group,
    required this.provider,
    required this.organizationId,
  });

  final GroupModel group;
  final AdminGroupProvider provider;
  final String organizationId;

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
          Container(
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
                  label: 'Share',
                  icon: Icons.share_rounded,
                  onPressed: () {
                    Share.share(
                      'Join "${group.name}" on MealAttend!\n\n'
                      'Use code: $code\n\n'
                      'Open the app → Scan QR or enter code to join.',
                      subject: 'Join ${group.name}',
                    );
                  },
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
      return const Center(child: CircularProgressIndicator());
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
    final meals = provider.selectedGroupMeals;

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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
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
                    'Go to Meal Config to add meals for this group.',
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
          label: 'Manage Meal Configuration',
          icon: Icons.settings_rounded,
          onPressed: () => context.push(RouteNames.adminMealConfig),
        ),
        const SizedBox(height: 8),
        AppPrimaryButton.outlined(
          label: 'Weekly Schedule',
          icon: Icons.calendar_month_rounded,
          onPressed: () => context.push(RouteNames.adminMealSchedule),
        ),
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
    final window =
        '${meal.attendanceWindow.openTime} – ${meal.attendanceWindow.closeTime}';

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
  bool _togglingPrefs = false;
  bool _updatingPrefTypes = false;
  bool _archiving = false;

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

  Future<void> _togglePreferences(bool newValue) async {
    setState(() => _togglingPrefs = true);
    final newConfig =
        widget.group.mealConfig.copyWith(preferencesEnabled: newValue);
    final ok = await widget.provider.updateGroup(
      organizationId: widget.organizationId,
      groupId: widget.group.id,
      mealConfig: newConfig,
    );
    if (!mounted) return;
    setState(() => _togglingPrefs = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (newValue
                ? 'Meal preferences enabled'
                : 'Meal preferences disabled')
            : 'Failed to update preference settings'),
      ),
    );
  }

  Future<void> _updateEnabledPreferences(
      MealPreferenceOption option, bool selected) async {
    final current =
        List<MealPreferenceOption>.from(widget.group.mealConfig.enabledPreferences);
    if (selected) {
      if (!current.contains(option)) current.add(option);
    } else {
      current.remove(option);
    }
    setState(() => _updatingPrefTypes = true);
    final newConfig =
        widget.group.mealConfig.copyWith(enabledPreferences: current);
    final ok = await widget.provider.updateGroup(
      organizationId: widget.organizationId,
      groupId: widget.group.id,
      mealConfig: newConfig,
    );
    if (!mounted) return;
    setState(() => _updatingPrefTypes = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.provider.error ?? 'Failed to update preference types',
          ),
        ),
      );
    }
  }

  Future<void> _confirmArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Group?'),
        content: Text(
          'Archiving "${widget.group.name}" will remove all member access. '
          'This action cannot be undone.',
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

    setState(() => _archiving = true);
    final ok = await widget.provider.archiveGroup(
      widget.group.id,
      organizationId: widget.organizationId,
    );
    if (!mounted) return;
    setState(() => _archiving = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group archived')),
      );
      // Return to groups list
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to archive group')),
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
          // Meal preferences toggle
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Meal Preferences',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                group.mealConfig.preferencesEnabled
                    ? 'Members select Veg / Chicken / Fish etc. when marking attendance.'
                    : 'Disabled — members mark attendance without preference selection.',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              value: group.mealConfig.preferencesEnabled,
              onChanged: _togglingPrefs ? null : _togglePreferences,
              secondary: _togglingPrefs
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.tune_rounded,
                      color: AppColors.primary, size: 20),
            ),
          ),
          // Enabled preference types (shown only when preferences are enabled)
          if (group.mealConfig.preferencesEnabled) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Active Preference Types',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (_updatingPrefTypes)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select which food types members can choose from.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: MealPreferenceOption.values.map((option) {
                        final isSelected = group.mealConfig.enabledPreferences
                            .contains(option);
                        return FilterChip(
                          label: Text(_prefLabel(option)),
                          avatar: Text(
                            _prefEmoji(option),
                            style: const TextStyle(fontSize: 14),
                          ),
                          selected: isSelected,
                          onSelected: _updatingPrefTypes
                              ? null
                              : (val) =>
                                  _updateEnabledPreferences(option, val),
                          showCheckmark: false,
                          selectedColor:
                              colorScheme.primaryContainer,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],

        const SizedBox(height: 16),

        // ── Danger zone ───────────────────────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
          child: ListTile(
            leading: _archiving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.error,
                    ),
                  )
                : Icon(Icons.archive_outlined, color: colorScheme.error),
            title: Text('Archive Group',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.error)),
            subtitle: const Text(
                'Members will lose access. This cannot be undone.'),
            onTap: _archiving ? null : _confirmArchive,
          ),
        ),
      ],
    );
  }

  String _prefLabel(MealPreferenceOption option) => switch (option) {
        MealPreferenceOption.veg => 'Veg',
        MealPreferenceOption.chicken => 'Chicken',
        MealPreferenceOption.fish => 'Fish',
        MealPreferenceOption.mutton => 'Mutton',
        MealPreferenceOption.egg => 'Egg',
        MealPreferenceOption.jain => 'Jain',
      };

  String _prefEmoji(MealPreferenceOption option) => switch (option) {
        MealPreferenceOption.veg => '🥦',
        MealPreferenceOption.chicken => '🍗',
        MealPreferenceOption.fish => '🐟',
        MealPreferenceOption.mutton => '🍖',
        MealPreferenceOption.egg => '🥚',
        MealPreferenceOption.jain => '🌿',
      };
}
