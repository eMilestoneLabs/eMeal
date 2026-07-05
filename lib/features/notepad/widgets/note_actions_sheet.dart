import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';
import 'package:smart_meal_management/features/notepad/providers/notepad_provider.dart';

/// Actions the caller must handle (mutations that pair with a SnackBar / Undo /
/// navigation live in the screen; simple colour changes are applied in-sheet).
enum NoteSheetAction {
  pin,
  favorite,
  archive,
  unarchive,
  duplicate,
  share,
  copy,
  setReminder,
  clearReminder,
  convertChecklist,
  convertText,
  select,
  delete,
}

/// Presents the per-note action sheet and returns the chosen [NoteSheetAction]
/// (or `null` if dismissed). Colour changes are applied directly via
/// [provider] and do not close the sheet.
Future<NoteSheetAction?> showNoteActionsSheet(
  BuildContext context, {
  required NotepadProvider provider,
  required String noteId,
}) {
  return showModalBottomSheet<NoteSheetAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _NoteActionsSheet(provider: provider, noteId: noteId),
  );
}

class _NoteActionsSheet extends StatelessWidget {
  const _NoteActionsSheet({required this.provider, required this.noteId});

  final NotepadProvider provider;
  final String noteId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.bottomSheetRadius),
        ),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: provider,
          builder: (context, _) {
            final note = provider.noteById(noteId);
            if (note == null) {
              // Deleted underneath us — nothing to show.
              return const SizedBox(height: 0);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppConstants.space12),
                _grabber(isDark),
                const SizedBox(height: AppConstants.space16),
                _colorRow(context, note, isDark),
                const SizedBox(height: AppConstants.space8),
                Divider(
                  height: 1,
                  color: (isDark ? AppColors.borderDark : AppColors.border)
                      .withValues(alpha: 0.5),
                ),
                _tile(
                  context,
                  icon:
                      note.pinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                  label: note.pinned ? 'Unpin' : 'Pin to top',
                  result: NoteSheetAction.pin,
                  isDark: isDark,
                ),
                _tile(
                  context,
                  icon:
                      note.favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                  label: note.favorite ? 'Remove favorite' : 'Add to favorites',
                  color: note.favorite ? AppColors.error : null,
                  result: NoteSheetAction.favorite,
                  isDark: isDark,
                ),
                _tile(
                  context,
                  icon: Icons.copy_all_rounded,
                  label: 'Duplicate',
                  result: NoteSheetAction.duplicate,
                  isDark: isDark,
                ),
                _tile(
                  context,
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  result: NoteSheetAction.share,
                  isDark: isDark,
                ),
                _tile(
                  context,
                  icon: Icons.content_copy_rounded,
                  label: 'Copy to clipboard',
                  result: NoteSheetAction.copy,
                  isDark: isDark,
                ),
                _tile(
                  context,
                  icon:
                      note.isChecklist
                          ? Icons.notes_rounded
                          : Icons.checklist_rounded,
                  label:
                      note.isChecklist
                          ? 'Convert to text note'
                          : 'Convert to checklist',
                  result:
                      note.isChecklist
                          ? NoteSheetAction.convertText
                          : NoteSheetAction.convertChecklist,
                  isDark: isDark,
                ),
                _tile(
                  context,
                  icon: Icons.notifications_none_rounded,
                  label: note.hasReminder ? 'Change reminder' : 'Set reminder',
                  result: NoteSheetAction.setReminder,
                  isDark: isDark,
                ),
                if (note.hasReminder)
                  _tile(
                    context,
                    icon: Icons.notifications_off_rounded,
                    label: 'Clear reminder',
                    result: NoteSheetAction.clearReminder,
                    isDark: isDark,
                  ),
                _tile(
                  context,
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Select',
                  result: NoteSheetAction.select,
                  isDark: isDark,
                ),
                _tile(
                  context,
                  icon:
                      note.archived
                          ? Icons.unarchive_rounded
                          : Icons.archive_outlined,
                  label: note.archived ? 'Restore from archive' : 'Archive',
                  result:
                      note.archived
                          ? NoteSheetAction.unarchive
                          : NoteSheetAction.archive,
                  isDark: isDark,
                ),
                _tile(
                  context,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: AppColors.error,
                  result: NoteSheetAction.delete,
                  isDark: isDark,
                ),
                const SizedBox(height: AppConstants.space8),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _grabber(bool isDark) => Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: (isDark ? AppColors.borderStrongDark : AppColors.borderStrong),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _colorRow(BuildContext context, Note note, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.space16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(NotePalette.count, (i) {
          final selected = note.colorId == i;
          final accent = NotePalette.accent(i, isDark);
          final isDefault = i == 0;
          return GestureDetector(
            onTap: () => provider.setColor(note.id, i),
            child: AnimatedContainer(
              duration: AppConstants.animFast,
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color:
                    isDefault
                        ? (isDark
                            ? AppColors.surfaceVariantDark
                            : AppColors.surfaceVariant)
                        : accent.withValues(alpha: isDark ? 0.35 : 0.22),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      selected
                          ? AppColors.primary
                          : (isDark ? AppColors.borderDark : AppColors.border),
                  width: selected ? 2 : 1,
                ),
              ),
              child:
                  isDefault
                      ? Icon(
                        Icons.format_color_reset_rounded,
                        size: 16,
                        color:
                            isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary,
                      )
                      : (selected
                          ? Icon(Icons.check_rounded, size: 16, color: accent)
                          : null),
            ),
          );
        }),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required NoteSheetAction result,
    required bool isDark,
    Color? color,
  }) {
    final fg =
        color ?? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary);
    return ListTile(
      leading: Icon(icon, size: 22, color: color ?? AppColors.primary),
      title: Text(
        label,
        style: AppTypography.bodyMedium.copyWith(
          color: fg,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () => Navigator.of(context).pop(result),
      dense: true,
    );
  }
}

/// Prompts for a reminder date then time. Returns the chosen [DateTime], or
/// `null` if the user cancelled either step. Local-only — this just captures
/// the timestamp; the value is stored on-device and shown as an indicator.
Future<DateTime?> pickReminderDateTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final base = initial ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: base.isBefore(now) ? now : base,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
