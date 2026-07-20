import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/user_avatar.dart';

/// Admin "More" hub screen — surfaces Profile, Settings and Exports links
/// that don't fit in the primary bottom nav.
class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;

    // Dark mode: indigo→violet gradient; Light mode: soft container gradient.
    final cardGradient = isDark
        ? const LinearGradient(
            colors: [AppColors.primary, AppColors.violet],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [AppColors.primaryContainer, AppColors.secondaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final onCard = isDark ? AppColors.onPrimary : AppColors.onPrimaryContainer;
    final onCardSubtle = isDark
        ? AppColors.onPrimary.withValues(alpha: 0.75)
        : AppColors.onPrimaryContainer.withValues(alpha: 0.7);
    final badgeBg = isDark
        ? AppColors.onPrimary.withValues(alpha: 0.15)
        : AppColors.primary.withValues(alpha: 0.15);
    final badgeText = isDark ? AppColors.onPrimary : AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: const Text('More'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── User identity card ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: cardGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                // ISSUE-003: real profile photo (locally picked bytes first,
                // then cached network avatar) with the same initials fallback.
                UserAvatar(
                  name: user?.name ?? 'Admin',
                  avatarUrl: user?.avatarUrl,
                  bytes: auth.avatarBytes,
                  radius: 28,
                  backgroundColor: isDark
                      ? AppColors.onPrimary.withValues(alpha: 0.2)
                      : AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Admin',
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: onCard,
                        ),
                      ),
                      if (user != null && user.email.isNotEmpty)
                        Text(
                          user.email,
                          style: AppTypography.bodySmall.copyWith(
                            color: onCardSubtle,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          user?.role.displayName ?? 'Manager',
                          style: AppTypography.labelSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: badgeText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Navigation group ─────────────────────────────────────────────
          const _SectionLabel(label: 'Account'),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.manage_accounts_rounded,
            label: 'Profile',
            subtitle: 'Edit your info and avatar',
            color: AppColors.primary,
            onTap: () => context.push(RouteNames.adminProfile),
          ),
          _NavTile(
            icon: Icons.settings_rounded,
            label: 'Settings',
            subtitle: 'App preferences and meal config',
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            onTap: () => context.push(RouteNames.adminSettings),
          ),
          _NavTile(
            icon: Icons.how_to_reg_rounded,
            label: 'Mark My Attendance',
            subtitle: 'Mark your own meals like a member',
            color: AppColors.present,
            onTap: () => context.push(RouteNames.adminMyAttendance),
          ),

          const SizedBox(height: 20),

          const _SectionLabel(label: 'Data'),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.download_rounded,
            label: 'Export Reports',
            subtitle: 'Download PDF or Excel attendance reports',
            color: AppColors.secondary,
            onTap: () => context.push(RouteNames.adminExports),
          ),

          const SizedBox(height: 20),

          const _SectionLabel(label: 'Session'),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.logout_rounded,
            label: 'Sign Out',
            subtitle: 'Return to role selection',
            color: AppColors.error,
            onTap: () async {
              // Premium confirmation dialog (visual parity with the student flow).
              final confirmed = await showDialog<bool>(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.5),
                builder: (_) => const _AdminLogoutDialog(),
              );
              if (confirmed != true) return;
              await auth.logout();
              if (context.mounted) context.go(RouteNames.roleSelect);
            },
          ),

          const SizedBox(height: 32),

          // ── App version note ─────────────────────────────────────────────
          Center(
            child: Text(
              'Smart Meal Management · v1.0.0-mvp',
              style: AppTypography.bodySmall.copyWith(
                color: (isDark ? AppColors.textTertiaryDark : AppColors.textTertiary)
                    .withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      label.toUpperCase(),
      style: AppTypography.labelSmall.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.6),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        title: Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTypography.bodySmall.copyWith(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)
              .withValues(alpha: 0.6),
        ),
      ),
    );
  }
}


// ── Sign-out confirmation dialog (matches the student settings dialog style) ──
class _AdminLogoutDialog extends StatelessWidget {
  const _AdminLogoutDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.logout_rounded,
                  size: 24, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(
              'Sign out?',
              style: AppTypography.titleMedium.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You will be returned to the role selection screen.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceVariantDark
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: AppTypography.labelMedium.copyWith(
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.error.withValues(alpha: 0.30),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Sign Out',
                          style: AppTypography.labelMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
