import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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

  /// Live-Test-14 ISSUE-1: the tag field used to commit ONLY on the keyboard's
  /// "done" action. Typing a tag and then tapping the body, pressing back, or
  /// dismissing the keyboard silently discarded it — so tags looked like they
  /// "never save", and with no tag there can be no folder. Committing on focus
  /// loss too makes the field behave the way every other chip input does.
  final FocusNode _tagFocus = FocusNode();

  // One controller per checklist row, cached by item id across rebuilds.
  final Map<String, TextEditingController> _itemControllers = {};
  String? _pendingFocusItemId;

  /// Bumped when the checklist reaches 100% so the progress ring replays its
  /// celebration animation exactly once per completion.
  int _celebrationTick = 0;

  NotepadProvider get _provider => widget.provider;

  @override
  void initState() {
    super.initState();
    final note = _provider.noteById(widget.noteId);
    _titleController = TextEditingController(text: note?.title ?? '');
    _bodyController = TextEditingController(text: note?.body ?? '');
    _titleController.addListener(_onTitleChanged);
    _bodyController.addListener(_onBodyChanged);
    // Commit a half-typed tag when the field loses focus (see [_tagFocus]).
    _tagFocus.addListener(_onTagFocusChanged);
  }

  void _onTagFocusChanged() {
    if (!_tagFocus.hasFocus) _commitTag();
  }

  /// Saves whatever is in the tag field, if anything. Safe to call repeatedly —
  /// `addTag` trims/normalises and the controller is cleared, so a second call
  /// with an empty field is a no-op.
  void _commitTag() {
    final raw = _tagController.text.trim();
    if (raw.isEmpty) return;
    _provider.addTag(widget.noteId, raw);
    _tagController.clear();
  }

  void _onTitleChanged() =>
      _provider.editContent(widget.noteId, title: _titleController.text);

  void _onBodyChanged() =>
      _provider.editContent(widget.noteId, body: _bodyController.text);

  @override
  void dispose() {
    _tagFocus.removeListener(_onTagFocusChanged);
    // Either discard an empty draft or persist the final keystroke — never both.
    // delete() cancels the pending debounced save, so there is no late write to
    // race the removal.
    final note = _provider.noteById(widget.noteId);
    if (note != null && note.isEmpty) {
      // Deliberately do NOT commit a pending tag here. `Note.isEmpty` ignores
      // tags, so a draft with only a tag is still an empty draft and is
      // discarded — and committing first would issue `_repo.put` while
      // `_repo.remove` is already in flight for the same note, which can
      // resurrect the deleted draft depending on which write lands last.
      _provider.delete(widget.noteId);
    } else {
      // The note survives, so a tag typed but never submitted must not be lost
      // when the screen closes. Commit BEFORE the flush so it is persisted.
      _commitTag();
      _provider.flush(widget.noteId);
    }
    _titleController.dispose();
    _bodyController.dispose();
    _tagController.dispose();
    _tagFocus.dispose();
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

  /// Toggles a checklist row and fires a small celebration the moment the
  /// list transitions to fully complete.
  Future<void> _toggleItem(Note note, ChecklistItem item) async {
    final wasComplete =
        note.checklistTotal > 0 && note.checklistDone == note.checklistTotal;
    await _provider.toggleChecklistItem(note.id, item.id);
    if (!mounted) return;
    final updated = _provider.noteById(note.id);
    if (updated == null) return;
    final nowComplete =
        updated.checklistTotal > 0 &&
        updated.checklistDone == updated.checklistTotal;
    if (nowComplete && !wasComplete) {
      setState(() => _celebrationTick++);
      _snack('All ${updated.checklistTotal} items done — great job! 🎉');
    }
  }

  /// Inserts [text] at the current cursor position of the body field
  /// (replacing any selection). The controller listener autosaves as usual.
  void _insertIntoBody(String text) {
    final value = _bodyController.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    final updated = value.text.replaceRange(start, end, text);
    _bodyController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
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

        // Coloured notes tint the whole canvas so the editor matches the card.
        final canvas = NotePalette.cardFill(note.colorId, isDark) ?? bg;

        return Scaffold(
          backgroundColor: canvas,
          appBar: AppBar(
            backgroundColor: canvas,
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
                      if (note.isChecklist && note.checklistTotal > 0) ...[
                        _checklistProgressHeader(note, isDark),
                        const SizedBox(height: AppConstants.space12),
                      ],
                      if (note.isChecklist)
                        _checklistEditor(note, isDark)
                      else
                        _bodyField(isDark),
                      const SizedBox(height: AppConstants.space20),
                      _tagsSection(note, isDark),
                    ],
                  ),
                ),
                _editorToolbar(note, isDark),
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
                  onPressed: () => _toggleItem(note, item),
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

  /// Animated completion ring + count for checklist notes. Replays a small
  /// celebratory pulse (keyed by [_celebrationTick]) when everything is done.
  Widget _checklistProgressHeader(Note note, bool isDark) {
    final progress = note.checklistProgress;
    final complete = progress >= 1.0;
    final color = complete ? AppColors.secondary : AppColors.primary;

    Widget ring = SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: AppConstants.animNormal,
            curve: Curves.easeOutCubic,
            builder:
                (context, v, _) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 4,
                  backgroundColor: (isDark
                          ? AppColors.borderDark
                          : AppColors.border)
                      .withValues(alpha: 0.5),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
          ),
          complete
              ? Icon(Icons.check_rounded, size: 20, color: color)
              : Text(
                '${(progress * 100).round()}%',
                style: AppTypography.labelSmall.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
        ],
      ),
    );
    if (complete) {
      ring = ring
          .animate(key: ValueKey('celebrate_$_celebrationTick'))
          .scale(
            begin: const Offset(0.7, 0.7),
            end: const Offset(1, 1),
            duration: AppConstants.animNormal,
            curve: Curves.elasticOut,
          );
    }

    return Container(
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          ring,
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complete
                      ? 'All done — beautifully finished! 🎉'
                      : '${note.checklistDone} / ${note.checklistTotal} completed',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color:
                        isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppConstants.space6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: AppConstants.animNormal,
                    curve: Curves.easeOutCubic,
                    builder:
                        (context, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          backgroundColor: (isDark
                                  ? AppColors.borderDark
                                  : AppColors.border)
                              .withValues(alpha: 0.5),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Slim always-visible tool strip above the footer: note colours, insert
  /// date/time (text notes), and text⇄checklist conversion.
  Widget _editorToolbar(Note note, bool isDark) {
    final divider = Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.space8),
      color: (isDark ? AppColors.borderDark : AppColors.border).withValues(
        alpha: 0.6,
      ),
    );

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.space12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.5),
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Colour dots — applied instantly, autosaved by the provider.
              ...List.generate(NotePalette.count, (i) {
                final selected = note.colorId == i;
                final accent = NotePalette.accent(i, isDark);
                return Padding(
                  padding: const EdgeInsets.only(right: AppConstants.space6),
                  child: InkResponse(
                    radius: 16,
                    onTap: () => _provider.setColor(note.id, i),
                    child: AnimatedContainer(
                      duration: AppConstants.animFast,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color:
                            i == 0
                                ? Colors.transparent
                                : accent.withValues(alpha: isDark ? 0.4 : 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? AppColors.primary : accent,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child:
                          selected
                              ? Icon(
                                Icons.check_rounded,
                                size: 12,
                                color:
                                    i == 0
                                        ? AppColors.primary
                                        : (isDark
                                            ? Colors.white
                                            : AppColors.textPrimary),
                              )
                              : null,
                    ),
                  ),
                );
              }),
              divider,
              if (!note.isChecklist) ...[
                IconButton(
                  tooltip: 'Insert date',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.calendar_today_rounded, size: 19),
                  color: AppColors.primary,
                  onPressed:
                      () => _insertIntoBody(
                        NoteDateFormat.dateStamp(DateTime.now()),
                      ),
                ),
                IconButton(
                  tooltip: 'Insert time',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.schedule_rounded, size: 19),
                  color: AppColors.primary,
                  onPressed:
                      () => _insertIntoBody(
                        NoteDateFormat.timeStamp(DateTime.now()),
                      ),
                ),
              ],
              IconButton(
                tooltip:
                    note.isChecklist
                        ? 'Convert to text note'
                        : 'Convert to checklist',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  note.isChecklist
                      ? Icons.notes_rounded
                      : Icons.checklist_rounded,
                  size: 20,
                ),
                color: AppColors.primary,
                onPressed: () async {
                  final toChecklist = !note.isChecklist;
                  await _provider.setChecklistMode(note.id, toChecklist);
                  if (!mounted) return;
                  if (toChecklist) {
                    _bodyController.clear();
                  } else {
                    _bodyController.text =
                        _provider.noteById(note.id)?.body ?? '';
                  }
                },
              ),
            ],
          ),
        ],
      ),
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
                focusNode: _tagFocus,
                textInputAction: TextInputAction.done,
                // Commit on Done AND on focus loss (see [_tagFocus]); the field
                // stays focused after Done so several tags can be added in a row.
                onSubmitted: (_) => _commitTag(),
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
                : note.wordCount == 0
                ? '0 words · 0 chars'
                : '${note.wordCount} words · ${note.characterCount} chars · '
                    '${note.readingMinutes} min read';
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
