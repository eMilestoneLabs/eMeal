import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';
import 'package:smart_meal_management/features/notepad/providers/notepad_provider.dart';
import 'package:smart_meal_management/features/notepad/utils/note_date_format.dart';
import 'package:smart_meal_management/features/notepad/utils/note_share.dart';
import 'package:smart_meal_management/features/notepad/widgets/note_actions_sheet.dart';

/// Full-screen note editor with **autosave-while-typing** (no Save button).
///
/// Handles both text notes (title + body) and checklist notes (title + rows).
/// Also edits tags and the local-only reminder. Pops with the deleted [Note]
/// when the user deletes from here so the list can offer an Undo; otherwise
/// pops with `null`.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.provider,
    required this.noteId,
    this.autofocusBody = false,
  });

  final NotepadProvider provider;
  final String noteId;

  /// New notes open with the body/first row focused for instant writing.
  final bool autofocusBody;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  final TextEditingController _tagController = TextEditingController();

  // One controller per checklist row, cached by item id across rebuilds.
  final Map<String, TextEditingController> _itemControllers = {};
  String? _pendingFocusItemId;

  NotepadProvider get _provider => widget.provider;

  @override
  void initState() {
    super.initState();
    final note = _provider.noteById(widget.noteId);
    _titleController = TextEditingController(text: note?.title ?? '');
    _bodyController = TextEditingController(text: note?.body ?? '');
    _titleController.addListener(_onTitleChanged);
    _bodyController.addListener(_onBodyChanged);
  }

  void _onTitleChanged() =>
      _provider.editContent(widget.noteId, title: _titleController.text);

  void _onBodyChanged() =>
      _provider.editContent(widget.noteId, body: _bodyController.text);

  @override
  void dispose() {
    // Either discard an empty draft or persist the final keystroke — never both.
    // delete() cancels the pending debounced save, so there is no late write to
    // race the removal.
    final note = _provider.noteById(widget.noteId);
    if (note != null && note.isEmpty) {
      _provider.delete(widget.noteId);
    } else {
      _provider.flush(widget.noteId);
    }
    _titleController.dispose();
    _bodyController.dispose();
    _tagController.dispose();
    for (final c in _itemControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Checklist controller lifecycle ───────────────────────────────────────────

  void _syncItemControllers(Note note) {
    final ids = note.checklist.map((e) => e.id).toSet();
    final stale = _itemControllers.keys.where((k) => !ids.contains(k)).toList();
    // Defer disposal to after this frame: the removed row's TextField is
    // unmounted during reconcile (after build) and detaches its listener from
    // the controller first, so disposing on the next frame is race-free.
    final removed = <TextEditingController>[];
    for (final k in stale) {
      final c = _itemControllers.remove(k);
      if (c != null) removed.add(c);
    }
    if (removed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in removed) {
          c.dispose();
        }
      });
    }
    for (final item in note.checklist) {
      _itemControllers.putIfAbsent(
        item.id,
        () => TextEditingController(text: item.text),
      );
    }
  }

  void _addChecklistItem() {
    final id = _provider.addChecklistItem(widget.noteId);
    setState(() => _pendingFocusItemId = id);
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _openActions() async {
    final action = await showNoteActionsSheet(
      context,
      provider: _provider,
      noteId: widget.noteId,
    );
    if (action == null || !mounted) return;
    final note = _provider.noteById(widget.noteId);
    if (note == null) return;

    switch (action) {
      case NoteSheetAction.pin:
        await _provider.togglePin(note.id);
      case NoteSheetAction.favorite:
        await _provider.toggleFavorite(note.id);
      case NoteSheetAction.duplicate:
        await _provider.duplicate(note.id);
        _snack('Note duplicated');
      case NoteSheetAction.share:
        await NoteShare.share(note);
      case NoteSheetAction.copy:
        await NoteShare.copyToClipboard(note);
        _snack('Copied to clipboard');
      case NoteSheetAction.archive:
        await _provider.setArchived(note.id, true);
        _snack('Note archived');
      case NoteSheetAction.unarchive:
        await _provider.setArchived(note.id, false);
        _snack('Note restored');
      case NoteSheetAction.setReminder:
        await _pickReminder(note);
      case NoteSheetAction.clearReminder:
        await _provider.setReminder(note.id, null);
        _snack('Reminder cleared');
      case NoteSheetAction.convertChecklist:
        await _provider.setChecklistMode(note.id, true);
        _bodyController.clear();
      case NoteSheetAction.convertText:
        await _provider.setChecklistMode(note.id, false);
        _bodyController.text = _provider.noteById(note.id)?.body ?? '';
      case NoteSheetAction.select:
        // Selection is a list-screen concept; ignored inside the editor.
        break;
      case NoteSheetAction.delete:
        await _confirmDelete(note);
    }
  }

  Future<void> _pickReminder(Note note) async {
    final when = await pickReminderDateTime(context, initial: note.reminderAt);
    if (when == null || !mounted) return;
    await _provider.setReminder(note.id, when);
    _snack('Reminder set for ${NoteDateFormat.stamp(when)}');
  }

  Future<void> _confirmDelete(Note note) async {
    final ok = await _showDeleteDialog();
    if (ok != true || !mounted) return;
    final removed = await _provider.delete(note.id);
    if (mounted) Navigator.of(context).pop(removed);
  }

  Future<bool?> _showDeleteDialog() {
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete note?'),
            content: const Text(
              'This note will be permanently removed from this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.background;

    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        final note = _provider.noteById(widget.noteId);
        if (note == null) {
          return const Scaffold(body: SizedBox.shrink());
        }
        if (note.isChecklist) _syncItemControllers(note);

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: note.pinned ? 'Unpin' : 'Pin',
                icon: Icon(
                  note.pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: note.pinned ? AppColors.primary : null,
                ),
                onPressed: () => _provider.togglePin(note.id),
              ),
              IconButton(
                tooltip: note.favorite ? 'Unfavorite' : 'Favorite',
                icon: Icon(
                  note.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: note.favorite ? AppColors.error : null,
                ),
                onPressed: () => _provider.toggleFavorite(note.id),
              ),
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: _openActions,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.space20,
                      AppConstants.space8,
                      AppConstants.space20,
                      AppConstants.space20,
                    ),
                    children: [
                      _titleField(isDark),
                      if (note.hasReminder) ...[
                        const SizedBox(height: AppConstants.space12),
                        _reminderChip(note, isDark),
                      ],
                      const SizedBox(height: AppConstants.space8),
                      if (note.isChecklist)
                        _checklistEditor(note, isDark)
                      else
                        _bodyField(isDark),
                      const SizedBox(height: AppConstants.space20),
                      _tagsSection(note, isDark),
                    ],
                  ),
                ),
                _EditorFooter(
                  provider: _provider,
                  noteId: widget.noteId,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _titleField(bool isDark) {
    return TextField(
      controller: _titleController,
      textCapitalization: TextCapitalization.sentences,
      style: AppTypography.headlineSmall.copyWith(
        fontWeight: FontWeight.w700,
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
      maxLines: null,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: 'Title',
        hintStyle: AppTypography.headlineSmall.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _bodyField(bool isDark) {
    return TextField(
      controller: _bodyController,
      autofocus: widget.autofocusBody,
      textCapitalization: TextCapitalization.sentences,
      keyboardType: TextInputType.multiline,
      maxLines: null,
      style: AppTypography.bodyLarge.copyWith(
        height: 1.55,
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: 'Start writing…',
        hintStyle: AppTypography.bodyLarge.copyWith(
          color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _checklistEditor(Note note, bool isDark) {
    // Clear the pending-focus marker after this frame so it fires once.
    if (_pendingFocusItemId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingFocusItemId = null;
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...note.checklist.map((item) {
          final controller = _itemControllers[item.id];
          if (controller == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    item.done
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color:
                        item.done
                            ? AppColors.secondary
                            : (isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary),
                  ),
                  onPressed:
                      () => _provider.toggleChecklistItem(note.id, item.id),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: item.id == _pendingFocusItemId,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onChanged:
                        (t) => _provider.editChecklistItemText(
                          note.id,
                          item.id,
                          t,
                        ),
                    onSubmitted: (_) => _addChecklistItem(),
                    style: AppTypography.bodyLarge.copyWith(
                      color:
                          item.done
                              ? (isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiary)
                              : (isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary),
                      decoration: item.done ? TextDecoration.lineThrough : null,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'List item',
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color:
                        isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                  ),
                  onPressed:
                      () => _provider.removeChecklistItem(note.id, item.id),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        InkWell(
          onTap: _addChecklistItem,
          borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Add item',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _reminderChip(Note note, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_active_rounded,
              size: 16,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            Text(
              NoteDateFormat.stamp(note.reminderAt!),
              style: AppTypography.labelMedium.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            InkResponse(
              radius: 16,
              onTap: () => _provider.setReminder(note.id, null),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagsSection(Note note, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TAGS',
          style: AppTypography.labelSmall.copyWith(
            fontSize: 11,
            letterSpacing: 0.9,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: AppConstants.space8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...note.tags.map(
              (t) => Chip(
                label: Text('#$t'),
                labelStyle: AppTypography.labelMedium.copyWith(
                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: AppColors.primary.withValues(
                  alpha: isDark ? 0.18 : 0.10,
                ),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                deleteIconColor:
                    isDark ? AppColors.primaryLight : AppColors.primary,
                onDeleted: () => _provider.removeTag(note.id, t),
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _tagController,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  _provider.addTag(note.id, v);
                  _tagController.clear();
                },
                style: AppTypography.bodyMedium.copyWith(
                  color:
                      isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.add_rounded, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  hintText: 'Add tag',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color:
                        isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.chipRadius,
                    ),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.borderDark : AppColors.border,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.chipRadius,
                    ),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.borderDark : AppColors.border,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Live word / character count + created/edited stamps. Rebuilds independently
/// of the text fields so typing stays smooth.
class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.provider,
    required this.noteId,
    required this.isDark,
  });

  final NotepadProvider provider;
  final String noteId;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: provider,
      builder: (context, _) {
        final note = provider.noteById(noteId);
        if (note == null) return const SizedBox.shrink();
        final style = AppTypography.labelSmall.copyWith(
          fontSize: 11,
          color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
        );
        final metric =
            note.isChecklist
                ? '${note.checklistDone}/${note.checklistTotal} done'
                : '${note.wordCount} words · ${note.characterCount} chars';
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space20,
            vertical: AppConstants.space8,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: (isDark ? AppColors.borderDark : AppColors.border)
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      NoteDateFormat.fullCreated(note.createdAt),
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppConstants.space8),
                  Icon(
                    Icons.cloud_done_rounded,
                    size: 13,
                    color:
                        isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      NoteDateFormat.fullEdited(note.updatedAt),
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(metric, style: style),
            ],
          ),
        );
      },
    );
  }
}
