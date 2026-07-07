import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/realtime_events.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/notice_repository.dart';
import 'package:smart_meal_management/data/repositories/notification_repository.dart';
import 'package:smart_meal_management/data/services/realtime_service.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/admin_attendance_screen.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/correction_requests_screen.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/vacation_requests_screen.dart';
import 'package:smart_meal_management/features/student/attendance/screens/my_corrections_screen.dart';
import 'package:smart_meal_management/features/student/settings/screens/student_vacation_request_screen.dart';
import 'package:smart_meal_management/features/notices/screens/notice_composer_screen.dart';
import 'package:smart_meal_management/features/admin/groups/screens/group_join_requests_screen.dart';
import 'package:smart_meal_management/features/admin/groups/screens/admin_groups_screen.dart';
import 'package:smart_meal_management/shared/models/notice_model.dart';
import 'package:smart_meal_management/shared/models/notification_diagnostics_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Notice board feed (Phase B) — bell center for students + admins.
///
/// Reading a notice marks it read (server-side, idempotent). Admins get a
/// compose FAB and per-notice delete. Live-updates on `notice.created.v1`.
class NoticeFeedScreen extends StatefulWidget {
  const NoticeFeedScreen({
    super.key,
    required this.organizationId,
    required this.groupId,
    required this.isAdmin,
  });

  final String organizationId;
  final String? groupId;
  final bool isAdmin;

  @override
  State<NoticeFeedScreen> createState() => _NoticeFeedScreenState();
}

class _NoticeFeedScreenState extends State<NoticeFeedScreen> {
  final _repo = NoticeRepository();
  StreamSubscription? _rtSub;

