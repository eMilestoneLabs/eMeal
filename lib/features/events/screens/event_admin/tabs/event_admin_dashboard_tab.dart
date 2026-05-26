import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_meal_type.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/features/events/providers/event_admin_provider.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/event_admin_shell.dart';

// ── EventAdminDashboardTab ─────────────────────────────────────────────────────

class EventAdminDashboardTab extends StatelessWidget {
  const EventAdminDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = EventAdminScope.of(context);
    final themeNotifier = EventThemeScope.of(context);
    final event = provider.event;
    final isDark = EventThemeScope.isDark(context);

    if (event == null) return const SizedBox.shrink();

    return CustomScrollView(
      slivers: [
        // ── App bar ────────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: true,
          backgroundColor:
              isDark ? AppColors.surfaceDark : AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(RouteNames.eventAdminRoot),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.name,
                style: AppTypography.titleMedium.copyWith(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  Text(event.type.emoji,
                      style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      event.type.label,
                      style: AppTypography.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            _StatusChip(status: event.status),
            const SizedBox(width: 4),
            // Dark/light theme toggle
            _AppBarIconBtn(
              icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              isDark: isDark,
              tooltip: isDark ? 'Light theme' : 'Dark theme',
              onTap: themeNotifier.toggle,
            ),
            const SizedBox(width: 2),
            // More menu (logout + close event)
            _AppBarMoreMenu(
              isDark: isDark,
              provider: provider,
            ),
            const SizedBox(width: 4),
          ],
        ),

        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppConstants.pagePaddingH,
            20,
            AppConstants.pagePaddingH,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── Date + join code ─────────────────────────────────────────
              _EventMetaRow(event: event, isDark: isDark),
              const SizedBox(height: 20),

              // ── Core stats grid ──────────────────────────────────────────
              _CoreStatsGrid(provider: provider, isDark: isDark),
              const SizedBox(height: 20),

              // ── Quick actions ────────────────────────────────────────────
              _QuickActionsRow(event: event, isDark: isDark),
              const SizedBox(height: 24),

              // ── Meal types analytics ─────────────────────────────────────
              if (event.mealTypes.isNotEmpty) ...[
                _MealTypeAnalytics(
                    provider: provider, event: event, isDark: isDark),
                const SizedBox(height: 24),
              ] else ...[
                _NoMealTypesCard(isDark: isDark),
                const SizedBox(height: 24),
              ],

              // ── Guest preview ────────────────────────────────────────────
              _GuestPreviewSection(provider: provider, isDark: isDark),
            ]),
          ),
        ),
      ],
    );
  }
}

// ── App bar icon button ────────────────────────────────────────────────────────

