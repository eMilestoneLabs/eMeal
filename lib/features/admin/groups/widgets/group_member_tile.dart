import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/features/auth/widgets/email_verification_badge.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/widgets/app_status_chip.dart';
import 'package:smart_meal_management/shared/widgets/cached_photo.dart';

/// Single member row in admin group detail Members tab.
///
/// Shows name, role chip, join date, attendance participation indicator,
/// vacation mode badge, and a promote / remove / block action menu.
class GroupMemberTile extends StatelessWidget {
  const GroupMemberTile({
    super.key,
    required this.member,
    this.isCurrentUser = false,
    this.isBlocked = false,
    this.joinedAt,
    this.attendanceRate,
    this.onPromote,
    this.onRemove,
    this.onBlock,
    this.onUnblock,
  });

  final UserModel member;
  final bool isCurrentUser;

  /// True when this member has been blocked by the admin.
  final bool isBlocked;

  /// When the member joined this group. Displayed as "Joined MMM yyyy".
  final DateTime? joinedAt;

  /// Attendance participation rate 0.0–1.0. Shown as a compact percentage badge.
  /// Null = not calculated yet (no badge shown).
  final double? attendanceRate;

  final VoidCallback? onPromote;
  final VoidCallback? onRemove;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAdmin = member.role.isAdmin;

    // Compute participation color
    Color rateColor(double rate) {
      if (rate >= 0.8) return AppColors.present;
      if (rate >= 0.5) return AppColors.warning;
      return AppColors.absent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          // ── Avatar (member photo if set, else initials) ─────────────────
          Builder(builder: (context) {
            final initials = Center(
              child: Text(
                member.initials,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isAdmin
                      ? AppColors.primary
                      : colorScheme.onPrimaryContainer,
                ),
              ),
            );
            final url = member.avatarUrl;
            return Container(
              width: 40,
              height: 40,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAdmin
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : colorScheme.primaryContainer,
              ),
              // Avatars are stored URLs (MinIO); fall back to initials on
              // empty/non-URL values or load errors. Single source of truth —
              // updates everywhere once the member's avatarUrl changes.
              child: (url != null && url.startsWith('http'))
                  ? CachedPhoto(
                      url: url,
                      width: 40,
                      height: 40,
                      cacheWidth: 80,
                      useThumbnail: true,
                      placeholder: initials,
                    )
                  : initials,
            );
          }),
          const SizedBox(width: 12),

          // ── Name + badges ──────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // SRS AUTH-036/040: read-only verified/unverified indicator
                    // next to every member's name (admin can't verify for them).
                    const SizedBox(width: 6),
                    EmailVerificationBadge(
                      verified: member.emailVerified,
                      interactive: false,
                      iconOnly: true,
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    // #2: prefer the member's per-group display role (chosen on
                    // join) over the global account role; fall back when unset.
                    AppStatusChip.label(
                      label: (member.groupFunctionalRole ?? member.role)
                          .displayName,
                      color: isAdmin ? AppColors.primary : AppColors.secondary,
                      compact: true,
                    ),
                    if (isBlocked)
                      const AppStatusChip.label(
                        label: 'Blocked',
                        color: AppColors.absent,
                        compact: true,
                      ),
                    if (member.isVacationMode)
                      const AppStatusChip.label(
                        label: 'On Vacation',
                        color: AppColors.vacation,
                        compact: true,
                      ),
                    if (attendanceRate != null)
                      AppStatusChip.label(
                        label:
                            '${(attendanceRate! * 100).round()}% attendance',
                        color: rateColor(attendanceRate!),
                        compact: true,
                      ),
                  ],
                ),
                // Join date
                if (joinedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Joined ${_fmtJoinDate(joinedAt!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Action menu ────────────────────────────────────────────────
          // ISSUE-002(iv) follow-up: the guard now counts only the actions this
          // menu can actually RENDER. It used to include [onPromote], which was
          // safe while "Make Admin" was an item — with that item gone, a caller
          // supplying onPromote alone would open a PopupMenuButton whose
          // itemBuilder returns an empty list (a debug assertion, and an empty
          // sheet in release). No current call site can hit that (onRemove is
          // always non-null for a non-self member), but the guard should not
          // depend on that coincidence.
          if (!isCurrentUser &&
              ((!isBlocked && onBlock != null) ||
                  (isBlocked && onUnblock != null) ||
                  onRemove != null))
            PopupMenuButton<_MemberAction>(
              icon: Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              itemBuilder: (_) => [
                // Live-Test-14 ISSUE-002(iv) (user-confirmed rule): the "Make
                // Admin" action is REMOVED — promoting a member to admin from
                // this menu is not a workflow the product offers. The
                // [onPromote] callback and _MemberAction.promote branch are
                // intentionally KEPT (additive-only discipline: the promote API
                // and its call sites stay intact and unbroken), but no UI can
                // reach them, so no admin can be created here. Re-adding the
                // entry is a one-line change if the rule is ever reversed.
                if (!isBlocked && onBlock != null)
                  PopupMenuItem(
                    value: _MemberAction.block,
                    child: Text(
                      'Block Member',
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                if (isBlocked && onUnblock != null)
                  const PopupMenuItem(
                    value: _MemberAction.unblock,
                    child: Text('Unblock Member'),
                  ),
                if (onRemove != null)
                  const PopupMenuItem(
                    value: _MemberAction.remove,
                    child: Text('Remove'),
                  ),
              ],
              onSelected: (action) {
                switch (action) {
                  case _MemberAction.promote:
                    onPromote?.call();
                  case _MemberAction.block:
                    onBlock?.call();
                  case _MemberAction.unblock:
                    onUnblock?.call();
                  case _MemberAction.remove:
                    onRemove?.call();
                }
              },
            ),
        ],
      ),
    );
  }

  String _fmtJoinDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

enum _MemberAction { promote, block, unblock, remove }
