import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/features/notepad/data/notepad_repository.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';

/// State manager for the Personal Notepad.
///
/// Owns the in-memory note list and all derived views (filter / search / sort).
/// Mutations update memory immediately (so the UI is instant) and persist to
/// [NotepadRepository] — content edits are **debounced** so autosave-while-
/// typing writes at most once per [_autosaveDebounce] instead of per keystroke.
///
/// This is a plain [ChangeNotifier]; the list screen owns one instance and
/// passes it directly to its widgets and to the pushed editor.
class NotepadProvider extends ChangeNotifier {
  NotepadProvider({NotepadRepository? repository, Duration? autosaveDebounce})
    : _repo = repository ?? NotepadRepository(),
      _autosaveDebounce = autosaveDebounce ?? const Duration(milliseconds: 600);

  final NotepadRepository _repo;
  final Duration _autosaveDebounce;

  // ── State ──────────────────────────────────────────────────────────────────
  final Map<String, Note> _notes = {};
  final Map<String, Timer> _pendingSaves = {};
  bool _loading = true;
  bool _disposed = false;

  NoteFilter _filter = NoteFilter.all;
  NoteSort _sort = NoteSort.lastModified;
  NoteLayout _layout = NoteLayout.grid;
  String _query = '';

  // Multi-select state.
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  // ── Getters ────────────────────────────────────────────────────────────────
  bool get isLoading => _loading;
  NoteFilter get filter => _filter;
  NoteSort get sort => _sort;
  NoteLayout get layout => _layout;
  String get query => _query;

  int get totalCount => _notes.values.where((n) => !n.archived).length;
  int get pinnedCount =>
      _notes.values.where((n) => n.pinned && !n.archived).length;
  int get favoriteCount =>
      _notes.values.where((n) => n.favorite && !n.archived).length;
  int get archivedCount => _notes.values.where((n) => n.archived).length;
  int get checklistCount =>
      _notes.values.where((n) => n.isChecklist && !n.archived).length;
  int get todayCount =>
      _notes.values.where((n) => !n.archived && _isToday(n.updatedAt)).length;
  int get weekCount =>
      _notes.values
          .where((n) => !n.archived && _isWithinWeek(n.updatedAt))
          .length;

  /// Sum of open (not-done) checklist rows across active checklists — the
  /// "things left to do" figure for the home stats card.
  int get openChecklistItems => _notes.values
      .where((n) => n.isChecklist && !n.archived)
      .fold(0, (sum, n) => sum + (n.checklistTotal - n.checklistDone));

  /// Most recent edit across active notes (null when the pad is empty).
  DateTime? get lastEditedAt {
    DateTime? latest;
    for (final n in _notes.values) {
      if (n.archived || n.isEmpty) continue;
      if (latest == null || n.updatedAt.isAfter(latest)) latest = n.updatedAt;
    }
    return latest;
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  static bool _isWithinWeek(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    return diff >= 0 && diff < 7;
  }

  /// Live snapshot of a single note (or `null` if it was deleted elsewhere).
  Note? noteById(String id) => _notes[id];

  // ── Multi-select getters ─────────────────────────────────────────────────────
  bool get selectionMode => _selectionMode;
  int get selectedCount => _selectedIds.length;
  bool isSelected(String id) => _selectedIds.contains(id);

  /// The list to render, after filter + search + sort. Pinned notes float to
  /// the top of every non-archived, unsorted-by-name view.
  List<Note> get visibleNotes {
    final q = _query.trim().toLowerCase();
    final list =
        _notes.values.where((n) {
          // Filter bucket.
          switch (_filter) {
            case NoteFilter.all:
              if (n.archived) return false;
              break;
            case NoteFilter.pinned:
              if (n.archived || !n.pinned) return false;
              break;
            case NoteFilter.favorites:
              if (n.archived || !n.favorite) return false;
              break;
            case NoteFilter.today:
              if (n.archived || !_isToday(n.updatedAt)) return false;
              break;
            case NoteFilter.week:
              if (n.archived || !_isWithinWeek(n.updatedAt)) return false;
              break;
            case NoteFilter.checklists:
              if (n.archived || !n.isChecklist) return false;
              break;
            case NoteFilter.archived:
              if (!n.archived) return false;
              break;
          }
          // Search over title, body, checklist rows, and tags.
          if (q.isNotEmpty) {
            final match =
                n.title.toLowerCase().contains(q) ||
                n.body.toLowerCase().contains(q) ||
                n.checklist.any((i) => i.text.toLowerCase().contains(q)) ||
                n.tags.any((t) => t.toLowerCase().contains(q));
            if (!match) return false;
          }
          // Hide never-touched empty drafts from the list (they still persist so an
          // in-progress editor is safe; they simply don't clutter the grid).
          if (n.isEmpty) return false;
          return true;
        }).toList();

    int byRecency(Note a, Note b) => b.updatedAt.compareTo(a.updatedAt);

    list.sort((a, b) {
      // Pinned always first (except in alphabetical + archived views where the
      // explicit sort wins for predictability).
      if (_filter != NoteFilter.archived && _sort != NoteSort.alphabetical) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      }
      switch (_sort) {
        case NoteSort.newest:
          return b.createdAt.compareTo(a.createdAt);
        case NoteSort.oldest:
          return a.createdAt.compareTo(b.createdAt);
        case NoteSort.lastModified:
          return byRecency(a, b);
        case NoteSort.alphabetical:
          final at = a.title.trim().isEmpty ? a.body : a.title;
          final bt = b.title.trim().isEmpty ? b.body : b.title;
          final cmp = at.toLowerCase().compareTo(bt.toLowerCase());
          return cmp != 0 ? cmp : byRecency(a, b);
      }
    });
    return list;
  }

