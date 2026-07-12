import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/features/events/providers/event_admin_provider.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/event_admin_shell.dart';

// ── EventAdminSettingsTab ──────────────────────────────────────────────────────

/// Settings tab — event details, theme toggle, logout, and danger zone.
class EventAdminSettingsTab extends StatelessWidget {
  const EventAdminSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = EventAdminScope.of(context);
    final themeNotifier = EventThemeScope.of(context);
    final event = provider.event;
    final isDark = EventThemeScope.isDark(context);

    if (event == null) return const SizedBox.shrink();

    return CustomScrollView(
      slivers: [
        // ── App bar ─────────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              const Icon(Icons.settings_rounded,
                  size: 20, color: AppColors.vacation),
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: AppTypography.titleLarge.copyWith(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),

        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppConstants.pagePaddingH,
            20,
            AppConstants.pagePaddingH,
            MediaQuery.paddingOf(context).bottom + 32,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── Event details ─────────────────────────────────────────────
              _SectionLabel(label: 'Event Details', isDark: isDark),
              const SizedBox(height: 12),
              _DetailCard(isDark: isDark, children: [
                _DetailRow(
                    label: 'Event Name',
                    value: event.name,
                    isDark: isDark),
                _DividerLine(isDark: isDark),
                _DetailRow(
                    label: 'Type',
                    value: '${event.type.emoji}  ${event.type.label}',
                    isDark: isDark),
                _DividerLine(isDark: isDark),
                _DetailRow(
                    label: 'Date',
                    value: event.formattedDate,
                    isDark: isDark),
                _DividerLine(isDark: isDark),
                _DetailRow(
                    label: 'Expected Guests',
                    value: '${event.expectedGuestCount}',
                    isDark: isDark),
                _DividerLine(isDark: isDark),
                _DetailRow(
                    label: 'Join Code',
                    value: event.joinCode ?? '—',
                    isDark: isDark,
                    valueColor: AppColors.vacation),
                _DividerLine(isDark: isDark),
                _DetailRow(
                    label: 'Meal Types',
                    value: '${event.mealTypes.length} configured',
                    isDark: isDark),
              ]),
              const SizedBox(height: 24),

              // ── Appearance ────────────────────────────────────────────────
              _SectionLabel(label: 'Appearance', isDark: isDark),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                iconColor: isDark
                    ? const Color(0xFF7C5CBF)
                    : const Color(0xFFF59E0B),
                title: isDark ? 'Dark Theme' : 'Light Theme',
                subtitle: isDark
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
                isDark: isDark,
                trailing: Switch(
                  value: isDark,
                  onChanged: (_) => themeNotifier.toggle(),
                  activeThumbColor: AppColors.vacation,
                  activeTrackColor: AppColors.vacation.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(height: 24),

              // ── Auto-delete ───────────────────────────────────────────────
              _SectionLabel(label: 'Data Retention', isDark: isDark),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: event.autoDeleteAfter7Days
                    ? Icons.auto_delete_rounded
                    : Icons.folder_outlined,
                iconColor: event.autoDeleteAfter7Days
                    ? AppColors.warning
                    : (isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiary),
                title: event.autoDeleteAfter7Days
                    ? 'Auto-delete enabled'
                    : 'Manual retention',
                subtitle: event.autoDeleteAfter7Days
                    ? 'Data deleted 7 days after event date'
                    : 'Data retained until manually closed',
                isDark: isDark,
              ),
              const SizedBox(height: 24),

              // ── Export ────────────────────────────────────────────────────
              _SectionLabel(label: 'Export', isDark: isDark),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.picture_as_pdf_rounded,
                iconColor: AppColors.error,
                title: 'Export Guest List — PDF',
                subtitle: 'Download attendance as a formatted PDF report',
                isDark: isDark,
                onTap: () => _exportPdf(context, provider),
              ),
              const SizedBox(height: 8),
              _SettingsTile(
                icon: Icons.table_chart_rounded,
                iconColor: AppColors.present,
                title: 'Export Guest List — Excel',
                subtitle: 'Download attendance data as an Excel spreadsheet',
                isDark: isDark,
                onTap: () => _exportXlsx(context, provider),
              ),
              const SizedBox(height: 24),

              // ── Account ───────────────────────────────────────────────────
              _SectionLabel(label: 'Account', isDark: isDark),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.logout_rounded,
                iconColor: AppColors.error,
                title: 'Log Out',
                subtitle: 'Return to the app home screen',
                isDark: isDark,
                onTap: () => _confirmLogout(context),
              ),
              const SizedBox(height: 24),

              // ── Danger zone ───────────────────────────────────────────────
              _SectionLabel(
                  label: 'Danger Zone', isDark: isDark, color: AppColors.error),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      AppColors.error.withValues(alpha: isDark ? 0.08 : 0.04),
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 16, color: AppColors.error),
                        const SizedBox(width: 8),
                        Text(
                          'Close This Event',
                          style: AppTypography.bodyMedium.copyWith(
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Once closed, guests can no longer join or modify their '
                      'attendance. This action cannot be undone.',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: !event.isActive
                            ? null
                            : () => _confirmClose(context, provider, isDark),
                        icon: const Icon(Icons.lock_rounded, size: 16),
                        label: Text(
                            !event.isActive ? 'Event Closed' : 'Close Event'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.error.withValues(alpha: 0.3),
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Export helpers ────────────────────────────────────────────────────────────

  Future<void> _exportPdf(
      BuildContext context, EventAdminProvider provider) async {
    if (provider.event == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final event = provider.event!;
    try {
      await ExportService.instance.exportEventGuestsPdf(
        parties: provider.parties,
        eventName: event.name,
        eventDateLabel: event.formattedDate,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('PDF exported successfully'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: ${e.toString()}'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // SRS Module 03 RPT-001: CSV removed — the spreadsheet export is Excel.
  Future<void> _exportXlsx(
      BuildContext context, EventAdminProvider provider) async {
    if (provider.event == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final event = provider.event!;
    try {
      await ExportService.instance.exportEventGuestsXlsx(
        parties: provider.parties,
        eventName: event.name,
        eventDateLabel: event.formattedDate,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Excel exported successfully'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: ${e.toString()}'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────────

  void _confirmLogout(BuildContext context) {
    final isDark = EventThemeScope.isDark(context);
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Log Out?',
          style: AppTypography.titleMedium.copyWith(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'You will be taken back to the app home screen.',
          style: AppTypography.bodyMedium.copyWith(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: AppTypography.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to root — pop all routes, landing on onboarding/home
              context.go('/');
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.vacation,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _confirmClose(
    BuildContext context,
    EventAdminProvider provider,
    bool isDark,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Close Event?',
          style: AppTypography.titleMedium.copyWith(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Guests will no longer be able to join or update attendance. '
          'This cannot be undone.',
          style: AppTypography.bodyMedium.copyWith(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await provider.closeEvent();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Event closed successfully'),
                    backgroundColor: AppColors.present,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                context.go(RouteNames.eventAdminRoot);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close Event'),
          ),
        ],
      ),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.isDark,
    this.color,
  });

  final String label;
  final bool isDark;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.titleSmall.copyWith(
        color: color ??
            (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ── Settings tile ──────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color:
                    isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Detail card ────────────────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.isDark, required this.children});
  final bool isDark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodySmall.copyWith(
                color: valueColor ??
                    (isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: isDark
          ? AppColors.borderDark.withValues(alpha: 0.4)
          : AppColors.border,
    );
  }
}
