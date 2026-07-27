import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/notepad/data/notepad_repository.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';
import 'package:smart_meal_management/features/notepad/providers/notepad_provider.dart';
import 'package:smart_meal_management/features/notepad/screens/note_editor_screen.dart';
import 'package:smart_meal_management/features/notepad/utils/note_date_format.dart';
import 'package:smart_meal_management/features/notepad/utils/note_share.dart';
import 'package:smart_meal_management/features/notepad/widgets/note_actions_sheet.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/notepad/widgets/note_card.dart';
import 'package:smart_meal_management/features/notepad/widgets/tag_folder_views.dart';
import 'package:smart_meal_management/features/notepad/widgets/notepad_empty_state.dart';
import 'package:smart_meal_management/features/notepad/widgets/notepad_hero.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Personal Notepad — offline, device-local note manager.
///
/// Owns the [NotepadProvider] (created + disposed here) and passes it directly
/// to its widgets and to the pushed editor.
class NotepadListScreen extends StatefulWidget {
  const NotepadListScreen({super.key});

  @override
  State<NotepadListScreen> createState() => _NotepadListScreenState();
}

class _NotepadListScreenState extends State<NotepadListScreen> {
  late final NotepadProvider _provider;
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  bool _providerReady = false;

  // Undo snackbar bookkeeping: capture the messenger once (safe to use in
  // dispose) and force-hide on a deterministic timer so the Undo bar can never
  // linger past its window or follow the user onto other screens.
  ScaffoldMessengerState? _messenger;
  Timer? _undoTimer;
  static const Duration _undoWindow = Duration(seconds: 4);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
    if (_providerReady) return;
    _providerReady = true;
    // Privacy fix: notes are stored per logged-in account, so two users on
    // the same device can never see each other's notepad.
    final userId = AuthProviderScope.of(context).currentUser?.id;
    _provider = NotepadProvider(
      repository: NotepadRepository(namespace: userId),
    );
    _provider.load();
    _searchController.addListener(
      () => _provider.setQuery(_searchController.text),
    );
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    // Never let a "Note deleted — Undo" bar outlive the notepad itself.
    _messenger?.clearSnackBars();
    _searchController.dispose();
    _provider.dispose();
    super.dispose();
  }

  // ── Creation ─────────────────────────────────────────────────────────────────

  Future<void> _createNote({bool checklist = false}) async {
    final note = _provider.createNote(checklist: checklist);
    await _openEditor(note.id, autofocusBody: true);
  }

  /// FAB → choose a text note or a checklist.
  Future<void> _showCreateMenu() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final checklist = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.bottomSheetRadius),
        ),
      ),
      builder:
          (ctx) => SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppConstants.space8),
                ListTile(
                  leading: const Icon(
                    Icons.notes_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('Text note'),
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.checklist_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('Checklist'),
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: AppConstants.space8),
              ],
            ),
          ),
    );
    if (checklist == null || !mounted) return;
    await _createNote(checklist: checklist);
  }

  Future<void> _openEditor(String id, {bool autofocusBody = false}) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder:
            (_) => NoteEditorScreen(
              provider: _provider,
              noteId: id,
              autofocusBody: autofocusBody,
            ),
      ),
    );
    if (result is Note && mounted) _showUndo(result);
  }

  // ── Single-note actions (long-press sheet) ───────────────────────────────────

  Future<void> _openSheet(Note note) async {
    final action = await showNoteActionsSheet(
      context,
      provider: _provider,
      noteId: note.id,
    );
    if (action == null || !mounted) return;
    final live = _provider.noteById(note.id) ?? note;
    await _handleSheetAction(action, live);
  }

  Future<void> _handleSheetAction(NoteSheetAction action, Note note) async {
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
        final when = await pickReminderDateTime(
          context,
          initial: note.reminderAt,
        );
        if (when != null) {
          await _provider.setReminder(note.id, when);
          _snack('Reminder set for ${NoteDateFormat.stamp(when)}');
        }
      case NoteSheetAction.clearReminder:
        await _provider.setReminder(note.id, null);
        _snack('Reminder cleared');
      case NoteSheetAction.convertChecklist:
        await _provider.setChecklistMode(note.id, true);
      case NoteSheetAction.convertText:
        await _provider.setChecklistMode(note.id, false);
      case NoteSheetAction.select:
        _provider.enterSelection(note.id);
      case NoteSheetAction.delete:
        await _deleteWithUndo(note.id);
    }
  }

  // ── Delete + Undo (single) ────────────────────────────────────────────────────

  Future<void> _deleteWithUndo(String id) async {
    final removed = await _provider.delete(id);
    if (removed == null || !mounted) return;
    _showUndo(removed);
  }

  void _showUndo(Note removed) {
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Note deleted'),
        behavior: SnackBarBehavior.floating,
        duration: _undoWindow,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _provider.restore(removed),
        ),
      ),
    );
    _armUndoDismiss(messenger);
  }

  // ── Multi-select bulk actions ─────────────────────────────────────────────────

  void _selectAllVisible() =>
      _provider.selectAll(_provider.visibleNotes.map((n) => n.id));

  Future<void> _bulkShare() async {
    final notes = _provider.selectedNotes();
    if (notes.isEmpty) return;
    await NoteShare.shareMany(notes);
  }

  Future<void> _bulkDelete() async {
    if (_provider.selectedCount == 0) return;
    final removed = await _provider.deleteSelected();
    if (removed.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${removed.length} note${removed.length == 1 ? '' : 's'} deleted',
        ),
        behavior: SnackBarBehavior.floating,
        duration: _undoWindow,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _provider.restoreMany(removed),
        ),
      ),
    );
    _armUndoDismiss(messenger);
  }

  /// Guarantees the Undo bar disappears after [_undoWindow] even in
  /// environments where SnackBar auto-dismiss is suspended (e.g. accessibility
  /// services set `accessibleNavigation`, which makes action snackbars
  /// persistent by default).
  void _armUndoDismiss(ScaffoldMessengerState messenger) {
    _undoTimer?.cancel();
    _undoTimer = Timer(_undoWindow + const Duration(milliseconds: 300), () {
      try {
        messenger.hideCurrentSnackBar();
      } catch (_) {
        // Messenger already disposed — nothing to hide.
      }
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// ISSUE-1 (tags-as-folders): true while the FOLDER GRID is on screen.
  /// Purely a view switch — no provider state, nothing to dispose.
  bool _browsingFolders = false;

  void _toggleFolders() {
    setState(() {
      _browsingFolders = !_browsingFolders;
      if (_browsingFolders) _searching = false;
    });
  }

  /// Open a tag folder: narrow the list and leave the grid.
  void _openFolder(String tag) {
    _provider.openTag(tag);
    setState(() => _browsingFolders = false);
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _searchController.clear();
    });
  }

  /// Live-Test-11 ISSUE-022: tag chips are functional — tapping one opens the
  /// search bar pre-filled with the tag, filtering the list to notes carrying
  /// it (the provider's query already matches tags). Clearing search restores
  /// the full list; no new state machinery needed.
  /// ISSUE-1: tapping a #tag opens that tag's FOLDER — a real, labelled
  /// narrowing with its own header — instead of stuffing the tag into the
  /// search box, where it read as a search and could be typed over.
  void _filterByTag(String tag) => _openFolder(tag);

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.background;

    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        final selecting = _provider.selectionMode;
        return Scaffold(
          backgroundColor: bg,
          appBar: selecting ? _selectionAppBar(isDark) : _buildAppBar(isDark),
          floatingActionButton:
              selecting
                  ? null
                  : FloatingActionButton.extended(
                    onPressed: _showCreateMenu,
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New note'),
                  ),
          body: _buildBody(isDark, selecting),
        );
      },
    );
  }

  Widget _buildBody(bool isDark, bool selecting) {
    if (_provider.isLoading) {
      return const AppListSkeleton(rows: 5, rowHeight: 92);
    }
    if (_browsingFolders && !selecting) {
      return TagFolderGrid(
        provider: _provider,
        isDark: isDark,
        onOpen: _openFolder,
      );
    }
    final notes = _provider.visibleNotes;
    return Column(
      children: [
        if (!selecting && _provider.activeTag != null)
          OpenFolderHeader(
            tag: _provider.activeTag!,
            count: notes.length,
            isDark: isDark,
            onClose: _provider.clearTag,
            onBrowse: _toggleFolders,
          ),
        if (!selecting) _FilterBar(provider: _provider, isDark: isDark),
        Expanded(
          child:
              notes.isEmpty
                  ? NotepadEmptyState(
                    filter: _provider.filter,
                    hasQuery: _provider.query.trim().isNotEmpty,
                    onCreate: _createNote,
                  )
                  : _buildList(notes, isDark, selecting),
        ),
      ],
    );
  }

  /// Premium home header (greeting + live stats). Shown only on the default
  /// "All" view when not searching/selecting so focused views stay compact.
  List<Widget> _heroSection(bool isDark) {
    final user =
        context
            .dependOnInheritedWidgetOfExactType<AuthProviderScope>()
            ?.notifier
            ?.currentUser;
    return [
      Padding(
        padding: const EdgeInsets.only(top: AppConstants.space8),
        child: NotepadHero(isDark: isDark, userName: user?.name),
      ),
      const SizedBox(height: AppConstants.space16),
      NotepadStatsCard(provider: _provider, isDark: isDark),
      const SizedBox(height: AppConstants.space20),
    ];
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    final fg = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title:
          _searching
              ? TextField(
                controller: _searchController,
                autofocus: true,
                style: AppTypography.bodyLarge.copyWith(color: fg),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search notes…',
                  hintStyle: AppTypography.bodyLarge.copyWith(
                    color:
                        isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                  ),
                ),
              )
              : Text(
                'Notepad',
                style: AppTypography.titleLarge.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
      actions: [
        // ISSUE-1 (tags-as-folders): browse tags as folders. Tinted while open
        // or while a folder is active, so the current context is never a guess.
        if (!_searching)
          IconButton(
            tooltip: _browsingFolders ? 'Back to notes' : 'Tag folders',
            icon: Icon(
              _browsingFolders
                  ? Icons.close_rounded
                  : (_provider.activeTag != null
                      ? Icons.folder_rounded
                      : Icons.folder_outlined),
              color: (_browsingFolders || _provider.activeTag != null)
                  ? AppColors.primary
                  : null,
            ),
            onPressed: _toggleFolders,
          ),
        if (!_searching && !_browsingFolders)
          IconButton(
            tooltip:
                _provider.layout == NoteLayout.grid ? 'List view' : 'Grid view',
            icon: Icon(
              _provider.layout == NoteLayout.grid
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_rounded,
            ),
            onPressed: _provider.toggleLayout,
          ),
        if (!_searching)
          IconButton(
            tooltip: 'Select',
            icon: const Icon(Icons.check_box_outlined),
            onPressed: _provider.startSelection,
          ),
        IconButton(
          tooltip: _searching ? 'Close search' : 'Search',
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          onPressed: _toggleSearch,
        ),
        PopupMenuButton<NoteSort>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort_rounded),
          onSelected: _provider.setSort,
          itemBuilder:
              (context) =>
                  NoteSort.values
                      .map(
                        (s) => CheckedPopupMenuItem<NoteSort>(
                          value: s,
                          checked: _provider.sort == s,
                          child: Text(s.label),
                        ),
                      )
                      .toList(),
        ),
      ],
      bottom: _appBarDivider(isDark),
    );
  }

  PreferredSizeWidget _selectionAppBar(bool isDark) {
    final fg = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final count = _provider.selectedCount;
    final hasSelection = count > 0;
    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        tooltip: 'Cancel',
        icon: const Icon(Icons.close_rounded),
        onPressed: _provider.clearSelection,
      ),
      title: Text(
        hasSelection ? '$count selected' : 'Select notes',
        style: AppTypography.titleMedium.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: _selectAllVisible,
        ),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: hasSelection ? _bulkShare : null,
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: hasSelection ? _bulkDelete : null,
        ),
      ],
      bottom: _appBarDivider(isDark),
    );
  }

  PreferredSizeWidget _appBarDivider(bool isDark) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(
        height: 1,
        color: (isDark ? AppColors.borderDark : AppColors.border).withValues(
          alpha: 0.4,
        ),
      ),
    );
  }

  Widget _buildList(List<Note> notes, bool isDark, bool selecting) {
    final grouped = _provider.sort != NoteSort.alphabetical;
    final showHero =
        !selecting &&
        _provider.query.trim().isEmpty &&
        _provider.filter == NoteFilter.all;
    final children = <Widget>[];
    if (showHero) children.addAll(_heroSection(isDark));

    void addCard(Note note) {
      final selected = _provider.isSelected(note.id);
      final card = NoteCard(
        note: note,
        selectionMode: selecting,
        selected: selected,
        onTap:
            selecting
                ? () => _provider.toggleSelection(note.id)
                : () => _openEditor(note.id),
        onLongPress:
            selecting
                ? () => _provider.toggleSelection(note.id)
                : () => _openSheet(note),
        onTogglePin: selecting ? () {} : () => _provider.togglePin(note.id),
        // Live-Test-11 ISSUE-022: tapping a #tag filters the list by that tag
        // through the existing search pipeline (query matches tags).
        onTagTap: selecting ? null : _filterByTag,
      );

      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.space12),
          child:
              selecting
                  // Swipe-to-delete is disabled during selection to avoid gesture
                  // conflict with tap-to-toggle.
                  ? card
                  : Dismissible(
                    key: ValueKey(note.id),
                    direction: DismissDirection.endToStart,
                    background: _swipeBackground(isDark),
                    onDismissed: (_) => _deleteWithUndo(note.id),
                    // Keyed so the entrance plays once per note and never replays
                    // on unrelated rebuilds (pin toggle, filter change, etc.).
                    child: card
                        .animate(key: ValueKey('anim_${note.id}'))
                        .fadeIn(duration: AppConstants.animFast)
                        .slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
                  ),
        ),
      );
    }

    void addDaySections(List<Note> items) {
      final map = NoteDateFormat.groupByDay(items);
      for (final section in NoteDaySection.values) {
        final bucket = map[section];
        if (bucket == null || bucket.isEmpty) continue;
        children.add(_SectionHeader(label: section.label, isDark: isDark));
        bucket.forEach(addCard);
      }
    }

    if (_provider.layout == NoteLayout.grid) {
      // Masonry mode: two balanced columns, pinned rail first. Swipe-to-delete
      // is list-mode only; grid deletes go through the long-press sheet.
      final splitPinned =
          grouped &&
          (_provider.filter == NoteFilter.all ||
              _provider.filter == NoteFilter.favorites);
      if (splitPinned && notes.any((n) => n.pinned)) {
        final pinned = notes.where((n) => n.pinned).toList();
        final rest = notes.where((n) => !n.pinned).toList();
        children.add(_SectionHeader(label: 'Pinned', isDark: isDark));
        children.add(_buildMasonry(pinned, isDark, selecting));
        if (rest.isNotEmpty) {
          children.add(_SectionHeader(label: 'Notes', isDark: isDark));
          children.add(_buildMasonry(rest, isDark, selecting));
        }
      } else {
        children.add(_buildMasonry(notes, isDark, selecting));
      }
    } else if (grouped) {
      final splitPinned =
          _provider.filter == NoteFilter.all ||
          _provider.filter == NoteFilter.favorites;
      if (splitPinned) {
        final pinned = notes.where((n) => n.pinned).toList();
        final rest = notes.where((n) => !n.pinned).toList();
        if (pinned.isNotEmpty) {
          children.add(_SectionHeader(label: 'Pinned', isDark: isDark));
          pinned.forEach(addCard);
        }
        addDaySections(rest);
      } else {
        addDaySections(notes);
      }
    } else {
      notes.forEach(addCard);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.space16,
            AppConstants.space12,
            AppConstants.space16,
            AppConstants.space40 + AppConstants.space40, // clear the FAB
          ),
          children: children,
        ),
      ),
    );
  }

  /// Two-column masonry: cards are dealt to the currently shorter column
  /// using a cheap height estimate, so tall and short notes interleave the
  /// way premium note apps do — no extra layout passes, no new dependency.
  Widget _buildMasonry(List<Note> notes, bool isDark, bool selecting) {
    final left = <Widget>[];
    final right = <Widget>[];
    double leftH = 0, rightH = 0;

    for (final note in notes) {
      final selected = _provider.isSelected(note.id);
      final card = Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.space12),
        child: NoteCard(
              note: note,
              selectionMode: selecting,
              selected: selected,
              onTap:
                  selecting
                      ? () => _provider.toggleSelection(note.id)
                      : () => _openEditor(note.id),
              onLongPress:
                  selecting
                      ? () => _provider.toggleSelection(note.id)
                      : () => _openSheet(note),
              onTogglePin:
                  selecting ? () {} : () => _provider.togglePin(note.id),
              // ISSUE-022: tag chips filter in the grid layout too.
              onTagTap: selecting ? null : _filterByTag,
            )
            .animate(key: ValueKey('anim_${note.id}'))
            .fadeIn(duration: AppConstants.animFast)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
      );
      final h = _estimateCardHeight(note);
      if (leftH <= rightH) {
        left.add(card);
        leftH += h;
      } else {
        right.add(card);
        rightH += h;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        const SizedBox(width: AppConstants.space12),
        Expanded(child: Column(children: right)),
      ],
    );
  }

  /// Rough card-height estimate used only to balance the masonry columns.
  double _estimateCardHeight(Note note) {
    double h = 84; // frame + title + footer
    if (note.isChecklist) {
      final visible = note.checklist.where((i) => i.text.trim().isNotEmpty);
      h += (visible.length > 4 ? 4 : visible.length) * 22;
      if (note.checklistTotal > 0) h += 18; // progress bar
    } else if (note.body.trim().isNotEmpty) {
      final lines = (note.body.trim().length / 26).ceil();
      h += (lines > 4 ? 4 : lines) * 18;
    }
    if (note.tags.isNotEmpty) h += 26;
    return h;
  }

  Widget _swipeBackground(bool isDark) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppConstants.space20),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
    );
  }
}

