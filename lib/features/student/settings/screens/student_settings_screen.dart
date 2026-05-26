import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/settings/providers/student_settings_provider.dart';
import 'package:smart_meal_management/shared/providers/theme_provider.dart';

/// Student settings screen.
///
/// ## State
/// [StudentSettingsProvider] is owned by this [State] and disposed with it.
/// Uses [ListenableBuilder] — no manual `addListener/setState`.
///
/// ## Sections
/// 1. Attendance — Default Attendance toggle
/// 2. Availability — Vacation Mode toggle
/// 3. Notifications — Meal Reminders toggle
/// 4. Appearance — Theme selector (System / Light / Dark)
/// 5. Account — Logout
class StudentSettingsScreen extends StatefulWidget {
  const StudentSettingsScreen({super.key});

  @override
  State<StudentSettingsScreen> createState() => _StudentSettingsScreenState();
}

class _StudentSettingsScreenState extends State<StudentSettingsScreen> {
  StudentSettingsProvider? _provider;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _provider = StudentSettingsProvider(
        authProvider: AuthProviderScope.of(context),
        themeProvider: ThemeProvider.of(context),
      );
    }
  }

  @override
  void dispose() {
    _provider?.dispose();
    super.dispose();
  }

  /// Intercepts vacation mode enabling with a confirm dialog.
  /// Disabling vacation mode applies immediately without confirmation.
  Future<void> _onVacationToggle(bool value) async {
    final provider = _provider;
    if (provider == null) return;
    if (!value) {
      // Turning OFF — apply immediately
      await provider.setVacationMode(false);
      return;
    }
    // Turning ON — ask for confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const _VacationConfirmDialog(),
    );
    if (confirmed == true && mounted) {
      await provider.setVacationMode(true);
    }
  }

  Future<void> _logout() async {
    final confirmed = await _showLogoutDialog();
    if (!confirmed || !mounted) return;
    await AuthProviderScope.of(context).logout();
    if (mounted) context.go(RouteNames.roleSelect);
  }

  Future<bool> _showLogoutDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          builder: (ctx) => const _LogoutDialog(),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
          appBar: _SettingsAppBar(isDark: isDark),
          body: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space16,
              vertical: AppConstants.space20,
            ),
            children: [
              // ── Section 1: Attendance ───────────────────────────────────────
              _SectionLabel(label: 'Attendance', isDark: isDark),
              const SizedBox(height: AppConstants.space8),
              _SettingsCard(
                isDark: isDark,
                children: [
                  _ToggleTile(
                    icon: Icons.auto_awesome_rounded,
                    iconColor: AppColors.primary,
                    title: 'Default Attendance',
                    subtitle:
                        'Automatically marked present every day. Toggle off only when you are absent.',
                    value: provider.isDefaultAttendance,
                    onChanged: provider.setDefaultAttendance,
                    isDark: isDark,
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.space20),

              // ── Section 2: Availability ─────────────────────────────────────
              _SectionLabel(label: 'Availability', isDark: isDark),
              const SizedBox(height: AppConstants.space8),
              _SettingsCard(
                isDark: isDark,
                children: [
                  _ToggleTile(
                    icon: Icons.beach_access_rounded,
                    iconColor: AppColors.vacation,
                    title: 'Vacation Mode',
                    subtitle:
                        "Pauses all attendance tracking and reminder notifications while you're away.",
                    value: provider.isVacationMode,
                    onChanged: _onVacationToggle,
                    isDark: isDark,
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.space20),

              // ── Section 3: Notifications ────────────────────────────────────
              _SectionLabel(label: 'Notifications', isDark: isDark),
              const SizedBox(height: AppConstants.space8),
              _SettingsCard(
                isDark: isDark,
                children: [
                  _ToggleTile(
                    icon: Icons.notifications_active_rounded,
                    iconColor: AppColors.warning,
                    title: 'Meal Reminders',
                    subtitle:
                        'Reminded 30 min and 10 min before attendance windows close.',
                    value: provider.remindersEnabled && !provider.isVacationMode,
                    onChanged: provider.isVacationMode ? null : provider.setReminders,
                    isDark: isDark,
                    disabledReason:
                        provider.isVacationMode ? 'Paused during vacation mode' : null,
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.space20),

              // ── Section 4: Appearance ───────────────────────────────────────
              _SectionLabel(label: 'Appearance', isDark: isDark),
              const SizedBox(height: AppConstants.space8),
              _SettingsCard(
                isDark: isDark,
                children: [
                  _ThemeSelector(
                    current: provider.themeMode,
                    onChanged: provider.setThemeMode,
                    isDark: isDark,
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.space20),

              // ── Section 5: Account ──────────────────────────────────────────
              _SectionLabel(label: 'Account', isDark: isDark),
              const SizedBox(height: AppConstants.space8),
              _SettingsCard(
                isDark: isDark,
                children: [
                  _ActionTile(
                    icon: Icons.logout_rounded,
                    iconColor: AppColors.error,
                    title: 'Sign Out',
                    subtitle: 'You will need to sign in again to continue.',
                    onTap: _logout,
                    isDark: isDark,
                    isDestructive: true,
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.space32),

              // ── Version footer ──────────────────────────────────────────────
              Center(
                child: Text(
                  'MealAttend v1.0.0',
                  style: AppTypography.labelSmall.copyWith(
                    color: (isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary)
                        .withValues(alpha: 0.6),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.space16),
            ],
          ),
        );
      },
    );
  }
}

// ── App bar ────────────────────────────────────────────────────────────────────

class _SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SettingsAppBar({required this.isDark});
  final bool isDark;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Text(
        'Settings',
        style: AppTypography.titleLarge.copyWith(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.4)
              : AppColors.border.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isDark});
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ── Settings card ──────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children, required this.isDark});
  final List<Widget> children;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.6)
              : AppColors.border,
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

// ── Toggle tile ────────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
    this.disabledReason,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isDark;
  final String? disabledReason;

  bool get _isDisabled => onChanged == null;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _isDisabled ? 0.55 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space16,
          vertical: 14.0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon container
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14.0),
            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    disabledReason ?? subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: _isDisabled
                          ? (isDark
                              ? AppColors.textTertiaryDark
                              : AppColors.textTertiary)
                          : (isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.space8),
            Switch(
              value: value,
              onChanged: _isDisabled ? null : onChanged,
              activeThumbColor: iconColor,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action tile (logout etc.) ──────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
    this.isDestructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDark;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space16,
            vertical: 14.0,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDestructive ? AppColors.error : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Theme selector ─────────────────────────────────────────────────────────────

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({
    required this.current,
    required this.onChanged,
    required this.isDark,
  });

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.vacation.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.palette_rounded,
                  size: 18,
                  color: AppColors.vacation,
                ),
              ),
              const SizedBox(width: 14.0),
              Text(
                'App Theme',
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14.0),
          Row(
            children: ThemeMode.values.map((mode) {
              final isSelected = current == mode;
              final label = switch (mode) {
                ThemeMode.system => 'System',
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
              };
              final icon = switch (mode) {
                ThemeMode.system => Icons.brightness_auto_rounded,
                ThemeMode.light => Icons.light_mode_rounded,
                ThemeMode.dark => Icons.dark_mode_rounded,
              };
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: mode != ThemeMode.dark ? AppConstants.space8 : 0,
                  ),
                  child: GestureDetector(
                    onTap: () => onChanged(mode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.surfaceVariantDark
                                : AppColors.surfaceVariant),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.30),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: AppTypography.labelSmall.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Logout confirmation dialog ─────────────────────────────────────────────────

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.dialogRadius),
          border: Border.all(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.logout_rounded,
                size: 24,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppConstants.space16),
            Text(
              'Sign out?',
              style: AppTypography.titleMedium.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'You will be returned to the login screen and will need to sign in again.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space24),
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
                        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
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
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
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

// ── Vacation mode confirm dialog ───────────────────────────────────────────────

class _VacationConfirmDialog extends StatelessWidget {
  const _VacationConfirmDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.dialogRadius),
          border: Border.all(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.vacation.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.beach_access_rounded,
                color: AppColors.vacation,
                size: 26,
              ),
            ),
            const SizedBox(height: AppConstants.space16),

            Text(
              'Enable Vacation Mode?',
              style: AppTypography.titleMedium.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'Attendance tracking and all meal reminders will be paused while vacation mode is active.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space24),

            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.border,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppConstants.buttonRadius,
                        ),
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
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.vacation,
                        borderRadius: BorderRadius.circular(
                          AppConstants.buttonRadius,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.vacation.withValues(alpha: 0.30),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Enable',
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