  // ── Loading ────────────────────────────────────────────────────────────────
  Future<void> load() async {
    final loaded = await _repo.loadAll();
    final layout = await _repo.loadLayout();
    if (_disposed) return;
    _notes
      ..clear()
      ..addEntries(loaded.map((n) => MapEntry(n.id, n)));
    _layout = layout;
    _loading = false;
    _safeNotify();
    // Re-assert device alarms for every future reminder (idempotent: the same
    // note always maps to the same notification id, so this replaces rather
    // than duplicates). Covers app reinstalls and reminder toggles elsewhere.
    for (final n in loaded) {
      final at = n.reminderAt;
      if (at != null && at.isAfter(DateTime.now())) {
        _syncReminderAlarm(n);
      }
    }
  }

  // ── Query / filter / sort ───────────────────────────────────────────────────
  void setFilter(NoteFilter value) {
    if (_filter == value) return;
    _filter = value;
    _safeNotify();
  }

  void setSort(NoteSort value) {
    if (_sort == value) return;
    _sort = value;
    _safeNotify();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _safeNotify();
  }

  /// Toggles between list and masonry layouts; persisted across sessions.
  void toggleLayout() {
    _layout = _layout == NoteLayout.grid ? NoteLayout.list : NoteLayout.grid;
    _safeNotify();
    _repo.saveLayout(_layout);
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────────

  /// Creates a fresh, empty note and returns it so the caller can open the
  /// editor. Not persisted until the first content edit (avoids empty-note spam
  /// if the user backs out immediately).
  Note createNote({bool checklist = false}) {
    final now = DateTime.now();
    final note = Note(
      id: _newId(),
      title: '',
      body: '',
      createdAt: now,
      updatedAt: now,
      isChecklist: checklist,
      // A brand-new checklist starts with one empty row to write into.
      checklist: checklist ? [ChecklistItem(id: _newId(), text: '')] : const [],
    );
    _notes[note.id] = note;
    // No notify: an empty draft is not shown in the list yet.
    return note;
  }

  /// Applies a content edit and schedules a debounced save. Safe to call on
  /// every keystroke.
  void editContent(String id, {String? title, String? body}) {
    final current = _notes[id];
    if (current == null) return;
    final updated = current.copyWith(
      title: title,
      body: body,
      updatedAt: DateTime.now(),
    );
    _notes[id] = updated;
    _scheduleSave(updated);
    _safeNotify();
  }

  Future<void> togglePin(String id) =>
      _mutate(id, (n) => n.copyWith(pinned: !n.pinned, updatedAt: n.updatedAt));

  Future<void> toggleFavorite(String id) => _mutate(
    id,
    (n) => n.copyWith(favorite: !n.favorite, updatedAt: n.updatedAt),
  );

  Future<void> setColor(String id, int colorId) =>
      _mutate(id, (n) => n.copyWith(colorId: colorId, updatedAt: n.updatedAt));

  /// Archives (or restores) a note. Archiving also clears the pin so it leaves
  /// the pinned rail cleanly.
  Future<void> setArchived(String id, bool archived) => _mutate(
    id,
    (n) => n.copyWith(
      archived: archived,
      pinned: archived ? false : n.pinned,
      updatedAt: DateTime.now(),
    ),
  );

  /// Duplicates a note as a new independent copy and returns it.
  Future<Note?> duplicate(String id) async {
    final src = _notes[id];
    if (src == null) return null;
    final now = DateTime.now();
    final copy = Note(
      id: _newId(),
      title: src.title.trim().isEmpty ? '' : '${src.title} (copy)',
      body: src.body,
      createdAt: now,
      updatedAt: now,
      favorite: src.favorite,
      colorId: src.colorId,
    );
    _notes[copy.id] = copy;
    _safeNotify();
    await _repo.put(copy);
    return copy;
  }

  /// Permanently deletes a note. Returns the removed [Note] so the caller can
  /// offer an Undo (via [restore]).
  Future<Note?> delete(String id) async {
    _pendingSaves.remove(id)?.cancel();
    final removed = _notes.remove(id);
    if (removed == null) return null;
    if (removed.hasReminder) _cancelReminderAlarm(id);
    _safeNotify();
    await _repo.remove(id);
    return removed;
  }

  /// Re-inserts a previously deleted note (Undo).
  Future<void> restore(Note note) async {
    _notes[note.id] = note;
    _safeNotify();
    await _repo.put(note);
    if (note.hasReminder) _syncReminderAlarm(note);
  }

  /// Flushes any pending debounced save for [id] immediately (call on editor
  /// close / app pause so the latest keystroke is never lost).
  Future<void> flush(String id) async {
    final timer = _pendingSaves.remove(id);
    if (timer == null) return;
    timer.cancel();
    final note = _notes[id];
    if (note != null) await _repo.put(note);
  }

  // ── Checklist ────────────────────────────────────────────────────────────────

  /// Flips a text note into a checklist, seeding rows from its body lines (or
  /// vice-versa, merging rows back into the body). Persisted immediately.
  Future<void> setChecklistMode(String id, bool asChecklist) =>
      _mutate(id, (n) {
        if (n.isChecklist == asChecklist) return n;
        if (asChecklist) {
          final seed =
              n.body
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty)
                  .map((l) => ChecklistItem(id: _newId(), text: l.trim()))
                  .toList();
          return n.copyWith(
            isChecklist: true,
            checklist:
                seed.isEmpty ? [ChecklistItem(id: _newId(), text: '')] : seed,
            body: '',
            updatedAt: DateTime.now(),
          );
        }
        final merged = n.checklist
            .where((i) => i.text.trim().isNotEmpty)
            .map((i) => i.text.trim())
            .join('\n');
        return n.copyWith(
          isChecklist: false,
          checklist: const [],
          body: merged,
          updatedAt: DateTime.now(),
        );
      });

