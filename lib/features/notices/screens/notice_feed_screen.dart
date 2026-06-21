import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/realtime_events.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/notice_repository.dart';
import 'package:smart_meal_management/data/services/realtime_service.dart';
import 'package:smart_meal_management/features/notices/screens/notice_composer_screen.dart';
import 'package:smart_meal_management/shared/models/notice_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

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

  Future<void> _load() async {
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
        });
      case Err(:final failure):
        setState(() {
          _loading = false;
          _error = failure.message;
        });
    }
  }

  Future<void> _openNotice(NoticeModel n) async {
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoticeDetailSheet(notice: n, isAdmin: widget.isAdmin),
    );
  }

  Future<void> _markAllRead() async {
    await _repo.markAllRead(groupId: widget.groupId);
    if (!mounted) return;
    setState(() {
      _notices = _notices.map((n) => n.copyWith(isRead: true)).toList();
    });
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
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : _notices.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: _notices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) => _NoticeCard(
                          notice: _notices[i],
                          isAdmin: widget.isAdmin,
                          onTap: () => _openNotice(_notices[i]),
                          onDelete: () => _delete(_notices[i]),
                        ),
                      ),
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
      return AppColors.primary;
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
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(notice.isOrgWide
                    ? Icons.business_rounded
                    : Icons.groups_rounded,
                    size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  notice.isOrgWide ? 'Organisation' : 'Group',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
                const SizedBox(width: 10),
                Text(_relativeTime(notice.publishedAt),
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textTertiary)),
                const Spacer(),
                if (isAdmin) ...[
                  Text('${notice.readCount} read',
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.textTertiary)),
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
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: 16),
            Text(notice.body,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ── Empty + error ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.notifications_off_rounded,
            size: 48, color: AppColors.textTertiary),
        const SizedBox(height: 12),
        Center(
          child: Text('No notices yet',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textTertiary)),
        ),
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
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}
