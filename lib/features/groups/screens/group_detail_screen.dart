import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/features/groups/providers/group_provider.dart';
import 'package:smart_meal_management/features/groups/screens/group_join_screen.dart';
import 'package:smart_meal_management/features/groups/widgets/qr_display_card.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Group detail screen — header, stats, meal config summary, leave action.
///
/// Accepts either [groupId] + [organizationId] (for deep-link navigation) or
/// a pre-loaded [group] (for fast transitions from a list).
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.organizationId,
    this.group,
  });

  final String groupId;
  final String organizationId;

  /// Optional pre-loaded group — skips the initial fetch if provided.
  final GroupModel? group;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late final GroupProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GroupProvider();
    _provider.addListener(_rebuild);

    if (widget.group != null) {
      // Fast path: pre-loaded group
      // ignore: invalid_use_of_protected_member
      // We expose group via selectedGroup after assigning here.
      _loadFromPreloaded();
    } else {
      _load();
    }
  }

  void _loadFromPreloaded() {
    // No async needed — just store in provider via loadGroup fallback.
    _load();
  }

  void _load() {
    _provider.loadGroup(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
    );
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    super.dispose();
  }

  GroupModel? get _group => widget.group ?? _provider.selectedGroup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_group?.name ?? 'Group'),
        centerTitle: false,
        actions: [
          if (_group != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_provider.isLoading && _group == null) {
      return const AppDetailSkeleton();
    }

    if (_provider.error != null && _group == null) {
      return AppEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load group',
        subtitle: _provider.error,
        actionLabel: 'Retry',
        onActionTap: _load,
      );
    }

    final group = _group;
    if (group == null) {
      return const AppEmptyState(
        icon: Icons.group_off_rounded,
        title: 'Group not found',
        subtitle: 'This group may have been removed.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupHeader(group: group),
          const SizedBox(height: 20),
          _StatsRow(group: group),
          const SizedBox(height: 20),
          _AboutCard(group: group),
          const SizedBox(height: 20),
          _MealConfigCard(config: group.mealConfig),
          const SizedBox(height: 20),
          if (group.joinCode != null) ...[
            QrDisplayCard(
              groupId: group.id,
              joinCode: group.joinCode!,
              groupName: group.name,
            ),
            const SizedBox(height: 20),
          ],
          // ISSUE 3: any member can join additional groups from here.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GroupJoinScreen(),
                ),
              ),
              icon: const Icon(Icons.group_add_rounded, size: 18),
              label: const Text('Join another group'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _LeaveButton(
            onLeave: () => _confirmLeave(context, group),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context, GroupModel group) async {
    // Capture context-dependent objects BEFORE any await.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final userId = AuthProviderScope.of(context).currentUser?.id ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: Text(
          'You will lose access to ${group.name}\'s meal schedule and attendance.',
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
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await _provider.leaveGroup(
      organizationId: group.organizationId,
      groupId: group.id,
      userId: userId,
    );

    if (!mounted) return;

    if (ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Left ${group.name}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      navigator.pop();
    } else {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Failed to leave group. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }
}

// ── Group header ───────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});
  final GroupModel group;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _groupIcon(group.type),
              size: 28,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                if (group.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    group.description!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    group.type.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _groupIcon(GroupType type) => switch (type) {
        GroupType.hostel => Icons.home_rounded,
        GroupType.mess => Icons.restaurant_rounded,
        GroupType.cafeteria => Icons.local_cafe_rounded,
        GroupType.pg => Icons.apartment_rounded,
        GroupType.coachingInstitute => Icons.school_rounded,
        GroupType.office => Icons.business_rounded,
        GroupType.factory_ => Icons.factory_rounded,
        GroupType.community => Icons.people_rounded,
        GroupType.event => Icons.event_rounded,
        GroupType.other => Icons.group_rounded,
      };
}

// ── Stats row ──────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.group});
  final GroupModel group;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.people_rounded,
            label: 'Members',
            value: '${group.memberCount}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.restaurant_menu_rounded,
            label: 'Meals',
            value: group.mealConfig.mealsEnabled ? 'On' : 'Off',
            valueColor: group.mealConfig.mealsEnabled
                ? AppColors.present
                : AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: group.isActive
                ? Icons.check_circle_rounded
                : Icons.pause_circle_rounded,
            label: 'Status',
            value: group.isActive ? 'Active' : 'Archived',
            valueColor: group.isActive ? AppColors.present : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── About card (ISSUE 2: read-only group information for members) ───────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.group});
  final GroupModel group;

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final rows = <Widget>[
      if ((group.organizationName ?? '').isNotEmpty)
        _InfoRow(
          icon: Icons.corporate_fare_rounded,
          label: 'Organization',
          value: group.organizationName!,
        ),
      if ((group.adminName ?? '').isNotEmpty)
        _InfoRow(
          icon: Icons.admin_panel_settings_rounded,
          label: 'Managed by',
          value: group.adminName!,
        ),
      if (group.functionalRole != null)
        _InfoRow(
          icon: Icons.badge_rounded,
          label: 'Your role',
          value: group.functionalRole!.label,
        ),
      if (group.createdAt != null)
        _InfoRow(
          icon: Icons.event_available_rounded,
          label: 'Created',
          value: _formatDate(group.createdAt!),
        ),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About this group',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++) ...[
            const SizedBox(height: 10),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        SizedBox(
          width: 96,
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── Meal config card ───────────────────────────────────────────────────────────

class _MealConfigCard extends StatelessWidget {
  const _MealConfigCard({required this.config});
  final GroupMealConfig config;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Meal Settings',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ConfigRow(
            label: 'Meals enabled',
            enabled: config.mealsEnabled,
          ),
          const SizedBox(height: 8),
          _ConfigRow(
            label: 'Meal preferences',
            enabled: config.preferencesEnabled,
          ),
          if (config.preferencesEnabled &&
              config.enabledPreferences.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: config.enabledPreferences.map((pref) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${pref.emoji} ${pref.label}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({required this.label, required this.enabled});
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          enabled ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
          size: 16,
          color: enabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Spacer(),
        Text(
          enabled ? 'On' : 'Off',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: enabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Leave button ───────────────────────────────────────────────────────────────

class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onLeave});
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onLeave,
        icon: const Icon(Icons.exit_to_app_rounded, size: 18),
        label: const Text('Leave Group'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.error,
          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
