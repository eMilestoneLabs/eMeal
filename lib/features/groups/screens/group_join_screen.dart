import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/groups/providers/group_provider.dart';
import 'package:smart_meal_management/features/groups/screens/group_detail_screen.dart';
import 'package:smart_meal_management/features/groups/widgets/group_join_card.dart';
import 'package:smart_meal_management/features/groups/widgets/qr_scanner_view.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Student group-join screen — 6-char code entry with success/error states.
///
/// [prefillCode] is supplied when the student arrives via a QR-scanned URL
/// (e.g. `context.push('/groups/join?code=ABC123')`). The code is pre-filled
/// in the text field and join is attempted automatically.
class GroupJoinScreen extends StatefulWidget {
  const GroupJoinScreen({super.key, this.prefillCode});

  /// Optional code pre-filled from a QR scan deep-link.
  final String? prefillCode;

  @override
  State<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

class _GroupJoinScreenState extends State<GroupJoinScreen> {
  late final GroupProvider _provider;
  late final TextEditingController _codeCtrl;
  String? _successGroupId;
  // MEM-004: set when a join created a pending approval request.
  GroupModel? _pendingGroup;

  // #2: the member's chosen per-group display role. Member-level only — admin
  // titles are never offered here (and the server rejects them). Default
  // 'student'; the same value is used by the QR/deep-link auto-join path.
  UserRole _selectedRole = UserRole.student;
  static const List<UserRole> _memberRoleOptions = [
    UserRole.student,
    UserRole.member,
    UserRole.guest,
  ];

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.prefillCode ?? '');
    _provider = GroupProvider();
    _provider.addListener(_rebuild);
    // Issue 4: surface any existing pending join requests so the student can
    // re-open "Waiting for approval" (and Cancel) after tapping Done earlier.
    _provider.loadPendingRequests();
    // Auto-submit when a code arrives via deep-link / QR URL.
    if (widget.prefillCode != null && widget.prefillCode!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onJoin(widget.prefillCode!, preview: false),
      );
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// MEM-002: manually-entered codes get a pre-join preview (identity +
  /// capacity + whether approval is required). QR / deep-link auto-joins skip
  /// the extra round-trip (scanning already implies intent).
  Future<void> _onJoin(String code, {bool preview = true}) async {
    if (preview) {
      final info = await _provider.previewJoin(code);
      if (info == null) return; // joinError surfaced by the card
      if (!mounted) return;
      final confirmed = await _showPreviewSheet(info);
      if (confirmed != true) return;
    }
    if (!mounted) return;

    final authProvider = AuthProviderScope.of(context);
    final user = authProvider.currentUser;
    final userId = user?.id ?? '';
    final orgId = user?.organizationId ?? 'org_001';
    final ok = await _provider.joinByCode(
      userId: userId,
      joinCode: code,
      organizationId: orgId,
      // #2: send the chosen member-level role as the per-group display title.
      functionalRole: _selectedRole.name,
    );
    if (!mounted) return;

    // MEM-004: a pending join shows the "waiting for approval" state — no org
    // sync / session refresh until an admin approves.
    if (ok && (_provider.lastJoined?.isPendingApproval ?? false)) {
      setState(() => _pendingGroup = _provider.lastJoined);
      // Issue 4: keep the re-accessible pending list current for both places.
      _provider.loadPendingRequests();
      return;
    }

    if (ok && _provider.lastJoined != null) {
      setState(() {
        _successGroupId = _provider.lastJoined!.id;
      });

      // Refresh the JWT so the organizationId the backend just set on this first
      // join enters the access token — fixes group / weekly menu / dashboard load.
      await authProvider.refreshSession();
      if (!mounted) return;

      // G2 fix: patch the in-memory UserModel so StudentShell's ListenableBuilder
      // fires immediately — Meals and Attendance tabs appear without a re-login.
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        final newGroupId = _provider.lastJoined!.id;
        final existing = List<String>.from(currentUser.effectiveGroupIds);
        if (!existing.contains(newGroupId)) existing.add(newGroupId);
        await authProvider.refreshUser(
          currentUser.copyWith(
            groupIds: existing,
            // Also set legacy groupId field if unset (effectiveGroupIds fallback).
            groupId: currentUser.groupId ?? newGroupId,
          ),
        );
      }
    }
  }

  /// Open the full-screen QR scanner.
  /// When a valid code is scanned, the scanner pops itself and we auto-join.
  Future<void> _openQrScanner() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => QrScannerView(
          onCodeScanned: (scannedCode) {
            Navigator.of(context).pop(scannedCode);
          },
        ),
      ),
    );

    if (code != null && mounted) {
      _codeCtrl.text = code;
      await _onJoin(code, preview: false);
    }
  }

  void _reset() {
    _codeCtrl.clear();
    _provider.clearLastJoined();
    setState(() {
      _successGroupId = null;
      _pendingGroup = null;
    });
  }

  /// MEM-002: bottom-sheet preview shown before a manual join. Returns true when
  /// the member confirms.
  Future<bool?> _showPreviewSheet(Map<String, dynamic> info) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final approval = info['approvalRequired'] == true;
    final isFull = info['isFull'] == true;
    final expired = info['expired'] == true;
    final current = (info['currentMembers'] as num?)?.toInt() ?? 0;
    final max = (info['maxMembers'] as num?)?.toInt();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(info['name']?.toString() ?? 'Group',
                style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(ctx).colorScheme.onSurface)),
            if (info['organizationName'] != null) ...[
              const SizedBox(height: 2),
              Text(info['organizationName'].toString(),
                  style: AppTypography.bodySmall.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
            if ((info['description'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(info['description'].toString(),
                  style: AppTypography.bodyMedium.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.groups_rounded,
                  size: 16,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                max != null ? '$current / $max members' : '$current members',
                style: AppTypography.labelMedium.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ]),
            if (approval) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.verified_user_rounded,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Admin approval required to join.',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.warning)),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: (isFull || expired)
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(
                  isFull
                      ? 'Group Full'
                      : expired
                          ? 'Code Expired'
                          : approval
                              ? 'Request to Join'
                              : 'Join Group',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelPending() async {
    final g = _pendingGroup;
    if (g == null) return;
    final ok = await _provider.cancelPendingRequest(g.id);
    if (!mounted) return;
    if (ok) {
      _reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join request cancelled.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_provider.joinError ?? 'Could not cancel.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Join a Group', style: AppTypography.titleLarge),
        centerTitle: false,
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.pagePaddingH,
            vertical: AppConstants.pagePaddingV,
          ),
          child: _pendingGroup != null
              ? _PendingView(
                  group: _pendingGroup!,
                  onCancel: _cancelPending,
                  onDone: _reset,
                )
              : _successGroupId != null
              ? _SuccessView(
                  group: _provider.lastJoined,
                  onJoinAnother: _reset,
                  onViewGroup: () => _openDetail(context, _successGroupId!),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Join a Group',
                      style: AppTypography.headlineSmall.copyWith(
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Enter the code shared by your admin to join their group.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                      ),
                    ),
                    // Issue 4: re-accessible pending requests (both places — this
                    // screen + the student groups switcher deep-link here).
                    if (_provider.pendingRequests.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _PendingRequestsSection(
                        groups: _provider.pendingRequests,
                        onReopen: (g) => setState(() => _pendingGroup = g),
                      ),
                    ],
                    const SizedBox(height: 28),
                    GroupJoinCard(
                      controller: _codeCtrl,
                      isLoading: _provider.isJoining,
                      errorText: _provider.joinError,
                      onJoin: _onJoin,
                    ),
                    const SizedBox(height: 20),

                    // ── #2: per-group role picker (member-level only) ───────
                    _RolePicker(
                      options: _memberRoleOptions,
                      selected: _selectedRole,
                      isDark: isDark,
                      onChanged: (r) => setState(() => _selectedRole = r),
                    ),
                    const SizedBox(height: 16),

                    // ── QR scan option ─────────────────────────────────────
                    _QrScanButton(onTap: _openQrScanner),

                    const SizedBox(height: 32),
                    _HowItWorksSection(),
                  ],
                ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, String groupId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          groupId: groupId,
          organizationId: _provider.lastJoined?.organizationId ?? '',
        ),
      ),
    );
  }
}

