import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/name_display.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// MODULE_02 (MEM-006/007) — Admin "Join Requests" approvals screen.
///
/// Lists every pending join request across the organization's groups and lets
/// the admin Approve / Reject (with an optional reason). Additive + self
/// contained: it drives the backend approval endpoints via [GroupRepository].
class GroupJoinRequestsScreen extends StatefulWidget {
  const GroupJoinRequestsScreen({super.key});

  @override
  State<GroupJoinRequestsScreen> createState() =>
      _GroupJoinRequestsScreenState();
}

class _PendingItem {
  const _PendingItem(this.group, this.user);
  final GroupModel group;
  final UserModel user;
}

class _GroupJoinRequestsScreenState extends State<GroupJoinRequestsScreen> {
  final _repo = GroupRepository();

  bool _loading = true;
  String? _error;
  String? _busyId; // '${groupId}:${userId}' currently being acted on
  List<_PendingItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final orgId =
        AuthProviderScope.of(context).currentUser?.organizationId ?? '';
    final groupsRes = await _repo.getOrganisationGroups(organizationId: orgId);
    if (!mounted) return;

    switch (groupsRes) {
      case Err(:final failure):
        setState(() {
          _error = failure.message;
          _loading = false;
        });
        return;
      case Ok(:final value):
        final items = <_PendingItem>[];
        // Only groups that report pending requests need a member fetch.
        final candidates =
            value.data.where((g) => g.isActive && g.pendingCount > 0).toList();
        for (final g in candidates) {
          final reqRes = await _repo.getJoinRequests(groupId: g.id);
          if (reqRes case Ok(:final value)) {
            for (final u in value.data) {
              items.add(_PendingItem(g, u));
            }
          }
        }
        if (!mounted) return;
        setState(() {
          _items = items;
          _loading = false;
        });
    }
  }

  Future<void> _approve(_PendingItem it) async {
    await _act(it, () => _repo.approveJoinRequest(
          groupId: it.group.id,
          userId: it.user.id,
        ), 'Request approved.');
  }

  Future<void> _reject(_PendingItem it) async {
    final reason = await _askReason();
    if (reason == null) return; // cancelled the dialog
    await _act(
      it,
      () => _repo.rejectJoinRequest(
        groupId: it.group.id,
        userId: it.user.id,
        reason: reason.isEmpty ? null : reason,
      ),
      'Request rejected.',
    );
  }

  Future<void> _act(
    _PendingItem it,
    Future<Result<Unit>> Function() action,
    String successLabel,
  ) async {
    final key = '${it.group.id}:${it.user.id}';
    if (_busyId != null) return;
    setState(() => _busyId = key);
    final res = await action();
    if (!mounted) return;
    setState(() => _busyId = null);
    switch (res) {
      case Ok():
        setState(() => _items = _items
            .where((x) => !(x.group.id == it.group.id && x.user.id == it.user.id))
            .toList());
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successLabel)));
      case Err(:final failure):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<String?> _askReason() {
    final ctrl = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject request'),
        content: TextField(
          controller: ctrl,
          maxLength: 300,
          decoration: const InputDecoration(
            hintText: 'Optional reason (shown to the member)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Join Requests', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const AppListSkeleton(rows: 5, rowHeight: 96)
          : _error != null
              ? _info(_error!, AppColors.error, onRetry: _load)
              : _items.isEmpty
                  ? _info('No pending join requests.',
                      Theme.of(context).colorScheme.onSurfaceVariant)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _card(_items[i], isDark),
                      ),
                    ),
    );
  }

  Widget _card(_PendingItem it, bool isDark) {
    final busy = _busyId == '${it.group.id}:${it.user.id}';
    return Container(
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
          Text(
            displayMemberName(it.user.name),
            style:
                AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.groups_rounded,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  it.group.name,
                  style: AppTypography.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                Expanded(
                  child: FilledButton(
                    onPressed: () => _approve(it),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.present,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _reject(it),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.absent,
                      side: BorderSide(
                        color: AppColors.absent.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _info(String msg, Color color, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.how_to_reg_rounded, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
