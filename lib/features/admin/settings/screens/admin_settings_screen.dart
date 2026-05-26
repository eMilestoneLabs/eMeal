import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/admin/settings/providers/admin_settings_provider.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/providers/theme_provider.dart';

/// Admin settings screen.
///
/// Toggle states are persisted via [AdminSettingsProvider] → SharedPreferences.
/// Theme mode is delegated to the shared [ThemeProvider] so changes are
/// immediate and app-wide (same pattern as the student settings screen).
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  AdminSettingsProvider? _provider;
  bool _initDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initDone) {
      _initDone = true;
      _provider = AdminSettingsProvider(
        authProvider: AuthProviderScope.of(context),
        themeProvider: ThemeProvider.of(context),
      );
      // Load persisted values — rebuilds via notifyListeners when done.
      _provider!.initialize().then((_) {
        if (mounted) setState(() {});
      });
      _provider!.addListener(_rebuild);
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider?.removeListener(_rebuild);
    _provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = _provider!;

    // Show a subtle loader while SharedPreferences values are being read.
    if (!p.isInitialized) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          title: Text('Settings', style: AppTypography.titleLarge),
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('Settings', style: AppTypography.titleLarge),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.pagePaddingH,
          vertical: AppConstants.pagePaddingV,
        ),
        children: [
          // ── Notifications ─────────────────────────────────────────────────
          const _SectionHeader('Notifications'),
          _SettingsTile(
            icon: Icons.notifications_rounded,
            title: 'Push Notifications',
            subtitle: 'Receive alerts for attendance updates',
            trailing: Switch(
              value: p.notificationsEnabled,
              onChanged: (v) => p.setNotifications(v),
            ),
          ),

          const SizedBox(height: 16),

          // ── Appearance ────────────────────────────────────────────────────
          const _SectionHeader('Appearance'),
          _ThemeSelectorCard(
            isDark: isDark,
            current: p.themeMode,
            onChanged: p.setThemeMode,
          ),

          const SizedBox(height: 16),

          // ── Analytics ─────────────────────────────────────────────────────
          const _SectionHeader('Analytics'),
          _SettingsTile(
            icon: Icons.analytics_rounded,
            title: 'Usage Analytics',
            subtitle: 'Help improve MealAttend with anonymous data',
            trailing: Switch(
              value: p.analyticsEnabled,
              onChanged: (v) => p.setAnalytics(v),
            ),
          ),

          const SizedBox(height: 32),

          // ── Sign out ──────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () async {
              await p.signOut();
            },
            icon: const Icon(Icons.logout_rounded, color: AppColors.absent),
            label: Text(
              'Sign Out',
              style: AppTypography.labelLarge.copyWith(color: AppColors.absent),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: AppColors.absent),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: isDark ? AppColors.textSecondaryDark : AppColors.textTertiary,
        ),
      ),
    );
  }
}

// ── Settings tile ──────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleSmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
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
          trailing,
        ],
      ),
    );
  }
}

// ── Theme selector card ────────────────────────────────────────────────────────

/// 3-button theme selector card (System / Light / Dark).
///
/// Matches the [_ThemeSelector] widget used in the student settings screen
/// so both flows feel consistent.
class _ThemeSelectorCard extends StatelessWidget {
  const _ThemeSelectorCard({
    required this.isDark,
    required this.current,
    required this.onChanged,
  });

  final bool isDark;
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.6)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with icon + label
          Row(
            children: [
              const Icon(Icons.palette_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Theme',
                    style: AppTypography.titleSmall.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Choose your preferred display mode',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 3-button selector row
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
                                  color:
                                      AppColors.primary.withValues(alpha: 0.30),
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