// ── Pending (waiting for approval) view — MEM-004/005 ────────────────────────

class _PendingView extends StatelessWidget {
  const _PendingView({
    required this.group,
    required this.onCancel,
    required this.onDone,
  });

  final GroupModel group;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 48),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.hourglass_top_rounded,
              size: 44, color: AppColors.warning),
        ),
        const SizedBox(height: 20),
        Text(
          'Waiting for approval',
          style: AppTypography.headlineSmall.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your request to join ${group.name} has been sent. You will be '
          'notified once an admin approves it.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel request'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}

// ── Pending requests section (Issue 4) ──────────────────────────────────────

/// Re-accessible list of the student's own pending join requests. Tapping a row
/// re-opens the "Waiting for approval" view (with Cancel). Shown on the Join a
/// Group screen and reachable from the student groups switcher.
class _PendingRequestsSection extends StatelessWidget {
  const _PendingRequestsSection({required this.groups, required this.onReopen});

  final List<GroupModel> groups;
  final ValueChanged<GroupModel> onReopen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.warning.withValues(alpha: 0.14),
            AppColors.warning.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top_rounded,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                groups.length == 1
                    ? 'Pending request'
                    : '${groups.length} pending requests',
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...groups.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: isDark ? AppColors.surfaceDark : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onReopen(g),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.name,
                                style: AppTypography.labelLarge
                                    .copyWith(fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Waiting for approval',
                                style: AppTypography.bodySmall.copyWith(
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.warning),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Success view ───────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.group,
    required this.onJoinAnother,
    required this.onViewGroup,
  });

  final GroupModel? group;
  final VoidCallback onJoinAnother;
  final VoidCallback onViewGroup;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = group?.name ?? 'Group';
    final type = group?.type.label ?? '';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 48),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 44,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "You're in!",
          style: AppTypography.headlineSmall.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Successfully joined $name${type.isNotEmpty ? ' ($type)' : ''}.',
          style: AppTypography.bodyMedium.copyWith(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onViewGroup,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('View Group'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onJoinAnother,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Join Another Group'),
          ),
        ),
      ],
    );
  }
}

