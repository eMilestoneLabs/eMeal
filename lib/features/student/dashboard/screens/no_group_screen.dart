import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/groups/providers/group_provider.dart';

/// Premium no-group onboarding screen.
///
/// Shown when the authenticated student has not yet joined any group.
/// Provides two entry paths:
///   1. Scan QR Code — opens the group-join QR scanner.
///   2. Enter Join Code — bottom sheet with a 6-char code input.
///
/// Design intent: feels like a welcoming product moment, not an error state.
/// Animated ambient orbs, glass card, glowing icon — matches auth screen energy.
class NoGroupScreen extends StatefulWidget {
  const NoGroupScreen({super.key});

  @override
  State<NoGroupScreen> createState() => _NoGroupScreenState();
}

class _NoGroupScreenState extends State<NoGroupScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  // Issue 4: second place to re-access a "Waiting for approval" request. A
  // student who only has a pending request (no active group) lands here after
  // tapping Done, so surface it with a tappable entry back into the join flow.
  final _groupProvider = GroupProvider();

  @override
  void initState() {
    super.initState();
    _groupProvider.addListener(_onPendingChanged);
    _groupProvider.loadPendingRequests();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    ));
    _ctrl.forward();
  }

  void _onPendingChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _groupProvider.removeListener(_onPendingChanged);
    _groupProvider.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  /// Push instead of go so the Android back button returns to the student
  /// home tab (via the shell's bottom nav history) rather than exiting the app.
  Future<void> _scanQr() async {
    await context.push(RouteNames.groupJoin);
    if (mounted) _groupProvider.loadPendingRequests(); // reflect any change
  }

  /// Issue 4: re-open the join screen (which shows the full "Waiting for
  /// approval" state + Cancel) from the pending banner.
  Future<void> _openPending() async {
    await context.push(RouteNames.groupJoin);
    if (mounted) _groupProvider.loadPendingRequests();
  }

  void _enterCode() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinCodeSheet(onSubmit: (code) {
        Navigator.of(context).pop();
        // Push instead of go — preserves back-stack so Android back works.
        context.push('${RouteNames.groupJoin}?code=$code');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0B1120), const Color(0xFF111827)]
                : [const Color(0xFFF5F7FF), const Color(0xFFEEF2FF)],
          ),
        ),
        child: Stack(
          children: [
            // ── Ambient orbs ──────────────────────────────────────────
            Positioned(
              top: -60,
              right: -80,
              child: _Orb(size: 280, color: AppColors.primary, alpha: isDark ? 0.18 : 0.09),
            ),
            Positioned(
              bottom: size.height * 0.15,
              left: -60,
              child: _Orb(size: 220, color: const Color(0xFF7C3AED), alpha: isDark ? 0.14 : 0.07),
            ),
            Positioned(
              bottom: -40,
              right: size.width * 0.2,
              child: _Orb(size: 160, color: AppColors.secondary, alpha: isDark ? 0.10 : 0.05),
            ),

            // ── Main content ─────────────────────────────────────────
            SafeArea(
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.space24,
                    ),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),

                        // ── Icon container ──────────────────────────
                        _GlowIcon(isDark: isDark),

                        const SizedBox(height: AppConstants.space32),

                        // ── Headline ─────────────────────────────────
                        Text(
                          "You haven't joined\na group yet",
                          style: AppTypography.headlineMedium.copyWith(
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.25,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: AppConstants.space16),

                        // ── Subtext ───────────────────────────────────
                        Text(
                          'Ask your Admin or Manager for an invite QR code\nto start tracking meals & attendance.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        // ── Pending request banner (Issue 4) ─────────
                        if (_groupProvider.pendingRequests.isNotEmpty) ...[
                          const SizedBox(height: AppConstants.space24),
                          _PendingBanner(
                            count: _groupProvider.pendingRequests.length,
                            groupName:
                                _groupProvider.pendingRequests.first.name,
                            isDark: isDark,
                            onTap: _openPending,
                          ),
                        ],

                        const Spacer(flex: 2),

                        // ── Info chip ────────────────────────────────
                        _InfoChip(isDark: isDark),

                        const SizedBox(height: AppConstants.space32),

                        // ── Primary CTA: Scan QR ─────────────────────
                        _ScanButton(onTap: _scanQr),

                        const SizedBox(height: AppConstants.space12),

                        // ── Secondary: Enter code ─────────────────────
                        _CodeButton(onTap: _enterCode, isDark: isDark),

                        const Spacer(flex: 1),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Glow icon ──────────────────────────────────────────────────────────────────

class _GlowIcon extends StatelessWidget {
  const _GlowIcon({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF7C3AED), AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.40),
            blurRadius: 48,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.18),
            blurRadius: 64,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Inner glow highlight
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),
          const Icon(Icons.group_add_rounded, size: 42, color: Colors.white),
        ],
      ),
    );
  }
}

