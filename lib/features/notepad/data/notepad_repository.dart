import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';

/// On-device persistence for the Personal Notepad.
///
/// ## Storage strategy
/// Notes live in [SharedPreferences] (Android: app-private prefs, iOS: the app
/// sandbox `NSUserDefaults`) — an app-isolated location that survives app
/// restarts, device reboots, and logout/login. **No note data is ever sent to
/// a backend, written to logs, or shared with other app modules.**
///
/// Each note is stored under its own key (`notepad.note.v1.<id>`) plus a single
/// membership index (`notepad.index.v1`). Writing one note therefore touches
/// only that note's key + (on create/delete) the small index — autosave stays
/// cheap even with hundreds of notes, instead of re-serialising the whole set
/// on every keystroke.
///
/// All methods fail soft: a corrupt or unreadable record is skipped rather than
/// throwing, so a single bad entry can never break the notepad.
///
/// ## Per-account privacy (bug fix)
/// Keys are namespaced by the logged-in user id (`notepad.u.<uid>.…`) so two
/// accounts using the same device can NEVER see each other's notes. Notes
/// written before namespacing existed (legacy `notepad.index.v1` keys) are
/// migrated once into the namespace of the first account that opens the
/// notepad after the upgrade — the device owner in practice — and the legacy
/// keys are removed so they cannot leak to any later account.
class NotepadRepository {
  NotepadRepository({String? namespace})
      : _ns = (namespace == null || namespace.trim().isEmpty)
            ? null
            : namespace.trim();

  /// Logged-in user id owning this store; `null` = legacy shared store
  /// (kept only as a fallback when no user is available).
  final String? _ns;

  static const String _legacyIndexKey = 'notepad.index.v1';
  static const String _legacyNotePrefix = 'notepad.note.v1.';
  static const String _legacyLayoutKey = 'notepad.layout.v1';

  String get _indexKey =>
      _ns == null ? _legacyIndexKey : 'notepad.u.$_ns.index.v1';
  String get _notePrefix =>
      _ns == null ? _legacyNotePrefix : 'notepad.u.$_ns.note.v1.';
  String get _layoutKey =>
      _ns == null ? _legacyLayoutKey : 'notepad.u.$_ns.layout.v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  String _key(String id) => '$_notePrefix$id';

  /// One-time claim of pre-namespacing notes by the first user store that
  /// loads after the upgrade. Legacy keys are deleted afterwards so no other
  /// account on the device can ever read them again.
  Future<void> _migrateLegacyIfAny(SharedPreferences prefs) async {
    if (_ns == null) return;
    try {
      final legacyIds = prefs.getStringList(_legacyIndexKey);
      if (legacyIds == null) return;
      final ids = prefs.getStringList(_indexKey) ?? <String>[];
      for (final id in legacyIds) {
        final raw = prefs.getString('$_legacyNotePrefix$id');
        if (raw != null) {
          await prefs.setString(_key(id), raw);
          if (!ids.contains(id)) ids.add(id);
        }
        await prefs.remove('$_legacyNotePrefix$id');
      }
      await prefs.setStringList(_indexKey, ids);
      final legacyLayout = prefs.getString(_legacyLayoutKey);
      if (legacyLayout != null && prefs.getString(_layoutKey) == null) {
        await prefs.setString(_layoutKey, legacyLayout);
      }
      await prefs.remove(_legacyLayoutKey);
      await prefs.remove(_legacyIndexKey);
    } catch (_) {
      // Fail soft — worst case the migration retries on the next load.
    }
  }

  /// Loads every stored note. Malformed entries are dropped silently and their
  /// ids pruned from the index so they do not accumulate.
  Future<List<Note>> loadAll() async {
    try {
      final prefs = await _prefs;
      await _migrateLegacyIfAny(prefs);
      final ids = prefs.getStringList(_indexKey) ?? const [];
      if (ids.isEmpty) return [];

      final notes = <Note>[];
      final liveIds = <String>[];
      for (final id in ids) {
        final raw = prefs.getString(_key(id));
        if (raw == null) continue;
        final note = _decode(raw);
        if (note == null) continue;
        notes.add(note);
        liveIds.add(id);
      }
      // Self-heal: prune ids whose payloads were missing/corrupt.
      if (liveIds.length != ids.length) {
        await prefs.setStringList(_indexKey, liveIds);
      }
      return notes;
    } catch (_) {
      return [];
    }
  }

  /// Inserts or updates [note]. Idempotent on the index.
  Future<void> put(Note note) async {
    try {
      final prefs = await _prefs;
      await prefs.setString(_key(note.id), jsonEncode(note.toMap()));
      final ids = prefs.getStringList(_indexKey) ?? <String>[];
      if (!ids.contains(note.id)) {
        ids.add(note.id);
        await prefs.setStringList(_indexKey, ids);
      }
    } catch (_) {
      // Non-fatal: a failed local write must never crash the app.
    }
  }

  /// Permanently removes the note with [id] from the device.
  Future<void> remove(String id) async {
    try {
      final prefs = await _prefs;
      await prefs.remove(_key(id));
      final ids = prefs.getStringList(_indexKey);
      if (ids != null && ids.remove(id)) {
        await prefs.setStringList(_indexKey, ids);
      }
    } catch (_) {
      // Non-fatal.
    }
  }

  /// Restores the saved home layout preference (defaults to grid — the
  /// premium masonry view — when nothing was saved yet).
  Future<NoteLayout> loadLayout() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_layoutKey);
      return raw == NoteLayout.list.name ? NoteLayout.list : NoteLayout.grid;
    } catch (_) {
      return NoteLayout.grid;
    }
  }

  /// Persists the home layout preference.
  Future<void> saveLayout(NoteLayout layout) async {
    try {
      final prefs = await _prefs;
      await prefs.setString(_layoutKey, layout.name);
    } catch (_) {
      // Non-fatal.
    }
  }

  Note? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return Note.tryFromMap(decoded);
    } catch (_) {
      return null;
    }
  }
}
