import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';
import 'package:smart_meal_management/features/notepad/providers/notepad_provider.dart';

/// Live-Test-14 ISSUE-1 — tags behave as FOLDERS: one tag holds many notes.
///
/// Kept deliberately cheap: plain `Container` tiles inside a `GridView`, with
/// `GestureDetector(behavior: opaque)` for taps — no per-tile Material,
/// InkWell, Tooltip or AnimationController. A large tag set therefore scrolls
/// exactly as smoothly as the note list (the same lesson that made the tag
/// chips on `NoteCard` revert to an opaque GestureDetector).

/// Grid of tag folders, each showing its note count.
class TagFolderGrid extends StatelessWidget {
  const TagFolderGrid({
    super.key,
    required this.provider,
    required this.isDark,
    required this.onOpen,
  });

  final NotepadProvider provider;
  final bool isDark;
  final void Function(String tag) onOpen;

  @override
  Widget build(BuildContext context) {
    final counts = provider.tagCounts;
    if (counts.isEmpty) return _EmptyFolders(isDark: isDark);

    final tags = counts.keys.toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.space16,
            AppConstants.space16,
            AppConstants.space16,
            AppConstants.space40 + AppConstants.space40, // clear the FAB
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: AppConstants.space12,
            crossAxisSpacing: AppConstants.space12,
            childAspectRatio: 1.45,
          ),
          itemCount: tags.length,
          itemBuilder: (context, i) {
            final tag = tags[i];
            final n = counts[tag] ?? 0;
            // Stable per-tag accent — the same folder keeps its colour across
            // sessions because it is derived from the tag text itself.
            final accent = tagAccent(tag, isDark);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(tag),
              child: Container(
                padding: const EdgeInsets.all(AppConstants.space12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.09),
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.42 : 0.30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_rounded, size: 26, color: accent),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                accent.withValues(alpha: isDark ? 0.30 : 0.18),
                            borderRadius:
                                BorderRadius.circular(AppConstants.chipRadius),
                          ),
                          child: Text(
                            '$n',
                            style: AppTypography.labelSmall.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '#$tag',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n == 1 ? '1 note' : '$n notes',
                      style: AppTypography.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.folder_open_rounded,
                  size: 34, color: AppColors.primary),
            ),
            const SizedBox(height: AppConstants.space20),
            Text(
              'No tag folders yet',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'Add a tag to any note and it becomes a folder here.\n'
              'One folder can hold as many notes as you like.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                height: 1.6,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "You are inside a folder" banner — names the folder, counts what is in it,
/// and gives one tap back to the grid and one tap to leave.
class OpenFolderHeader extends StatelessWidget {
  const OpenFolderHeader({
    super.key,
    required this.tag,
    required this.count,
    required this.isDark,
    required this.onClose,
    required this.onBrowse,
  });

  final String tag;
  final int count;
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? AppColors.primaryLight : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppConstants.space16, AppConstants.space12, AppConstants.space16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: isDark ? 0.20 : 0.10),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: isDark ? 0.45 : 0.28),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBrowse,
              child: Icon(Icons.folder_rounded, size: 20, color: fg),
            ),
            const SizedBox(width: AppConstants.space8),
            Expanded(
              child: Text(
                '#$tag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  color:
                      isDark ? AppColors.primaryLight : AppColors.primaryDark,
                ),
              ),
            ),
            Text(
              count == 1 ? '1 note' : '$count notes',
              style: AppTypography.labelSmall
                  .copyWith(fontWeight: FontWeight.w600, color: fg),
            ),
            const SizedBox(width: AppConstants.space8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: Icon(Icons.close_rounded, size: 18, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// The stable accent for a tag — the SAME colour wherever that tag appears:
/// its folder tile, the open-folder header, and its chip on a note card.
///
/// Derived from the tag text itself, so a folder keeps its colour across
/// sessions with nothing persisted. Kept here beside [TagFolderGrid] so the
/// grid and the chips can never drift onto different palettes.
Color tagAccent(String tag, bool isDark) =>
    NotePalette.accent((tag.hashCode.abs() % 6) + 1, isDark);