// ── Info chip ──────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space16,
            vertical: AppConstants.space8,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : AppColors.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
              const SizedBox(width: AppConstants.space6),
              Text(
                'No account needed for Event Guest joining',
                style: AppTypography.labelSmall.copyWith(
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pending request banner (Issue 4) ────────────────────────────────────────

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({
    required this.count,
    required this.groupName,
    required this.isDark,
    required this.onTap,
  });

  final int count;
  final String groupName;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.warning.withValues(alpha: 0.16),
                AppColors.warning.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.hourglass_top_rounded,
                    color: AppColors.warning, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? 'Waiting for approval'
                          : '$count requests waiting',
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 1
                          ? '$groupName · tap to view or cancel'
                          : 'Tap to view or cancel your requests',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
    );
  }
}

// ── Scan QR button ─────────────────────────────────────────────────────────────

class _ScanButton extends StatefulWidget {
  const _ScanButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF6366F1)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded,
                  size: 22, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                'Scan QR Code',
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Enter code button ──────────────────────────────────────────────────────────

class _CodeButton extends StatelessWidget {
  const _CodeButton({required this.onTap, required this.isDark});
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.80),
          borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.keyboard_rounded,
              size: 18,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
            const SizedBox(width: AppConstants.space8),
            Text(
              'Enter Join Code',
              style: AppTypography.labelLarge.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ambient orb ────────────────────────────────────────────────────────────────

class _Orb extends StatelessWidget {
  const _Orb({
    required this.size,
    required this.color,
    required this.alpha,
  });

  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.35),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

// ── Join code bottom sheet ─────────────────────────────────────────────────────

class _JoinCodeSheet extends StatefulWidget {
  const _JoinCodeSheet({required this.onSubmit});
  final ValueChanged<String> onSubmit;

  @override
  State<_JoinCodeSheet> createState() => _JoinCodeSheetState();
}

class _JoinCodeSheetState extends State<_JoinCodeSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final ok = _ctrl.text.trim().length >= 4;
      if (ok != _canSubmit) setState(() => _canSubmit = ok);
    });
    // Auto-focus the field
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.bottomSheetRadius),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.space24,
        AppConstants.space24,
        AppConstants.space24,
        AppConstants.space24 + viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ──────────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.borderDark : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.space20),

          // ── Title ────────────────────────────────────────────────────────
          Text(
            'Enter Join Code',
            style: AppTypography.titleMedium.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.space6),
          Text(
            'Enter the group code shared by your Admin or Manager.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.space20),

          // ── Input ────────────────────────────────────────────────────────
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: _canSubmit
                ? (_) => widget.onSubmit(_ctrl.text.trim().toUpperCase())
                : null,
            style: AppTypography.titleMedium.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. HOSTEL01',
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
                letterSpacing: 2,
              ),
              filled: true,
              fillColor: isDark
                  ? AppColors.surfaceVariantDark.withValues(alpha: 0.5)
                  : AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppConstants.space16,
                vertical: AppConstants.space16,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.space20),

          // ── Submit ───────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: AnimatedOpacity(
              opacity: _canSubmit ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 200),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFF6366F1)],
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                    onTap: _canSubmit
                        ? () => widget.onSubmit(_ctrl.text.trim().toUpperCase())
                        : null,
                    child: Center(
                      child: Text(
                        'Join Group',
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

