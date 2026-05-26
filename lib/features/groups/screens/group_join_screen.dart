import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/groups/providers/group_provider.dart';
import 'package:smart_meal_management/features/groups/screens/group_detail_screen.dart';
import 'package:smart_meal_management/features/groups/widgets/group_join_card.dart';
import 'package:smart_meal_management/features/groups/widgets/qr_scanner_view.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
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

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.prefillCode ?? '');
    _provider = GroupProvider();
    _provider.addListener(_rebuild);
    // Auto-submit when a code arrives via deep-link / QR URL.
    if (widget.prefillCode != null && widget.prefillCode!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onJoin(widget.prefillCode!),
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

  Future<void> _onJoin(String code) async {
    final authProvider = AuthProviderScope.of(context);
    final user = authProvider.currentUser;
    final userId = user?.id ?? '';
    final orgId = user?.organizationId ?? 'org_001';
    final ok = await _provider.joinByCode(
      userId: userId,
      joinCode: code,
      organizationId: orgId,
    );
    if (!mounted) return;
    if (ok && _provider.lastJoined != null) {
      setState(() {
        _successGroupId = _provider.lastJoined!.id;
      });

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
      await _onJoin(code);
    }
  }

  void _reset() {
    _codeCtrl.clear();
    _provider.clearLastJoined();
    setState(() => _successGroupId = null);
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
          child: _successGroupId != null
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
                    const SizedBox(height: 28),
                    GroupJoinCard(
                      controller: _codeCtrl,
                      isLoading: _provider.isJoining,
                      errorText: _provider.joinError,
                      onJoin: _onJoin,
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
            text: 'Enter the 6-character code above and tap Join Group.',
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
