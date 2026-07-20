import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/name_display.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';
import 'package:smart_meal_management/shared/widgets/user_avatar.dart';

/// MODULE_02 (MEM-006/007) — Admin "Join Requests" approvals screen.
///
/// Two modes, one premium UI:
///  • **Group-scoped** ([groupId] provided) — the primary, group-specific entry
///    reached from a group's detail/settings. Loads that ONE group's pending
///    requests in a single call (ultra-fast, no org-wide fan-out).
///  • **Organization-wide** ([groupId] null) — aggregate view reached from the
///    Groups app-bar; lists pending requests across every active group.
///
/// Additive + self contained: drives the backend approval endpoints via
/// [GroupRepository]. Premium, theme-adaptive cards with Approve / Reject.
class GroupJoinRequestsScreen extends StatefulWidget {
  const GroupJoinRequestsScreen({super.key, this.groupId, this.groupName});

  /// When set, the screen is scoped to this single group (group-specific UI).
  final String? groupId;
  final String? groupName;

  @override
  State<GroupJoinRequestsScreen> createState() =>
      _GroupJoinRequestsScreenState();
}

class _PendingItem {
  const _PendingItem(this.groupId, this.groupName, this.user);
  final String groupId;
  final String groupName;
  final UserModel user;
}

class _GroupJoinRequestsScreenState extends State<GroupJoinRequestsScreen> {
  final _repo = GroupRepository();

  bool _loading = true;
  String? _error;
  String? _busyId; // '${groupId}:${userId}' currently being acted on
  List<_PendingItem> _items = [];

  bool get _scoped => widget.groupId != null;

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

    // Group-scoped: a single request for this group's pending members — the
    // fast path (no organization fan-out).
    if (_scoped) {
      final reqRes = await _repo.getJoinRequests(groupId: widget.groupId!);
      if (!mounted) return;
      switch (reqRes) {
        case Err(:final failure):
          setState(() {
            _error = failure.message;
            _loading = false;
          });
        case Ok(:final value):
          setState(() {
            _items = value.data
                .map((u) => _PendingItem(
                      widget.groupId!,
                      widget.groupName ?? 'This group',
                      u,
                    ))
                .toList();
            _loading = false;
          });
      }
      return;
    }

    // Organization-wide: only groups that report pending requests need a fetch.
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
        final candidates =
            value.data.where((g) => g.isActive && g.pendingCount > 0).toList();
        // All per-group fetches ride ONE parallel wave (HTTP/2-multiplexed)
        // instead of a sequential round-trip per group.
        final results = await Future.wait(
            candidates.map((g) => _repo.getJoinRequests(groupId: g.id)));
        for (var i = 0; i < candidates.length; i++) {
          final g = candidates[i];
          if (results[i] case Ok(:final value)) {
            for (final u in value.data) {
              items.add(_PendingItem(g.id, g.name, u));
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
    await _act(
      it,
      () => _repo.approveJoinRequest(groupId: it.groupId, userId: it.user.id),
      'Request approved.',
    );
  }

  Future<void> _reject(_PendingItem it) async {
    final reason = await _askReason();
    if (reason == null) return; // cancelled the dialog
    await _act(
      it,
      () => _repo.rejectJoinRequest(
        groupId: it.groupId,
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
    final key = '${it.groupId}:${it.user.id}';
    if (_busyId != null) return;
    setState(() => _busyId = key);
    final res = await action();
    if (!mounted) return;
    setState(() => _busyId = null);
    switch (res) {
      case Ok():
        setState(() => _items = _items
            .where((x) => !(x.groupId == it.groupId && x.user.id == it.user.id))
            .toList());
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(successLabel),
            behavior: SnackBarBehavior.floating,
          ));
      case Err(:final failure):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(failure.message),
            behavior: SnackBarBehavior.floating,
          ));
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
    final title = _scoped ? 'Join Requests' : 'Join Requests';
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTypography.titleLarge),
            if (_scoped && widget.groupName != null)
              Text(
                widget.groupName!,
                style: AppTypography.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
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
          ? const AppListSkeleton(rows: 5, rowHeight: 108)
          : _error != null
              ? _info(_error!, AppColors.error, onRetry: _load)
              : _items.isEmpty
                  ? _info(
                      _scoped
                          ? 'No one is waiting to join this group.'
                          : 'No pending join requests.',
                      Theme.of(context).colorScheme.onSurfaceVariant)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: _items.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => i == 0
                            ? _summary()
                            : _card(_items[i - 1], isDark),
                      ),
                    ),
    );
  }

  /// Premium count summary header (e.g. "3 pending requests").
  Widget _summary() {
    final n = _items.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: [
          AppColors.primary.withValues(alpha: 0.14),
          AppColors.primary.withValues(alpha: 0.05),
        ]),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.how_to_reg_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$n pending ${n == 1 ? 'request' : 'requests'}'
              '${_scoped ? '' : ' across your groups'}',
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(_PendingItem it, bool isDark) {
    final busy = _busyId == '${it.groupId}:${it.user.id}';
    final colorScheme = Theme.of(context).colorScheme;
    final name = displayMemberName(it.user.name);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
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
              // ISSUE-003: real requester photo (cached thumbnail) with the
              // same initials fallback the badge had before.
              UserAvatar(
                name: name,
                avatarUrl: it.user.avatarUrl,
                radius: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.titleSmall
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // In scoped mode the group is in the app-bar; show intent.
                      _scoped ? 'Wants to join' : 'Wants to join ${it.groupName}',
                      style: AppTypography.bodySmall
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (busy)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 9),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _approve(it),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.present,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reject(it),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.absent,
                      side: BorderSide(
                        color: AppColors.absent.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ISSUE-003: initials rendering now lives inside the shared [UserAvatar].

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
