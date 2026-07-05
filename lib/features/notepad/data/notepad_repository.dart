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
class NotepadRepository {
  static const String _indexKey = 'notepad.index.v1';
  static const String _notePrefix = 'notepad.note.v1.';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  String _key(String id) => '$_notePrefix$id';

  /// Loads every stored note. Malformed entries are dropped silently and their
  /// ids pruned from the index so they do not accumulate.
  Future<List<Note>> loadAll() async {
    try {
      final prefs = await _prefs;
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
