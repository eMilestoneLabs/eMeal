import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/utils/responsive_helper.dart';

/// Navigation entry used by [AppResponsiveScaffold]'s desktop side-rail.
class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    this.isSelected = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;
}

/// A responsive scaffold wrapper that adapts layout for mobile, tablet,
/// and desktop without changing the calling widget tree.
///
/// On **mobile / tablet**: standard [Scaffold] with bottom navigation bar.
/// On **desktop**: shell with a 240-px fixed side-nav rail.
class AppResponsiveScaffold extends StatelessWidget {
  const AppResponsiveScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.sideNavItems,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final List<AppNavItem>? sideNavItems;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? AppColors.backgroundDark : AppColors.background);

    if (context.isDesktop && sideNavItems != null) {
      return _DesktopScaffold(
        appBar: appBar,
        body: body,
        sideNavItems: sideNavItems!,
        backgroundColor: bg,
        floatingActionButton: floatingActionButton,
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomNavBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation:
          floatingActionButtonLocation ?? FloatingActionButtonLocation.endFloat,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
    );
  }
}

// ── Desktop shell ─────────────────────────────────────────────────────────────

class _DesktopScaffold extends StatelessWidget {
  const _DesktopScaffold({
    required this.body,
    required this.sideNavItems,
    required this.backgroundColor,
    this.appBar,
    this.floatingActionButton,
  });

  final Widget body;
  final List<AppNavItem> sideNavItems;
  final Color backgroundColor;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Row(
        children: [
          Container(
            width: 240,
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                ...sideNavItems.map((item) => _SideNavTile(item: item)),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _SideNavTile extends StatelessWidget {
  const _SideNavTile({required this.item});

  final AppNavItem item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Icon(
        item.icon,
        color: item.isSelected
            ? AppColors.primary
            : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
      ),
      title: Text(
        item.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: item.isSelected
                  ? AppColors.primary
                  : (isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary),
            ),
      ),
      selected: item.isSelected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: item.onTap,
    );
  }
}