// ── Filter chips ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.provider, required this.isDark});

  final NotepadProvider provider;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    int countFor(NoteFilter f) => switch (f) {
      NoteFilter.all => provider.totalCount,
      NoteFilter.pinned => provider.pinnedCount,
      NoteFilter.favorites => provider.favoriteCount,
      NoteFilter.today => provider.todayCount,
      NoteFilter.week => provider.weekCount,
      NoteFilter.checklists => provider.checklistCount,
      NoteFilter.archived => provider.archivedCount,
    };

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space16,
          vertical: AppConstants.space8,
        ),
        children:
            NoteFilter.values.map((f) {
              final selected = provider.filter == f;
              final count = countFor(f);
              return Padding(
                padding: const EdgeInsets.only(right: AppConstants.space8),
                child: ChoiceChip(
                  avatar: Icon(
                    f.icon,
                    size: 15,
                    color:
                        selected
                            ? Colors.white
                            : (isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary),
                  ),
                  label: Text(count > 0 ? '${f.label} · $count' : f.label),
                  selected: selected,
                  onSelected: (_) => provider.setFilter(f),
                  showCheckmark: false,
                  labelStyle: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        selected
                            ? Colors.white
                            : (isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary),
                  ),
                  backgroundColor:
                      isDark ? AppColors.surfaceDark : AppColors.surface,
                  selectedColor: AppColors.primary,
                  side: BorderSide(
                    color:
                        selected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.borderDark
                                : AppColors.border),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

// ── Day-section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 4,
        top: AppConstants.space4,
        bottom: AppConstants.space8,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
        ),
      ),
    );
  }
}
