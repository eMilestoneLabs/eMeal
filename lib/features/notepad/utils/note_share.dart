import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';

/// Plain-text export helpers for a note. Notes are shared **only** through the
/// user-initiated system share sheet / clipboard — never transmitted anywhere
/// automatically.
abstract final class NoteShare {
  /// Renders a note as shareable plain text (title heading + body).
  static String asPlainText(Note note) {
    final title = note.title.trim();
    final body = note.body.trim();
    if (title.isEmpty) return body;
    if (body.isEmpty) return title;
    return '$title\n\n$body';
  }

  /// Opens the OS share sheet (WhatsApp, Email, Telegram, …).
  static Future<void> share(Note note) async {
    final text = asDetailedText(note);
    if (text.isEmpty) return;
    final subject = note.title.trim().isEmpty ? 'Note' : note.title.trim();
    await Share.share(text, subject: subject);
  }

  /// Copies the note's text to the system clipboard.
  static Future<void> copyToClipboard(Note note) async {
    final text = asDetailedText(note);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Renders a checklist as text lines (`☑`/`☐`), or falls back to the plain
  /// body for text notes.
  static String asDetailedText(Note note) {
    if (!note.isChecklist) return asPlainText(note);
    final title = note.title.trim();
    final lines = note.checklist
        .where((i) => i.text.trim().isNotEmpty)
        .map((i) => '${i.done ? '☑' : '☐'} ${i.text.trim()}')
        .join('\n');
    if (title.isEmpty) return lines;
    if (lines.isEmpty) return title;
    return '$title\n\n$lines';
  }

  /// Shares multiple notes as one plain-text document (bulk share).
  static Future<void> shareMany(List<Note> notes) async {
    final blocks =
        notes.map(asDetailedText).where((t) => t.trim().isNotEmpty).toList();
    if (blocks.isEmpty) return;
    final text = blocks.join('\n\n———\n\n');
    await Share.share(text, subject: 'Notes (${blocks.length})');
  }
}
