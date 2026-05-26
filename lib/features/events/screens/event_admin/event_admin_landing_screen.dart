import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/features/events/providers/event_admin_provider.dart';

// ── EventAdminLandingScreen ────────────────────────────────────────────────────

/// Landing screen for event admins.
///
/// Shows the admin's event list. From here they can:
///   - Select an existing event → enter [EventAdminShell]
///   - Create a new event → [EventCreateScreen]
///   - Sign out
class EventAdminLandingScreen extends StatefulWidget {
  const EventAdminLandingScreen({super.key});

  @override
  State<EventAdminLandingScreen> createState() =>
      _EventAdminLandingScreenState();
}

class _EventAdminLandingScreenState extends State<EventAdminLandingScreen> {
  late final EventAdminProvider _provider;
  bool _initDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initDone) {
      _initDone = true;
      _provider = EventAdminProvider();
      _provider.addListener(_rebuild);
      final auth = AuthProviderScope.of(context);
      _provider.loadMyEvents(adminId: auth.currentUser?.id ?? 'admin_event_001');
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    super.dispose();
  }

  void _openEvent(EventModel event) {
    final eventId = event.id;
    context.push('/event-admin/event/$eventId');
  }

  /// Navigates to event creation and reloads the event list on return.
  ///
  /// The create screen uses [context.go] on success (navigating directly to the
  /// event shell) so a stale list only appears when the user later navigates
  /// back to this landing screen. Reloading on pop-back ensures the list is
  /// always fresh regardless of how the user returned.
  Future<void> _navigateToCreate() async {
    await context.push(RouteNames.eventAdminCreate);
    if (!mounted) return;
    final auth = AuthProviderScope.of(context);
    _provider.loadMyEvents(adminId: auth.currentUser?.id ?? 'admin_event_001');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor:
                isDark ? AppColors.surfaceDark : AppColors.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.vacation, Color(0xFFEC4899)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.celebration_rounded,
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('My Events', style: AppTypography.titleLarge),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.logout_rounded,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
                tooltip: 'Sign out',
                onPressed: () async {
                  await AuthProviderScope.of(context).logout();
                },
              ),
            ],
          ),

          if (_provider.isLoadingEvents)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.vacation),
                ),
              ),
            )
          else if (_provider.myEvents.isEmpty)
            SliverFillRemaining(
              child: _EmptyEventsState(
                isDark: isDark,
                onCreateTap: _navigateToCreate,
              ),
            )
          else ...[
            // ── Header row ──────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppConstants.pagePaddingH, 20, AppConstants.pagePaddingH, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_provider.myEvents.length} event${_provider.myEvents.length == 1 ? '' : 's'}',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    _CreateEventButton(
                      onTap: _navigateToCreate,
                    ),
                  ],
                ),
              ),
            ),

            // ── Events list ─────────────────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  AppConstants.pagePaddingH,
                  0,
                  AppConstants.pagePaddingH,
                  MediaQuery.paddingOf(context).bottom + 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final event = _provider.myEvents[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _EventCard(
                        event: event,
                        isDark: isDark,
                        onTap: () => _openEvent(event),
                      ),
                    );
                  },
                  childCount: _provider.myEvents.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Create button ──────────────────────────────────────────────────────────────

class _CreateEventButton extends StatelessWidget {
  const _CreateEventButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.vacation, Color(0xFFEC4899)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.vacation.withValues(alpha: 0.30),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              'New Event',
              style: AppTypography.labelMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Event card ─────────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.isDark,
    required this.onTap,
  });

  final EventModel event;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(
            color: event.status == EventStatus.active
                ? AppColors.vacation.withValues(alpha: 0.35)
                : (isDark
                    ? AppColors.borderDark.withValues(alpha: 0.6)
                    : AppColors.border),
            width: event.status == EventStatus.active ? 1.5 : 1.0,
          ),
          boxShadow: event.status == EventStatus.active
              ? [
                  BoxShadow(
                    color: AppColors.vacation.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type emoji badge
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.vacation.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  event.type.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          event.name,
                          style: AppTypography.titleSmall.copyWith(
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(status: event.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        event.formattedDate,
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.groups_rounded,
                        size: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${event.expectedGuestCount} expected',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Join code chip
                  if (event.joinCode != null)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
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
                    ),
                ],
              ),
            ),
            // Arrow
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyEventsState extends StatelessWidget {
  const _EmptyEventsState({
    required this.isDark,
    required this.onCreateTap,
  });

  final bool isDark;
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.vacation, Color(0xFFEC4899)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.vacation.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.celebration_rounded,
                  size: 38, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              'No events yet',
              style: AppTypography.titleLarge.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Create your first event to start\nmanaging guests and meals.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: onCreateTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.vacation, Color(0xFFEC4899)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.vacation.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Create Event',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