// ── How it works ───────────────────────────────────────────────────────────────

class _HowItWorksSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to join',
            style: AppTypography.titleSmall.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const _Step(
            number: '1',
            text: 'Ask your group admin or manager for the invite QR code.',
          ),
          const SizedBox(height: 8),
          const _Step(
            number: '2',
            text: 'Enter the group code above and tap Join Group.',
          ),
          const SizedBox(height: 8),
          const _Step(
            number: '3',
            text: 'Start marking attendance and viewing your meal menu!',
          ),
        ],
      ),
    );
  }
}

// ── QR scan button ─────────────────────────────────────────────────────────────

class _QrScanButton extends StatelessWidget {
  const _QrScanButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner_rounded, size: 20, color: textColor),
            const SizedBox(width: 10),
            Text(
              'Scan QR Code instead',
              style: AppTypography.labelMedium.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── #2: role picker ────────────────────────────────────────────────────────

/// Premium segmented picker for the member's per-group display role. Only
/// member-level roles are offered — this is a display title, never a permission
/// grant (the server rejects admin roles on join).
class _RolePicker extends StatelessWidget {
  const _RolePicker({
    required this.options,
    required this.selected,
    required this.isDark,
    required this.onChanged,
  });

  final List<UserRole> options;
  final UserRole selected;
  final bool isDark;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your role in this group',
          style: AppTypography.labelMedium.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Shown on your profile and to your admin. Display only — it never '
          'changes your permissions.',
          style: AppTypography.bodySmall.copyWith(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((role) {
            final isSel = role == selected;
            return GestureDetector(
              onTap: () => onChanged(role),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isSel
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : (isDark
                          ? AppColors.surfaceVariantDark
                          : AppColors.surfaceVariant),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSel
                        ? AppColors.primary
                        : (isDark ? AppColors.borderDark : AppColors.border),
                    width: isSel ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSel) ...[
                      const Icon(Icons.check_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      role.label,
                      style: AppTypography.labelMedium.copyWith(
                        color: isSel
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