  /// Adds a new (optionally pre-filled) checklist row and returns its id so the
  /// editor can focus it. Debounced save.
  String addChecklistItem(String id, {String text = ''}) {
    final itemId = _newId();
    final note = _notes[id];
    if (note == null) return itemId;
    final updated = note.copyWith(
      checklist: [...note.checklist, ChecklistItem(id: itemId, text: text)],
      updatedAt: DateTime.now(),
    );
    _notes[id] = updated;
    _scheduleSave(updated);
    _safeNotify();
    return itemId;
  }

  /// Edits a checklist row's text (debounced — safe per keystroke).
  void editChecklistItemText(String noteId, String itemId, String text) {
    final note = _notes[noteId];
    if (note == null) return;
    final updated = note.copyWith(
      checklist:
          note.checklist
              .map((i) => i.id == itemId ? i.copyWith(text: text) : i)
              .toList(),
      updatedAt: DateTime.now(),
    );
    _notes[noteId] = updated;
    _scheduleSave(updated);
    _safeNotify();
  }

  Future<void> toggleChecklistItem(String noteId, String itemId) => _mutate(
    noteId,
    (n) => n.copyWith(
      checklist:
          n.checklist
              .map((i) => i.id == itemId ? i.copyWith(done: !i.done) : i)
              .toList(),
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> removeChecklistItem(String noteId, String itemId) => _mutate(
    noteId,
    (n) => n.copyWith(
      checklist: n.checklist.where((i) => i.id != itemId).toList(),
      updatedAt: DateTime.now(),
    ),
  );

  // ── Tags ─────────────────────────────────────────────────────────────────────

  Future<void> addTag(String id, String rawTag) {
    final tag = rawTag.trim();
    if (tag.isEmpty) return Future.value();
    return _mutate(id, (n) {
      final exists = n.tags.any((t) => t.toLowerCase() == tag.toLowerCase());
      if (exists) return n;
      return n.copyWith(tags: [...n.tags, tag], updatedAt: n.updatedAt);
    });
  }

  Future<void> removeTag(String id, String tag) => _mutate(
    id,
    (n) => n.copyWith(
      tags: n.tags.where((t) => t != tag).toList(),
      updatedAt: n.updatedAt,
    ),
  );

  // ── Reminder (persisted flag + real device notification) ────────────────────

  Future<void> setReminder(String id, DateTime? when) async {
    await _mutate(
      id,
      (n) =>
          when == null
              ? n.copyWith(clearReminder: true, updatedAt: n.updatedAt)
              : n.copyWith(reminderAt: when, updatedAt: n.updatedAt),
    );
    final note = _notes[id];
    if (note != null) _syncReminderAlarm(note);
  }

  /// Aligns the device alarm with [note]'s current reminder state. Fail-soft:
  /// notification problems never break the notepad itself.
  void _syncReminderAlarm(Note note) {
    try {
      final at = note.reminderAt;
      if (at != null && at.isAfter(DateTime.now())) {
        NotificationService.instance.scheduleNoteReminder(
          noteId: note.id,
          title: note.title,
          when: at,
        );
      } else {
        NotificationService.instance.cancelNoteReminder(note.id);
      }
    } catch (_) {
      // Never let scheduling issues surface as notepad errors.
    }
  }

  void _cancelReminderAlarm(String noteId) {
    try {
      NotificationService.instance.cancelNoteReminder(noteId);
    } catch (_) {
      // Fail soft.
    }
  }

  // ── Multi-select ─────────────────────────────────────────────────────────────

  /// Enters selection mode with nothing selected yet (app-bar "Select" entry).
  void startSelection() {
    if (_selectionMode) return;
    _selectionMode = true;
    _selectedIds.clear();
    _safeNotify();
  }

  void enterSelection(String id) {
    _selectionMode = true;
    _selectedIds
      ..clear()
      ..add(id);
    _safeNotify();
  }

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    if (_selectedIds.isEmpty) _selectionMode = false;
    _safeNotify();
  }

  void selectAll(Iterable<String> ids) {
    _selectionMode = true;
    _selectedIds.addAll(ids);
    _safeNotify();
  }

  void clearSelection() {
    if (!_selectionMode && _selectedIds.isEmpty) return;
    _selectionMode = false;
    _selectedIds.clear();
    _safeNotify();
  }

  /// Live [Note]s currently selected (skips any deleted underneath).
  List<Note> selectedNotes() =>
      _selectedIds.map((id) => _notes[id]).whereType<Note>().toList();

  /// Bulk-deletes the current selection and returns the removed notes so the
  /// caller can offer a single Undo. Clears selection mode.
  Future<List<Note>> deleteSelected() async {
    final removed = <Note>[];
    for (final id in _selectedIds.toList()) {
      _pendingSaves.remove(id)?.cancel();
      final note = _notes.remove(id);
      if (note != null) {
        removed.add(note);
        if (note.hasReminder) _cancelReminderAlarm(id);
      }
    }
    _selectedIds.clear();
    _selectionMode = false;
    _safeNotify();
    for (final n in removed) {
      await _repo.remove(n.id);
    }
    return removed;
  }

  /// Re-inserts a batch of previously deleted notes (bulk Undo).
  Future<void> restoreMany(List<Note> notes) async {
    for (final n in notes) {
      _notes[n.id] = n;
    }
    _safeNotify();
    for (final n in notes) {
      await _repo.put(n);
      if (n.hasReminder) _syncReminderAlarm(n);
    }
  }

  // ── Internals ────────────────────────────────────────────────────────────────

  Future<void> _mutate(String id, Note Function(Note) transform) async {
    final current = _notes[id];
    if (current == null) return;
    final updated = transform(current);
    _notes[id] = updated;
    _safeNotify();
    await _repo.put(updated);
  }

  void _scheduleSave(Note note) {
    _pendingSaves[note.id]?.cancel();
    _pendingSaves[note.id] = Timer(_autosaveDebounce, () async {
      _pendingSaves.remove(note.id);
      final latest = _notes[note.id];
      if (latest != null) await _repo.put(latest);
    });
  }

  String _newId() {
    // Monotonic-ish: epoch micros + counter guards against same-instant creates.
    final base = DateTime.now().microsecondsSinceEpoch;
    return 'n_${base}_${_idCounter++}';
  }

  int _idCounter = 0;

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _pendingSaves.values) {
      t.cancel();
    }
    _pendingSaves.clear();
    super.dispose();
  }
}