  bool _loading = true;
  String? _error;
  // Issue 7: Notice Board backend may not be deployed yet. A failed load is
  // shown as a friendly "coming soon" state instead of a raw API error page.
  bool _unavailable = false;
  List<NoticeModel> _notices = [];

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = RealtimeService.instance
        .on(RealtimeEvents.noticeCreated)
        .listen((_) => _load());
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    super.dispose();
  }

  /// Per-org, per-group cache key for the notice feed (null group = org-wide).
  String get _cacheKey =>
      'notices:${widget.organizationId}:${widget.groupId ?? 'org'}';

  Future<void> _load() async {
    // Cache-first (SWR): paint the last-known feed instantly, then refresh.
    if (_notices.isEmpty) {
      final cached = await ResponseCacheService.instance.readList(
          _cacheKey, NoticeModel.fromJson, maxAge: const Duration(hours: 12));
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _notices = cached;
          _unavailable = false;
        });
      }
    }
    if (mounted) setState(() => _loading = _notices.isEmpty);
    final res = await _repo.getNotices(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
      includeInactive: false,
      limit: 100,
    );
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _notices = value.data;
          _loading = false;
          _error = null;
          _unavailable = false;
        });
        // Write-through so the next open is instant. Only successful results
        // are cached, so an undeployed backend never poisons the cache.
        ResponseCacheService.instance
            .writeList(_cacheKey, value.data, (n) => n.toJson());
      case Err():
        // Notice Board is future work — degrade gracefully (no error page).
        setState(() {
          _loading = false;
          _error = null;
          _unavailable = true;
        });
    }
  }

  Future<void> _openNotice(NoticeModel n) async {
    // Mark read first (idempotent) so the badge clears whether we deep-link or
    // just show the text — "mark as read after opening" (command_3).
    if (!n.isRead) {
      await _repo.markRead(n.id);
      if (mounted) {
        setState(() {
          final i = _notices.indexWhere((x) => x.id == n.id);
          if (i != -1) _notices[i] = _notices[i].copyWith(isRead: true);
        });
      }
    }
    if (!mounted) return;

    // Notification Center deep-link: an actionable notice opens the related
    // workflow directly instead of a text sheet. The backend audience-scopes
    // each link (admins get review queues; members get their own screens), so
    // whoever holds the notice is always routed to the right place.
    final workflow = _workflowFor(n.linkType);
    if (workflow != null) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => workflow));
      if (mounted) await _load(); // a decision may have changed the queue
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoticeDetailSheet(notice: n, isAdmin: widget.isAdmin),
    );
  }

  /// Maps a notice [linkType] to the screen it should open. Admin request
  /// queues and member decision screens are both covered; null = plain notice.
  Widget? _workflowFor(String? linkType) {
    switch (linkType) {
      case 'vacationRequests': // admin: pending vacation approvals
        return const VacationRequestsScreen();
      case 'correctionRequests': // admin: pending correction approvals
        return const CorrectionRequestsScreen();
      case 'guestRequests': // admin: hosted-guest review lives on attendance
        return const AdminAttendanceScreen();
      case 'myVacations': // member: their vacation requests + decision
        return const StudentVacationRequestScreen();
      case 'myCorrections': // member: their correction requests + decision
        return const MyCorrectionsScreen();
      // Module 02 (MEM-006/007): admin join-request approvals.
      case 'groupJoinRequests':
        return const GroupJoinRequestsScreen();
      // Module 02 (NTF-004): group-full alert opens group management.
      case 'groupMembers':
        return const AdminGroupsScreen();
      // 'myGroups' (member lifecycle decisions) falls through to the detail
      // sheet — the notice text is the actionable content.
      default:
        return null;
    }
  }

  /// Swipe-only mark-read (no navigation). A decision notice never disappears —
  /// swiping just clears its unread dot.
  Future<void> _markReadOnly(NoticeModel n) async {
    if (n.isRead) return;
    await _repo.markRead(n.id);
    if (!mounted) return;
    setState(() {
      final i = _notices.indexWhere((x) => x.id == n.id);
      if (i != -1) _notices[i] = _notices[i].copyWith(isRead: true);
    });
  }

  /// Recency bucket for category grouping (Today / Yesterday / This week / …).
  String _bucketOf(DateTime t) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    if (d <= 0) return 'Today';
    if (d == 1) return 'Yesterday';
    if (d < 7) return 'This week';
    return 'Earlier';
  }

  /// Premium grouped inbox: notices bucketed by recency with day headers, each
  /// unread card swipe-to-mark-read. Notices arrive pinned-desc / newest-first.
  Widget _buildFeed() {
    final items = <(String?, NoticeModel?)>[];
    String? last;
    for (final n in _notices) {
      final b = _bucketOf(n.publishedAt);
      if (b != last) {
        items.add((b, null));
        last = b;
      }
      items.add((null, n));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final (header, notice) = items[i];
        if (header != null) return _DayHeader(label: header);
        final n = notice!;
        final card = Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _NoticeCard(
            notice: n,
            isAdmin: widget.isAdmin,
            onTap: () => _openNotice(n),
            onDelete: () => _delete(n),
          ),
        );
        // NTF-006: members swipe a notice away to remove it from their OWN bell
        // (per-user dismissal). Admins keep the swipe-to-mark-read behaviour so
        // their management gestures are unchanged.
        if (!widget.isAdmin) {
          return Dismissible(
            key: ValueKey('dis_${n.id}'),
            direction: DismissDirection.endToStart,
            background: const _SwipeDismissBackground(),
            onDismissed: (_) => _dismiss(n),
            child: card,
          );
        }
        if (n.isRead) return card;
        // Swipe left to mark read without opening (confirmDismiss returns false
        // so the row snaps back, now read, instead of being removed).
        return Dismissible(
          key: ValueKey('sw_${n.id}'),
          direction: DismissDirection.endToStart,
          background: const _SwipeMarkReadBackground(),
          confirmDismiss: (_) async {
            await _markReadOnly(n);
            return false;
          },
          child: card,
        );
      },
    );
  }

  Future<void> _markAllRead() async {
    await _repo.markAllRead(groupId: widget.groupId);
    if (!mounted) return;
    setState(() {
      _notices = _notices.map((n) => n.copyWith(isRead: true)).toList();
    });
  }

  /// NTF-006: remove ONE notice from THIS member's bell (per-user hide). The
  /// shared notice is untouched for everyone else.
  Future<void> _dismiss(NoticeModel n) async {
    setState(() => _notices.removeWhere((x) => x.id == n.id));
    await _repo.dismissNotice(n.id);
  }

  /// NTF-006: "Delete All" — clear every notice from THIS member's bell.
  Future<void> _dismissAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'This removes every notification from your bell. It does not affect '
          'other members.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear all')),
        ],
      ),
    );
    if (ok != true) return;
    final snapshot = _notices;
    setState(() => _notices = []);
    final res = await _repo.dismissAll(groupId: widget.groupId);
    if (!mounted) return;
    if (res case Err(:final failure)) {
      // Restore on failure so nothing is silently lost.
      setState(() => _notices = snapshot);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _compose() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NoticeComposerScreen(
          organizationId: widget.organizationId,
          groupId: widget.groupId,
        ),
      ),
    );
    if (created == true) await _load();
  }

  /// FR-NOTX-018 (ISSUE-16): admin-visible delivery diagnostics — makes
  /// "push is on but nothing arrives" observable (channel state, registered
  /// devices, last-send outcome). The in-app board itself is always reliable.
  Future<void> _showDeliveryStatus() async {
    final res = await NotificationRepository().getDeliveryDiagnostics();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _DeliveryStatusSheet(diagnostics: value),
        );
      case Err(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load delivery status: ${failure.message}')),
        );
    }
  }

  Future<void> _delete(NoticeModel n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete notice?'),
        content: Text('"${n.title}" will be removed for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteNotice(n.id);
    if (!mounted) return;
    setState(() => _notices.removeWhere((x) => x.id == n.id));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasUnread = _notices.any((n) => !n.isRead);
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Notices', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read', style: AppTypography.labelMedium),
            ),
          // NTF-006: clear all notifications from this user's own bell.
          if (_notices.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.clear_all_rounded),
              onPressed: _dismissAll,
            ),
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Delivery status',
              icon: const Icon(Icons.troubleshoot_rounded),
              onPressed: _showDeliveryStatus,
            ),
        ],
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _compose,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.campaign_rounded, color: Colors.white),
              label: const Text('Post notice',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const AppListSkeleton(rows: 4, rowHeight: 110)
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _notices.isEmpty
                    ? _EmptyState(unavailable: _unavailable)
                    : _buildFeed(),
      ),
    );
  }
}