class _AppBarIconBtn extends StatelessWidget {
  const _AppBarIconBtn({
    required this.icon,
    required this.isDark,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surfaceVariantDark
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ── App bar more menu ──────────────────────────────────────────────────────────

class _AppBarMoreMenu extends StatelessWidget {
  const _AppBarMoreMenu({required this.isDark, required this.provider});
  final bool isDark;
  final EventAdminProvider provider;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      color: isDark ? AppColors.surfaceDark : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.6)
              : AppColors.border,
        ),
      ),
      elevation: isDark ? 6 : 3,
      shadowColor: isDark
          ? Colors.black.withValues(alpha: 0.4)
          : Colors.black.withValues(alpha: 0.12),
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceVariantDark
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.more_vert_rounded,
            size: 17,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary),
      ),
      onSelected: (value) {
        if (value == 'logout') _confirmLogout(context);
        if (value == 'close_event') _confirmClose(context, provider);
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout_rounded,
                  size: 16, color: AppColors.error),
              const SizedBox(width: 12),
              Text(
                'Log Out',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (provider.event?.isActive == true)
          PopupMenuItem<String>(
            value: 'close_event',
            child: Row(
              children: [
                Icon(Icons.lock_rounded,
                    size: 16,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(
                  'Close Event',
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Log Out?',
          style: AppTypography.titleMedium.copyWith(
            color: isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary,
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

  void _confirmClose(BuildContext context, EventAdminProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Close Event?',
          style: AppTypography.titleMedium.copyWith(
            color: isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Guests will no longer be able to join or update attendance.',
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
                    content: Text('Event closed'),
                    backgroundColor: AppColors.present,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
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

// ── Event meta row ─────────────────────────────────────────────────────────────

class _EventMetaRow extends StatelessWidget {
  const _EventMetaRow({required this.event, required this.isDark});
  final EventModel event;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.calendar_today_rounded,
            size: 14,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            event.formattedDate,
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (event.joinCode != null) ...[
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.vacation
                  .withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_rounded,
                    size: 11, color: AppColors.vacation),
                const SizedBox(width: 4),
                Text(
                  event.joinCode!,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.vacation,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Core stats grid ────────────────────────────────────────────────────────────

/// 3-column grid: Total · Adults · Children + Veg · Non-Veg · Pending
/// Uses LayoutBuilder to compute height proportionally — no overflow.
class _CoreStatsGrid extends StatelessWidget {
  const _CoreStatsGrid({required this.provider, required this.isDark});
  final EventAdminProvider provider;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        label: 'Total',
        value: provider.totalGuestCount,
        icon: Icons.groups_rounded,
        color: AppColors.vacation
      ),
      (
        label: 'Adults',
        value: provider.totalAdultCount,
        icon: Icons.person_rounded,
        color: AppColors.info
      ),
      (
        label: 'Children',
        value: provider.totalChildCount,
        icon: Icons.child_care_rounded,
        color: AppColors.warning
      ),
      (
        label: 'Veg',
        value: provider.totalVegCount,
        icon: Icons.eco_rounded,
        color: AppColors.present
      ),
      (
        label: 'Non-Veg',
        value: provider.totalNonVegCount,
        icon: Icons.set_meal_rounded,
        color: AppColors.error
      ),
      (
        label: 'Pending',
        value: provider.pendingMealCount,
        icon: Icons.hourglass_empty_rounded,
        color: AppColors.textTertiary
      ),
    ];

    return LayoutBuilder(builder: (_, constraints) {
      // Card width = (available width - 2 gaps) / 3 columns
      final cardW = (constraints.maxWidth - 20) / 3;
      // Height = 100% of card width for a comfortable square-ish card
      final cardH = cardW * 1.05;

      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: stats.map((s) {
          return SizedBox(
            width: cardW,
            height: cardH,
            child: _StatCard(
              label: s.label,
              value: s.value,
              icon: s.icon,
              color: s.color,
              isDark: isDark,
            ),
          );
        }).toList(),
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: AppTypography.titleLarge.copyWith(
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Quick actions ──────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.event, required this.isDark});
  final EventModel event;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Generate QR',
            icon: Icons.qr_code_2_rounded,
            color: AppColors.vacation,
            isDark: isDark,
            onTap: () => _showQrSheet(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: 'Export Report',
            icon: Icons.download_rounded,
            color: AppColors.info,
            isDark: isDark,
            onTap: () => _showExportSheet(context),
          ),
        ),
      ],
    );
  }

  void _showQrSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QrSheet(event: event, isDark: isDark),
    );
  }

  void _showExportSheet(BuildContext context) {
    final provider = EventAdminScope.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _ExportSheet(isDark: isDark, provider: provider, event: event),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(
              color: color.withValues(alpha: isDark ? 0.25 : 0.18)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Meal type analytics ────────────────────────────────────────────────────────

class _MealTypeAnalytics extends StatelessWidget {
  const _MealTypeAnalytics({
    required this.provider,
    required this.event,
    required this.isDark,
  });
  final EventAdminProvider provider;
  final EventModel event;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final breakdown = provider.mealTypeBreakdown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meal Breakdown',
          style: AppTypography.titleSmall.copyWith(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ...event.mealTypes.map((mt) {
          final counts = breakdown[mt.id] ??
              (total: 0, adults: 0, children: 0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MealTypeRow(
              mealType: mt,
              total: counts.total,
              adults: counts.adults,
              children: counts.children,
              isDark: isDark,
            ),
          );
        }),
        if (provider.pendingMealCount > 0)
          _MealTypeRow(
            mealType: const EventMealType(
              id: '_pending',
              title: 'Pending',
              emoji: '⏳',
              color: Color(0xFF9E9E9E),
            ),
            total: provider.pendingMealCount,
            adults: 0,
            children: 0,
            isDark: isDark,
            isPending: true,
          ),
      ],
    );
  }
}

class _MealTypeRow extends StatelessWidget {
  const _MealTypeRow({
    required this.mealType,
    required this.total,
    required this.adults,
    required this.children,
    required this.isDark,
    this.isPending = false,
  });

  final EventMealType mealType;
  final int total;
  final int adults;
  final int children;
  final bool isDark;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Text(mealType.emoji,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mealType.title,
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!isPending && (adults > 0 || children > 0))
                  Text(
                    '${adults > 0 ? "$adults adult${adults != 1 ? "s" : ""}" : ""}${adults > 0 && children > 0 ? "  ·  " : ""}${children > 0 ? "$children child${children != 1 ? "ren" : ""}" : ""}',
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: mealType.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$total',
              style: AppTypography.labelSmall.copyWith(
                color: mealType.color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoMealTypesCard extends StatelessWidget {
  const _NoMealTypesCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border:
            Border.all(color: AppColors.info.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant_menu_rounded,
              size: 18, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No meal types configured yet. Go to the Meals tab to add custom meal types.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Guest preview ──────────────────────────────────────────────────────────────

class _GuestPreviewSection extends StatelessWidget {
  const _GuestPreviewSection({
    required this.provider,
    required this.isDark,
  });

  final EventAdminProvider provider;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final parties = provider.parties;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Guest Parties',
              style: AppTypography.titleSmall.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (parties.length > 3)
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Tap Guests in the bottom bar to see all ${parties.length} parties'),
                      backgroundColor: AppColors.vacation,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  'View all ${parties.length}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.vacation,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (parties.isEmpty)
          _EmptyGuestsState(isDark: isDark)
        else
          ...parties.take(3).map((party) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PartyPreviewCard(
                    party: party,
                    provider: provider,
                    isDark: isDark),
              )),
      ],
    );
  }
}

class _PartyPreviewCard extends StatelessWidget {
  const _PartyPreviewCard({
    required this.party,
    required this.provider,
    required this.isDark,
  });

  final EventGuestParty party;
  final EventAdminProvider provider;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final allDone = party.allEventMealsSelected;
    final event = provider.event;

    return Container(
      padding: const EdgeInsets.all(14),
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
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.vacation.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                party.primaryName.isNotEmpty
                    ? party.primaryName[0].toUpperCase()
                    : '?',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.vacation,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  party.primaryName,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _MiniTag(
                      label:
                          '${party.adultsCount}A${party.childrenCount > 0 ? " · ${party.childrenCount}C" : ""}',
                      color: AppColors.info,
                    ),
                    _MiniTag(
                      label: allDone ? '✓ Done' : 'Pending',
                      color: allDone
                          ? AppColors.present
                          : AppColors.textTertiary,
                    ),
                    // Show meal type breakdown from party
                    if (event != null)
                      ...event.mealTypes.map((mt) {
                        final count = party.eventMealCount(mt.id);
                        if (count == 0) return const SizedBox.shrink();
                        return _MiniTag(
                            label: '${mt.emoji} $count',
                            color: mt.color);
                      }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _EmptyGuestsState extends StatelessWidget {
  const _EmptyGuestsState({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.group_add_rounded,
                size: 36,
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary),
            const SizedBox(height: 10),
            Text(
              'No guests yet',
              style: AppTypography.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Share the QR or join code so guests can join.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status chip ────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final EventStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      EventStatus.active => AppColors.present,
      EventStatus.upcoming => AppColors.info,
      EventStatus.ended => AppColors.textTertiary,
      EventStatus.expired => AppColors.absent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        status.label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ── QR Sheet ───────────────────────────────────────────────────────────────────

class _QrSheet extends StatelessWidget {
  const _QrSheet({required this.event, required this.isDark});
  final EventModel event;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.borderDark : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.vacation.withValues(alpha: 0.3),
                  width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.vacation.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_2_rounded,
                    size: 100, color: AppColors.vacation),
                const SizedBox(height: 8),
                Text(
                  event.joinCode ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.vacation,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            event.name,
            style: AppTypography.titleMedium.copyWith(
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Guests scan this QR or enter the code to join.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    side: BorderSide(
                        color: isDark
                            ? AppColors.borderDark
                            : AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('QR sharing coming soon'),
                        backgroundColor: AppColors.vacation,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Share QR'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.vacation,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Export Sheet ───────────────────────────────────────────────────────────────

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({
    required this.isDark,
    required this.provider,
    required this.event,
  });
  final bool isDark;
  final EventAdminProvider provider;
  final EventModel event;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _exportingPdf = false;
  bool _exportingExcel = false;

  Future<void> _mockExport({required bool isPdf}) async {
    setState(() {
      if (isPdf) {
        _exportingPdf = true;
      } else {
        _exportingExcel = true;
      }
    });

    final provider = widget.provider;
    final eventName = widget.event.name;
    final d = widget.event.date;
    final eventDateLabel =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    try {
      if (isPdf) {
        await ExportService.instance.exportEventGuestsPdf(
          parties: provider.parties,
          eventName: eventName,
          eventDateLabel: eventDateLabel,
        );
      } else {
        await ExportService.instance.exportEventGuestsCsv(
          parties: provider.parties,
          eventName: eventName,
          eventDateLabel: eventDateLabel,
        );
      }
    } catch (_) {
      // Silently swallow — share_plus already handles share cancellation.
    }

    if (!mounted) return;

    setState(() {
      _exportingPdf = false;
      _exportingExcel = false;
    });

    final format = isPdf ? 'PDF' : 'CSV';
    final snackColor = isPdf ? AppColors.error : AppColors.present;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isPdf ? Icons.picture_as_pdf_rounded : Icons.table_chart_rounded,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$format report ready — share sheet opened.',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: snackColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final provider = widget.provider;
    final event = widget.event;
    final breakdown = provider.mealTypeBreakdown;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.10),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ListView(
          controller: ctrl,
          padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad + 16),
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.borderDark : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.info.withValues(alpha: 0.9),
                        AppColors.info,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.download_rounded,
                      size: 20, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export Report',
                        style: AppTypography.titleMedium.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${event.name}  ·  ${event.formattedDate}',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Overview stats ───────────────────────────────────────────
            _ExportStatRow(
              label: 'Total Guests',
              value: '${provider.totalGuestCount}',
              isDark: isDark,
              color: AppColors.vacation,
            ),
            const SizedBox(height: 6),
            _ExportStatRow(
              label: 'Adults',
              value: '${provider.totalAdultCount}',
              isDark: isDark,
              color: AppColors.info,
            ),
            const SizedBox(height: 6),
            _ExportStatRow(
              label: 'Children',
              value: '${provider.totalChildCount}',
              isDark: isDark,
              color: AppColors.warning,
            ),
            const SizedBox(height: 6),
            _ExportStatRow(
              label: 'Veg',
              value: '${provider.totalVegCount}',
              isDark: isDark,
              color: const Color(0xFF4CAF50),
            ),
            const SizedBox(height: 6),
            _ExportStatRow(
              label: 'Non-Veg',
              value: '${provider.totalNonVegCount}',
              isDark: isDark,
              color: const Color(0xFFFF5722),
            ),

            // ── Meal type breakdown ──────────────────────────────────────
            if (event.mealTypes.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'MEAL TYPE BREAKDOWN',
                style: AppTypography.labelSmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.backgroundDark.withValues(alpha: 0.5)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppColors.borderDark.withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Column(
                  children: event.mealTypes.asMap().entries.map((entry) {
                    final i = entry.key;
                    final mt = entry.value;
                    final c = breakdown[mt.id] ??
                        (total: 0, adults: 0, children: 0);
                    final isLast = i == event.mealTypes.length - 1;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Text(mt.emoji,
                                  style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  mt.title,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: isDark
                                        ? AppColors.textPrimaryDark
                                        : AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${c.total} total',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: mt.color,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (c.total > 0)
                                    Text(
                                      '${c.adults}A  ·  ${c.children}C',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: isDark
                                            ? AppColors.textTertiaryDark
                                            : AppColors.textTertiary,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            color: isDark
                                ? AppColors.borderDark.withValues(alpha: 0.3)
                                : AppColors.border.withValues(alpha: 0.6),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 20),
            // ── What's included label ────────────────────────────────────
            Text(
              'EXPORT INCLUDES',
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 10),
            _IncludeTag(label: 'Guest names & party sizes', isDark: isDark),
            const SizedBox(height: 6),
            _IncludeTag(label: 'Meal type per person', isDark: isDark),
            const SizedBox(height: 6),
            _IncludeTag(label: 'Adult / children split', isDark: isDark),
            const SizedBox(height: 6),
            _IncludeTag(label: 'Veg / non-veg aggregate', isDark: isDark),
            const SizedBox(height: 6),
            _IncludeTag(label: 'Attendance status', isDark: isDark),
            const SizedBox(height: 20),

            // ── Export buttons ───────────────────────────────────────────
            _ExportActionButton(
              icon: Icons.picture_as_pdf_rounded,
              title: 'Export as PDF',
              subtitle: 'Formatted report ready to print or share',
              color: AppColors.error,
              isDark: isDark,
              isLoading: _exportingPdf,
              onTap: () => _mockExport(isPdf: true),
            ),
            const SizedBox(height: 10),
            _ExportActionButton(
              icon: Icons.table_chart_rounded,
              title: 'Export as Excel',
              subtitle: 'Spreadsheet with per-person breakdown',
              color: const Color(0xFF16A34A),
              isDark: isDark,
              isLoading: _exportingExcel,
              onTap: () => _mockExport(isPdf: false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Export stat row ────────────────────────────────────────────────────────────

class _ExportStatRow extends StatelessWidget {
  const _ExportStatRow({
    required this.label,
    required this.value,
    required this.isDark,
    required this.color,
  });
  final String label;
  final String value;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

// ── Include tag ────────────────────────────────────────────────────────────────

class _IncludeTag extends StatelessWidget {
  const _IncludeTag({required this.label, required this.isDark});
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_rounded,
            size: 14, color: AppColors.present),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Export action button ───────────────────────────────────────────────────────

class _ExportActionButton extends StatelessWidget {
  const _ExportActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isDark,
    required this.isLoading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isDark;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: color.withValues(alpha: isLoading ? 0.35 : 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  : Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoading ? 'Generating…' : title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    isLoading ? 'Please wait' : subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!isLoading)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// _ExportOption replaced by _ExportActionButton above.
