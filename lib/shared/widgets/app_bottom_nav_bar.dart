import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Data class representing a single bottom navigation item.
class AppNavBarItem {
  const AppNavBarItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badge,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Optional badge count. Shown as a dot when > 0.
  final int? badge;
}

/// Material 3 styled bottom navigation bar.
///
/// Used by [StudentShell] and [AdminShell] to provide persistent tab navigation.
/// Triggers light haptic feedback on each tap.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.backgroundColor,
  });

  final List<AppNavBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = backgroundColor ??
        (isDark ? AppColors.surfaceDark : AppColors.surface);
    final borderColor = isDark ? AppColors.borderDark : AppColors.border;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = i == currentIndex;
              return Expanded(
                child: _NavItem(
                  item: item,
                  selected: selected,
                  isDark: isDark,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onTap(i);
                  },
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final AppNavBarItem item;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.primary;
    final inactiveColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with optional badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  key: ValueKey(selected),
                  size: 24,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
              // Badge dot
              if ((item.badge ?? 0) > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.absent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: AppTypography.labelSmall.copyWith(
              color: selected ? activeColor : inactiveColor,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal,
            ),
            child: Text(item.label),
          ),
        ],
      ),
    );
  }
}