// ── Priority helpers ─────────────────────────────────────────────────────────

Color _priorityColor(String priority) {
  switch (priority) {
    case 'urgent':
      return AppColors.error;
    case 'high':
      return AppColors.warning;
    case 'low':
      return AppColors.textTertiary;
    default:
      // Issue 2: Normal = blue (spec), consistent with the composer chip.
      return AppColors.info;
  }
}

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

/// Admin review queues say "Review"; member decision screens say "View".
bool _isReviewLink(String linkType) =>
    linkType == 'vacationRequests' ||
    linkType == 'correctionRequests' ||
    linkType == 'guestRequests' ||
    // Module 02 (MEM-006/007): a join request is an admin review action too.
    linkType == 'groupJoinRequests';

// ── Day section header (category grouping) ───────────────────────────────────

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 0, 8),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── Swipe-to-mark-read background ────────────────────────────────────────────

class _SwipeMarkReadBackground extends StatelessWidget {
  const _SwipeMarkReadBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.present.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.done_all_rounded,
              size: 18, color: AppColors.present),
          const SizedBox(width: 6),
          Text('Mark read',
              style: AppTypography.labelMedium.copyWith(
                  color: AppColors.present, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// NTF-006: swipe background for a member dismissing a notice from their bell.
class _SwipeDismissBackground extends StatelessWidget {
  const _SwipeDismissBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delete_sweep_rounded,
              size: 18, color: AppColors.error),
          const SizedBox(width: 6),
          Text('Remove',
              style: AppTypography.labelMedium.copyWith(
                  color: AppColors.error, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Notice card ──────────────────────────────────────────────────────────────

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.notice,
    required this.isAdmin,
    required this.onTap,
    required this.onDelete,
  });

  final NoticeModel notice;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _priorityColor(notice.priority);
    // Theme-adaptive secondary/tertiary text so notices stay legible & premium
    // in BOTH light and dark — raw AppColors.textSecondary/tertiary are
    // light-theme-only tokens that wash out on dark surfaces.
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryText = colorScheme.onSurfaceVariant;
    final tertiaryText = colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: notice.isRead
                ? (isDark ? AppColors.borderDark : AppColors.border)
                    .withValues(alpha: 0.4)
                : accent.withValues(alpha: 0.5),
            width: notice.isRead ? 1 : 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!notice.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                if (notice.pinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.push_pin_rounded, size: 14),
                  ),
                Expanded(
                  child: Text(
                    notice.title,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight:
                          notice.isRead ? FontWeight.w600 : FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _PriorityChip(priority: notice.priority, color: accent),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              notice.body,
              style: AppTypography.bodySmall.copyWith(color: secondaryText),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(notice.isOrgWide
                    ? Icons.business_rounded
                    : Icons.groups_rounded,
                    size: 13, color: tertiaryText),
                const SizedBox(width: 4),
                Text(
                  notice.isOrgWide ? 'Organisation' : 'Group',
                  style:
                      AppTypography.labelSmall.copyWith(color: tertiaryText),
                ),
                const SizedBox(width: 10),
                Text(_relativeTime(notice.publishedAt),
                    style: AppTypography.labelSmall
                        .copyWith(color: tertiaryText)),
                if (notice.linkType != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_isReviewLink(notice.linkType!) ? 'Review' : 'View',
                            style: AppTypography.labelSmall.copyWith(
                                color: accent, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_forward_rounded,
                            size: 12, color: accent),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (isAdmin) ...[
                  Text('${notice.readCount} read',
                      style: AppTypography.labelSmall
                          .copyWith(color: tertiaryText)),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline_rounded, size: 16),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority, required this.color});
  final String priority;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        priority[0].toUpperCase() + priority.substring(1),
        style: AppTypography.labelSmall
            .copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── Detail sheet ─────────────────────────────────────────────────────────────

class _NoticeDetailSheet extends StatelessWidget {
  const _NoticeDetailSheet({required this.notice, required this.isAdmin});
  final NoticeModel notice;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _priorityColor(notice.priority);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ListView(
          controller: scrollCtrl,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (notice.pinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.push_pin_rounded, size: 16),
                  ),
                Expanded(
                  child: Text(notice.title,
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.w800)),
                ),
                _PriorityChip(priority: notice.priority, color: accent),
              ],
            ),
            const SizedBox(height: 6),
            Text(_relativeTime(notice.publishedAt),
                style: AppTypography.labelSmall.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7))),
            const SizedBox(height: 16),
            Text(notice.body,
                style: AppTypography.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ── Empty + error ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.unavailable = false});

  /// True when the backend notices service isn't reachable yet — shows a
  /// "coming soon" message instead of "No notices yet".
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(
            unavailable
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(
          child: Text(unavailable ? 'Notifications coming soon' : 'No notices yet',
              style: AppTypography.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        if (unavailable) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Center(
              child: Text(
                'Announcements will appear here in a future update.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline_rounded, size: 44, color: AppColors.error),
        const SizedBox(height: 12),
        Center(
          child: Text(message,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}

// ── Delivery status sheet (FR-NOTX-018 / ISSUE-16) ───────────────────────────

class _DeliveryStatusSheet extends StatelessWidget {
  const _DeliveryStatusSheet({required this.diagnostics});
  final NotificationDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final d = diagnostics;
    final last = d.lastSend;
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
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Notification delivery', style: AppTypography.titleMedium),
          const SizedBox(height: 4),
          Text(
            'In-app notices always reach everyone. Push alerts also need a '
            'registered device.',
            style:
                AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          _statusRow(
            icon: d.pushConfigured
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
            color: d.pushConfigured ? AppColors.present : AppColors.warning,
            label: 'Push channel',
            value: d.pushConfigured ? 'Active' : 'Not configured (in-app only)',
          ),
          _statusRow(
            icon: Icons.phone_android_rounded,
            color: AppColors.info,
            label: 'Registered devices',
            value: '${d.registeredDevices} of ${d.totalMembers} members',
          ),
          if (d.membersWithoutDevice > 0)
            _statusRow(
              icon: Icons.phonelink_erase_rounded,
              color: AppColors.textTertiary,
              label: 'In-app only',
              value:
                  '${d.membersWithoutDevice} member(s) have no push device yet',
            ),
          if (last != null)
            _statusRow(
              icon: last.failed == 0
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: last.failed == 0 ? AppColors.present : AppColors.warning,
              label: 'Last send',
              value:
                  '"${last.title}" — ${last.successful}/${last.total} delivered'
                  '${last.at != null ? ' · ${_relativeTime(last.at!.toLocal())}' : ''}',
            )
          else
            _statusRow(
              icon: Icons.schedule_rounded,
              color: AppColors.textTertiary,
              label: 'Last send',
              value: 'No push sent in the last 7 days',
            ),
        ],
      ),
    );
  }

  Widget _statusRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.labelMedium),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
