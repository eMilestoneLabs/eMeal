import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';

/// Friendly empty state shown when a filter/search yields no notes.
class NotepadEmptyState extends StatelessWidget {
  const NotepadEmptyState({
    super.key,
    required this.filter,
    required this.hasQuery,
    this.onCreate,
  });

  final NoteFilter filter;
  final bool hasQuery;
  final VoidCallback? onCreate;

  ({IconData icon, String title, String subtitle}) get _copy {
    if (hasQuery) {
      return (
        icon: Icons.search_off_rounded,
        title: 'No matching notes',
        subtitle: 'Try a different word or clear the search.',
      );
    }
    return switch (filter) {
      NoteFilter.pinned => (
        icon: Icons.push_pin_outlined,
        title: 'No pinned notes',
        subtitle: 'Pin important notes to keep them at the top.',
      ),
      NoteFilter.favorites => (
        icon: Icons.favorite_border_rounded,
        title: 'No favorites yet',
        subtitle: 'Mark notes as favorite for quick access.',
      ),
      NoteFilter.archived => (
        icon: Icons.archive_outlined,
        title: 'Archive is empty',
        subtitle: 'Archived notes are tucked away here.',
      ),
      NoteFilter.all => (
        icon: Icons.edit_note_rounded,
        title: 'Your notepad is empty',
        subtitle:
            'Capture reminders, lists, and ideas — all stored privately '
            'on this device.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = _copy;
    final showCreate =
        onCreate != null && !hasQuery && (filter == NoteFilter.all);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(
                          alpha: isDark ? 0.28 : 0.14,
                        ),
                        AppColors.violet.withValues(
                          alpha: isDark ? 0.22 : 0.10,
                        ),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(c.icon, size: 42, color: AppColors.primary),
                )
                .animate()
                .fadeIn(duration: AppConstants.animNormal)
                .scale(begin: const Offset(0.85, 0.85)),
            const SizedBox(height: AppConstants.space20),
            Text(
              c.title,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              c.subtitle,
              style: AppTypography.bodySmall.copyWith(
                height: 1.5,
                color:
                    isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (showCreate) ...[
              const SizedBox(height: AppConstants.space24),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Create your first note'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.space20,
                    vertical: AppConstants.space12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
