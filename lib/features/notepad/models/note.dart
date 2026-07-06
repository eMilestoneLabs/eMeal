import 'package:flutter/material.dart';

/// Filter buckets for the notepad list. `today` / `week` / `checklists` are
/// smart filters computed from note state — nothing extra is persisted.
enum NoteFilter { all, pinned, favorites, today, week, checklists, archived }

/// Sort orders for the notepad list.
enum NoteSort { newest, oldest, lastModified, alphabetical }

/// Home-screen layout: single-column list or two-column masonry grid.
enum NoteLayout { list, grid }

extension NoteSortLabel on NoteSort {
  String get label => switch (this) {
    NoteSort.newest => 'Newest first',
    NoteSort.oldest => 'Oldest first',
    NoteSort.lastModified => 'Last modified',
    NoteSort.alphabetical => 'Alphabetical',
  };
}

extension NoteFilterLabel on NoteFilter {
  String get label => switch (this) {
    NoteFilter.all => 'All',
    NoteFilter.pinned => 'Pinned',
    NoteFilter.favorites => 'Favorites',
    NoteFilter.today => 'Today',
    NoteFilter.week => 'This Week',
    NoteFilter.checklists => 'Checklists',
    NoteFilter.archived => 'Archived',
  };

  /// Small leading glyph for the filter chip rail.
  IconData get icon => switch (this) {
    NoteFilter.all => Icons.grid_view_rounded,
    NoteFilter.pinned => Icons.push_pin_rounded,
    NoteFilter.favorites => Icons.favorite_rounded,
    NoteFilter.today => Icons.today_rounded,
    NoteFilter.week => Icons.date_range_rounded,
    NoteFilter.checklists => Icons.checklist_rounded,
    NoteFilter.archived => Icons.archive_rounded,
  };
}

/// A single checklist row within a checklist-type [Note].
@immutable
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    this.done = false,
  });

  final String id;
  final String text;
  final bool done;

  ChecklistItem copyWith({String? text, bool? done}) =>
      ChecklistItem(id: id, text: text ?? this.text, done: done ?? this.done);

  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'done': done};

  static ChecklistItem? tryFromMap(Map<String, dynamic> map) {
    final id = map['id'];
    if (id is! String || id.isEmpty) return null;
    return ChecklistItem(
      id: id,
      text: (map['text'] as String?) ?? '',
      done: (map['done'] as bool?) ?? false,
    );
  }
}

