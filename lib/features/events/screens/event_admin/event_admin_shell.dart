import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/events/providers/event_admin_provider.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/tabs/event_admin_dashboard_tab.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/tabs/event_admin_guests_tab.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/tabs/event_admin_meals_tab.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/tabs/event_admin_settings_tab.dart';

// ── EventAdminShell ────────────────────────────────────────────────────────────

/// Root shell for the event admin experience.
///
/// Owns two notifiers scoped to the event sub-tree:
///   - [EventAdminProvider] — event data + guest management
///   - [EventThemeNotifier] — independent dark/light toggle for event screens
///
/// Tabs:
///   0  Dashboard  — stats, quick actions, guest preview
///   1  Guests     — full party list, inline editing
///   2  Meals      — dynamic meal type configuration
///   3  Settings   — event details, theme toggle, logout
class EventAdminShell extends StatefulWidget {
  const EventAdminShell({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventAdminShell> createState() => _EventAdminShellState();
}

class _EventAdminShellState extends State<EventAdminShell> {
  late final EventAdminProvider _provider;
  final EventThemeNotifier _themeNotifier = EventThemeNotifier();
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _provider = EventAdminProvider();
    _provider.addListener(_rebuild);
    _provider.loadEvent(widget.eventId);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    _themeNotifier.dispose();
    super.dispose();
  }

  void _onTabTap(int index) {
    if (_currentTab != index) setState(() => _currentTab = index);
  }

  @override
  Widget build(BuildContext context) {
    return EventAdminScope(
      provider: _provider,
      child: EventThemeScope(
        notifier: _themeNotifier,
        child: ValueListenableBuilder<bool>(
          valueListenable: _themeNotifier,
          builder: (_, isDark, _) {
            final theme = isDark ? _darkTheme : _lightTheme;
            return Theme(
              data: theme,
              child: Scaffold(
                backgroundColor: isDark
                    ? AppColors.backgroundDark
                    : AppColors.background,
                body: _provider.isLoading
                    ? _LoadingView(isDark: isDark)
                    : _provider.event == null
                        ? _ErrorView(isDark: isDark)
                        : IndexedStack(
                            index: _currentTab,
                            children: const [
                              EventAdminDashboardTab(),
                              EventAdminGuestsTab(),
                              EventAdminMealsTab(),
                              EventAdminSettingsTab(),
                            ],
                          ),
                bottomNavigationBar: _provider.event == null
                    ? null
                    : _EventAdminBottomNav(
                        currentIndex: _currentTab,
                        onTap: _onTabTap,
                        isDark: isDark,
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  static final ThemeData _darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.vacation,
      surface: AppColors.surfaceDark,
    ),
    scaffoldBackgroundColor: AppColors.backgroundDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardColor: AppColors.surfaceDark,
  );

  static final ThemeData _lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: AppColors.vacation,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardColor: AppColors.surface,
  );
}

// ── EventThemeNotifier ─────────────────────────────────────────────────────────

/// Scoped dark-mode toggle for the event admin sub-tree.
///
/// Independent from the global app theme — toggling this only affects
/// event admin screens, not the rest of the app.
class EventThemeNotifier extends ValueNotifier<bool> {
  EventThemeNotifier() : super(false); // default: light

  void toggle() => value = !value;
}

// ── EventThemeScope ────────────────────────────────────────────────────────────

class EventThemeScope
    extends InheritedNotifier<EventThemeNotifier> {
  const EventThemeScope({
    super.key,
    required EventThemeNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static EventThemeNotifier of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<EventThemeScope>();
    assert(scope != null,
        'EventThemeScope.of() called outside EventAdminShell subtree.');
    return scope!.notifier!;
  }

  static bool isDark(BuildContext context) => of(context).value;
}

// ── EventAdminScope ────────────────────────────────────────────────────────────

class EventAdminScope extends InheritedNotifier<EventAdminProvider> {
  const EventAdminScope({
    super.key,
    required EventAdminProvider provider,
    required super.child,
  }) : super(notifier: provider);

  static EventAdminProvider of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<EventAdminScope>();
    assert(scope != null,
        'EventAdminScope.of() called outside EventAdminShell subtree.');
    return scope!.notifier!;
  }
}

// ── Bottom navigation ──────────────────────────────────────────────────────────

class _EventAdminBottomNav extends StatelessWidget {
  const _EventAdminBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;

  static const _items = [
    (icon: Icons.dashboard_rounded, label: 'Dashboard'),
    (icon: Icons.people_rounded, label: 'Guests'),
    (icon: Icons.restaurant_menu_rounded, label: 'Meals'),
    (icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.6)
                : AppColors.border,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = currentIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.vacation.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          item.icon,
                          size: 22,
                          color: isActive
                              ? AppColors.vacation
                              : isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: AppTypography.labelSmall.copyWith(
                          fontSize: 10,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isActive
                              ? AppColors.vacation
                              : isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ── Loading / error views ──────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.vacation),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading event…',
            style: AppTypography.bodyMedium.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 52,
              color: isDark
                  ? AppColors.textTertiaryDark
                  : AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Event not found',
              style: AppTypography.titleMedium.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This event may have been deleted or expired.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Go Back'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.vacation),
            ),
          ],
        ),
      ),
    );
  }
}
