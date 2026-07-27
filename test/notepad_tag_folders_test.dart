import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/features/notepad/providers/notepad_provider.dart';

/// Live-Test-14 ISSUE-1 — tags behave as FOLDERS.
///
/// Pins the folder contract the user specified: a tag holds MANY notes, notes
/// can be created/organised inside a folder, and opening a folder narrows the
/// list without disturbing the existing filter/sort/search pipeline.
void main() {
  setUp(() {
    // The repository persists to SharedPreferences; an in-memory store keeps
    // these tests hermetic and lets the provider load/save exactly as in the app.
    SharedPreferences.setMockInitialValues({});
  });

  Future<NotepadProvider> makeProvider() async {
    final p = NotepadProvider();
    await p.load();
    return p;
  }

  /// Creates a note carrying [tags] with real content (an empty draft is hidden
  /// by design, so every fixture gets a body).
  Future<void> seed(NotepadProvider p, String body, List<String> tags) async {
    final n = p.createNote();
    p.editContent(n.id, body: body);
    for (final t in tags) {
      await p.addTag(n.id, t);
    }
  }

  group('a tag is a folder that holds many notes', () {
    test('tagCounts groups multiple notes under one tag', () async {
      final p = await makeProvider();
      await seed(p, 'first', ['work']);
      await seed(p, 'second', ['work']);
      await seed(p, 'third', ['home']);

      expect(p.tagCounts['work'], 2);
      expect(p.tagCounts['home'], 1);
    });

    test('a note in several tags appears in each folder', () async {
      final p = await makeProvider();
      await seed(p, 'shared', ['work', 'home']);

      expect(p.tagCounts['work'], 1);
      expect(p.tagCounts['home'], 1);
    });

    test('folders group case-insensitively, keeping the first spelling',
        () async {
      final p = await makeProvider();
      await seed(p, 'a', ['Work']);
      await seed(p, 'b', ['work']);

      expect(p.tagCounts.length, 1);
      expect(p.tagCounts['Work'], 2);
    });

    test('an untagged note belongs to no folder but stays visible', () async {
      final p = await makeProvider();
      await seed(p, 'loose', const []);
      await seed(p, 'filed', ['work']);

      // Only the tagged note forms a folder...
      expect(p.tagCounts, {'work': 1});
      // ...and the untagged one is still reachable in the normal list.
      expect(p.visibleNotes.length, 2);
    });
  });

  group('opening a folder narrows the list', () {
    test('only that folder\'s notes are visible', () async {
      final p = await makeProvider();
      await seed(p, 'work note', ['work']);
      await seed(p, 'home note', ['home']);
      expect(p.visibleNotes.length, 2);

      p.openTag('work');

      expect(p.activeTag, 'work');
      expect(p.visibleNotes.length, 1);
      expect(p.visibleNotes.single.body, 'work note');
    });

    test('opening is case-insensitive', () async {
      final p = await makeProvider();
      await seed(p, 'work note', ['Work']);

      p.openTag('work');

      expect(p.visibleNotes.length, 1);
    });

    test('clearTag restores the full list', () async {
      final p = await makeProvider();
      await seed(p, 'work note', ['work']);
      await seed(p, 'home note', ['home']);
      p.openTag('work');

      p.clearTag();

      expect(p.activeTag, isNull);
      expect(p.visibleNotes.length, 2);
    });
  });

  group('organising notes within a folder', () {
    test('a note created while a folder is OPEN is filed into it', () async {
      // Without this the new note carries no tag and vanishes from the folder
      // the moment it is saved — "the folder lost my note".
      final p = await makeProvider();
      p.openTag('work');

      final n = p.createNote();
      p.editContent(n.id, body: 'written inside the folder');

      expect(p.visibleNotes.single.body, 'written inside the folder');
      expect(p.tagCounts['work'], 1);
    });

    test('a note created with NO folder open stays untagged', () async {
      final p = await makeProvider();

      final n = p.createNote();
      p.editContent(n.id, body: 'loose note');

      expect(p.tagCounts, isEmpty);
      expect(p.visibleNotes.single.tags, isEmpty);
    });

    test('adding a tag moves a note INTO a folder', () async {
      final p = await makeProvider();
      await seed(p, 'loose', const []);
      final id = p.visibleNotes.single.id;

      await p.addTag(id, 'work');

      expect(p.tagCounts['work'], 1);
      expect(p.visibleNotes.single.tags, contains('work'));
    });

    test('removing a tag moves a note OUT of a folder', () async {
      final p = await makeProvider();
      await seed(p, 'filed', ['work']);
      final id = p.visibleNotes.single.id;

      await p.removeTag(id, 'work');

      expect(p.tagCounts, isEmpty);
      expect(p.visibleNotes.single.tags, isEmpty);
    });

    test('deleting the last note empties the folder', () async {
      final p = await makeProvider();
      await seed(p, 'only', ['work']);
      final id = p.visibleNotes.single.id;

      await p.delete(id);

      expect(p.tagCounts, isEmpty);
    });
  });

  group('no regression to the existing pipeline', () {
    test('archived notes never appear as folders', () async {
      final p = await makeProvider();
      await seed(p, 'filed', ['work']);
      final id = p.visibleNotes.single.id;

      await p.setArchived(id, true);

      expect(p.tagCounts, isEmpty);
    });

    test('search still narrows WITHIN an open folder', () async {
      final p = await makeProvider();
      await seed(p, 'alpha', ['work']);
      await seed(p, 'beta', ['work']);
      p.openTag('work');

      p.setQuery('alpha');

      expect(p.visibleNotes.length, 1);
      expect(p.visibleNotes.single.body, 'alpha');
    });
  });
}