/// A single personal note.
///
/// Notes are **device-local only** — they are never serialized to any backend
/// API, never logged, and never leave [NotepadRepository]'s on-device store.
/// The model is intentionally immutable; every mutation returns a copy via
/// [copyWith] so the provider can diff and persist deterministically.
///
/// A note is either a **text note** (`body`) or a **checklist** (`isChecklist`
/// + `checklist`). Both kinds share [tags] and an optional local-only
/// [reminderAt] indicator.
@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.favorite = false,
    this.archived = false,
    this.colorId = 0,
    this.isChecklist = false,
    this.checklist = const [],
    this.tags = const [],
    this.reminderAt,
  });

  /// Stable unique id (creation-time based, collision-guarded by the provider).
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;
  final bool favorite;
  final bool archived;

  /// Index into [NotePalette.of] — `0` means the default (uncolored) card.
  final int colorId;

  /// Whether this note renders as a checklist instead of free text.
  final bool isChecklist;
  final List<ChecklistItem> checklist;
  final List<String> tags;

  /// Local-only reminder timestamp. Shown as an indicator on the card/editor;
  /// never leaves the device and never fires a server-side notification.
  final DateTime? reminderAt;

  /// A note with no meaningful content — used to hide empty drafts and to pick
  /// a preview label. Tags/reminder alone do not make a note "non-empty".
  bool get isEmpty {
    if (title.trim().isNotEmpty) return false;
    if (isChecklist) {
      return checklist.every((i) => i.text.trim().isEmpty);
    }
    return body.trim().isEmpty;
  }

  int get checklistDone => checklist.where((i) => i.done).length;
  int get checklistTotal => checklist.length;

  bool get hasReminder => reminderAt != null;

  int get wordCount {
    final words = body.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    return words.length;
  }

  int get characterCount => body.characters.length;

  /// Estimated reading time in minutes (~200 wpm, minimum 1 for any content).
  int get readingMinutes {
    final w = wordCount;
    if (w == 0) return 0;
    return (w / 200).ceil();
  }

  /// Checklist completion ratio in `[0, 1]` (0 for empty checklists).
  double get checklistProgress =>
      checklistTotal == 0 ? 0 : checklistDone / checklistTotal;

  Note copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    bool? pinned,
    bool? favorite,
    bool? archived,
    int? colorId,
    bool? isChecklist,
    List<ChecklistItem>? checklist,
    List<String>? tags,
    DateTime? reminderAt,
    bool clearReminder = false,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      favorite: favorite ?? this.favorite,
      archived: archived ?? this.archived,
      colorId: colorId ?? this.colorId,
      isChecklist: isChecklist ?? this.isChecklist,
      checklist: checklist ?? this.checklist,
      tags: tags ?? this.tags,
      reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'pinned': pinned,
    'favorite': favorite,
    'archived': archived,
    'colorId': colorId,
    'isChecklist': isChecklist,
    'checklist': checklist.map((i) => i.toMap()).toList(),
    'tags': tags,
    'reminderAt': reminderAt?.millisecondsSinceEpoch,
  };

  /// Parses a persisted map. Returns `null` for malformed entries so a single
  /// corrupt record can never crash the whole notepad load. New fields default
  /// gracefully so notes stored by older versions still load.
  static Note? tryFromMap(Map<String, dynamic> map) {
    final id = map['id'];
    if (id is! String || id.isEmpty) return null;
    final createdMs = (map['createdAt'] as num?)?.toInt();
    final updatedMs = (map['updatedAt'] as num?)?.toInt();
    if (createdMs == null || updatedMs == null) return null;

    final rawChecklist = map['checklist'];
    final checklist = <ChecklistItem>[];
    if (rawChecklist is List) {
      for (final e in rawChecklist) {
        if (e is Map<String, dynamic>) {
          final item = ChecklistItem.tryFromMap(e);
          if (item != null) checklist.add(item);
        }
      }
    }

    final rawTags = map['tags'];
    final tags = <String>[];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t is String && t.trim().isNotEmpty) tags.add(t);
      }
    }

    final reminderMs = (map['reminderAt'] as num?)?.toInt();

    return Note(
      id: id,
      title: (map['title'] as String?) ?? '',
      body: (map['body'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
      pinned: (map['pinned'] as bool?) ?? false,
      favorite: (map['favorite'] as bool?) ?? false,
      archived: (map['archived'] as bool?) ?? false,
      colorId: (map['colorId'] as num?)?.toInt() ?? 0,
      isChecklist: (map['isChecklist'] as bool?) ?? false,
      checklist: checklist,
      tags: tags,
      reminderAt:
          reminderMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(reminderMs),
    );
  }
}

/// Soft, theme-aware label colours for note cards.
///
/// Index `0` is the default (no colour) — callers fall back to the surface
/// colour. All other indices resolve to a gentle tint that reads well in both
/// light and dark themes.
abstract final class NotePalette {
  /// Number of selectable colours (including the default at index 0).
  static const int count = 7;

  static const List<Color> _seeds = [
    Color(0x00000000), // 0 default — transparent sentinel
    Color(0xFF4F46E5), // indigo (brand primary)
    Color(0xFF059669), // emerald
    Color(0xFFF59E0B), // amber
    Color(0xFFEF4444), // rose
    Color(0xFF8B5CF6), // violet
    Color(0xFF3B82F6), // sky
  ];

  static Color seed(int colorId) =>
      _seeds[(colorId >= 0 && colorId < _seeds.length) ? colorId : 0];

  /// Card fill for [colorId] under the given [isDark] theme.
  /// Returns `null` for the default colour so the caller uses the surface.
  static Color? cardFill(int colorId, bool isDark) {
    if (colorId <= 0 || colorId >= _seeds.length) return null;
    final s = _seeds[colorId];
    return isDark
        ? Color.alphaBlend(s.withValues(alpha: 0.16), const Color(0xFF1E293B))
        : Color.alphaBlend(s.withValues(alpha: 0.10), const Color(0xFFFFFFFF));
  }

  /// Accent used for the colour dot / left border.
  static Color accent(int colorId, bool isDark) {
    if (colorId <= 0 || colorId >= _seeds.length) {
      return isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    }
    return _seeds[colorId];
  }
}
