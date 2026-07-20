import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/realtime_events.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/data/repositories/notice_repository.dart';
import 'package:smart_meal_management/data/services/realtime_service.dart';
import 'package:smart_meal_management/features/notices/screens/notice_feed_screen.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Premium notice-board bell with a live unread badge (Phase B).
///
/// Self-contained: fetches its own unread count, listens for `notice.created.v1`
/// over the realtime channel, and refreshes when the feed is dismissed. Drop it
/// into any AppBar `actions:` list or header row.
class NoticeBell extends StatefulWidget {
  const NoticeBell({
    super.key,
    required this.organizationId,
    required this.groupId,
    required this.isAdmin,
    this.color,
  });

  final String organizationId;
  final String? groupId;
  final bool isAdmin;
  final Color? color;

  @override
  State<NoticeBell> createState() => _NoticeBellState();
}

class _NoticeBellState extends State<NoticeBell> {
  final _repo = NoticeRepository();
  StreamSubscription? _rtSub;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = RealtimeService.instance
        .on(RealtimeEvents.noticeCreated)
        .listen((_) => _load());
  }

  // ISSUE-001: refetch the unread badge when the active group switches —
  // the bell is a long-lived header widget, so the prop can change in place.
  @override
  void didUpdateWidget(covariant NoticeBell old) {
    super.didUpdateWidget(old);
    if (old.groupId != widget.groupId ||
        old.organizationId != widget.organizationId) {
      _load();
    }
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _repo.getUnreadCount(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
    );
    if (!mounted) return;
    if (res case Ok(:final value)) setState(() => _unread = value);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoticeFeedScreen(
          organizationId: widget.organizationId,
          groupId: widget.groupId,
          isAdmin: widget.isAdmin,
        ),
      ),
    );
    await _load(); // unread count may have changed while reading
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.color ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppColors.textPrimaryDark
            : AppColors.textPrimary);
    final badge = _unread > 99 ? '99+' : '$_unread';
    return IconButton(
      tooltip: 'Notices',
      onPressed: _open,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_none_rounded, color: iconColor),
          if (_unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: _unread > 9 ? 4 : 0, vertical: 0),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                alignment: Alignment.center,
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
