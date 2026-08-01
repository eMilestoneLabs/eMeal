import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';
import 'package:smart_meal_management/features/notepad/widgets/tag_folder_views.dart';
import 'package:smart_meal_management/features/notepad/utils/note_date_format.dart';

/// A single note preview card — title, content preview (text snippet or
/// checklist rows), colour accent, tags, reminder indicator, and status chips.
/// Supports a multi-select visual state. Kept cheap so a list of hundreds
/// scrolls smoothly.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onLongPress,
    required this.onTogglePin,
    this.selectionMode = false,
    this.selected = false,
    this.onTagTap,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onTogglePin;
  final bool selectionMode;
  final bool selected;

  /// Live-Test-11 ISSUE-022: tapping a tag chip filters the list by that tag
  /// (routed through the existing search pipeline). Null = chips stay static.
  final void Function(String tag)? onTagTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill =
        NotePalette.cardFill(note.colorId, isDark) ??
        (isDark ? AppColors.surfaceDark : AppColors.surface);
    final accent = NotePalette.accent(note.colorId, isDark);
    final hasTitle = note.title.trim().isNotEmpty;

    final borderColor =
        selected
            ? AppColors.primary
            : (note.colorId > 0
                ? accent.withValues(alpha: isDark ? 0.4 : 0.35)
                : (isDark ? AppColors.borderDark : AppColors.border));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: Ink(
          decoration: BoxDecoration(
            color: note.colorId > 0 ? null : fill,
            // Coloured notes get a soft two-stop gradient of their accent so
            // the card reads premium instead of a flat tint.
            gradient:
                note.colorId > 0
                    ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        fill,
                        Color.alphaBlend(
                          accent.withValues(alpha: isDark ? 0.06 : 0.04),
                          fill,
                        ),
                      ],
                    )
                    : null,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
            boxShadow:
                isDark
                    ? null
                    : [
                      BoxShadow(
                        color: (note.colorId > 0 ? accent : Colors.black)
                            .withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        hasTitle ? note.title.trim() : 'Untitled note',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color:
                              hasTitle
                                  ? (isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary)
                                  : (isDark
                                      ? AppColors.textTertiaryDark
                                      : AppColors.textTertiary),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.space6),
                    _trailingControl(isDark),
                  ],
                ),
                _buildPreview(isDark),
                if (note.isChecklist && note.checklistTotal > 0) ...[
                  const SizedBox(height: AppConstants.space8),
                  _progressBar(isDark),
                ],
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.space8),
                  _tagWrap(isDark),
                ],
                const SizedBox(height: AppConstants.space8),
                _footer(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trailingControl(bool isDark) {
    if (selectionMode) {
      return Icon(
        selected
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 20,
        color:
            selected
                ? AppColors.primary
                : (isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary),
      );
    }
    return InkResponse(
      onTap: onTogglePin,
      radius: 18,
      child: Icon(
        note.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
        size: 16,
        color:
            note.pinned
                ? AppColors.primary
                : (isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary),
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    if (note.isChecklist) {
      final visible =
          note.checklist
              .where((i) => i.text.trim().isNotEmpty)
              .take(4)
              .toList();
      if (visible.isEmpty) return const SizedBox.shrink();
      final remaining = note.checklistTotal - visible.length;
      return Padding(
        padding: const EdgeInsets.only(top: AppConstants.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...visible.map(
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      i.done
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 15,
                      color:
                          i.done
                              ? AppColors.secondary
                              : (isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiary),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        i.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          height: 1.3,
                          decoration:
                              i.done ? TextDecoration.lineThrough : null,
                          color:
                              i.done
                                  ? (isDark
                                      ? AppColors.textTertiaryDark
                                      : AppColors.textTertiary)
                                  : (isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+$remaining more',
                  style: AppTypography.labelSmall.copyWith(
                    fontSize: 11,
                    color:
                        isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (note.body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.space6),
      child: Text(
        note.body.trim(),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall.copyWith(
          height: 1.4,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
      ),
    );
  }

  /// Slim animated completion bar for checklist cards — fills as items are
  /// ticked and turns green when everything is done.
  Widget _progressBar(bool isDark) {
    final progress = note.checklistProgress;
    final done = progress >= 1.0;
    final barColor = done ? AppColors.secondary : AppColors.primary;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: AppConstants.animNormal,
              curve: Curves.easeOutCubic,
              builder:
                  (context, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 5,
                    backgroundColor: (isDark
                            ? AppColors.borderDark
                            : AppColors.border)
                        .withValues(alpha: 0.5),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
            ),
          ),
        ),
        const SizedBox(width: AppConstants.space8),
        Text(
          '${(progress * 100).round()}%',
          style: AppTypography.labelSmall.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: barColor,
          ),
        ),
      ],
    );
  }

  Widget _tagWrap(bool isDark) {
    final shown = note.tags.take(3).toList();
    final extra = note.tags.length - shown.length;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        // Live-Test-14 ISSUE-003: tapping a #tag did nothing.
        //
        // Root cause: the GestureDetector kept its DEFAULT
        // `HitTestBehavior.deferToChild` while its child was a `Container` whose
        // only paint is a `decoration`. A RenderDecoratedBox is a proxy box — it
        // never reports a hit for itself — so the chip's padding was entirely
        // transparent to hit-testing and only the glyph run could be hit. Every
        // near-miss tap therefore fell through to the note card's own InkWell
        // underneath and opened the note instead of filtering.
        //
        // Fix = `behavior: HitTestBehavior.opaque`: the whole chip rectangle
        // becomes hit-testable, and because this detector sits DEEPER in the
        // hit-test path than the card's InkWell it is added to the gesture arena
        // first and wins. Vertical padding 2 → 5 gives the row a usable height.
        //
        // Deliberately NOT Material + InkWell + Tooltip: this card is
        // documented as cheap so a list of hundreds scrolls smoothly, and those
        // three would add an ink-features layer, a gesture-owning InkResponse
        // and (worst) a Tooltip AnimationController *per chip, per card*. The
        // opaque flag fixes the same defect with ZERO extra render objects and
        // no new disposable resources — the original design had no splash
        // either, so no affordance is lost.
        // ISSUE-2 polish: the chip wears its tag's OWN accent — the same colour
        // that tag's folder tile and open-folder header use — so a tag is
        // recognisable at a glance and the notepad reads as one system instead
        // of a wall of identical purple pills. Still a plain Container behind an
        // opaque GestureDetector: no Material, no ink, no extra render objects.
        ...shown.map((t) {
          final accent = tagAccent(t, isDark);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTagTap == null ? null : () => onTagTap!(t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(AppConstants.chipRadius),
                border: Border.all(
                  color: accent.withValues(alpha: isDark ? 0.38 : 0.26),
                ),
              ),
              child: Text(
                '#$t',
                style: AppTypography.labelSmall.copyWith(
                  fontSize: 11,
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }),
        if (extra > 0)
          Text(
            '+$extra',
            style: AppTypography.labelSmall.copyWith(
              fontSize: 11,
              color:
                  isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
            ),
          ),
      ],
    );
  }

  Widget _footer(bool isDark) {
    final subtle = isDark ? AppColors.textTertiaryDark : AppColors.textTertiary;
    return Row(
      children: [
        if (note.isChecklist && note.checklistTotal > 0) ...[
          Icon(Icons.checklist_rounded, size: 13, color: subtle),
          const SizedBox(width: 3),
          Text(
            '${note.checklistDone}/${note.checklistTotal}',
            style: AppTypography.labelSmall.copyWith(
              fontSize: 11,
              color: subtle,
            ),
          ),
          const SizedBox(width: AppConstants.space8),
        ],
        Flexible(
          child: Text(
            // Text notes surface word count + reading time next to the stamp
            // (e.g. "8 min ago · 120 words · 1 min read").
            note.isChecklist || note.wordCount == 0
                ? NoteDateFormat.relative(note.updatedAt)
                : '${NoteDateFormat.relative(note.updatedAt)} · '
                    '${note.wordCount} word${note.wordCount == 1 ? '' : 's'} · '
                    '${note.readingMinutes} min read',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              fontSize: 11,
              color: subtle,
            ),
          ),
        ),
        const Spacer(),
        if (note.hasReminder) ...[
          const Icon(
            Icons.notifications_active_rounded,
            size: 13,
            color: AppColors.warning,
          ),
          const SizedBox(width: 3),
          Text(
            NoteDateFormat.relative(note.reminderAt!),
            style: AppTypography.labelSmall.copyWith(
              fontSize: 11,
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (note.favorite)
          const Icon(Icons.favorite_rounded, size: 14, color: AppColors.error),
        if (note.archived) ...[
          const SizedBox(width: 4),
          Icon(Icons.archive_rounded, size: 14, color: subtle),
        ],
      ],
    );
  }
}
