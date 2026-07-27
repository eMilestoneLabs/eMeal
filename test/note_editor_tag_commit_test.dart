// Live-Test-14 ISSUE-1 — RUNTIME validation of tag saving.
//
// Drives the REAL NoteEditorScreen: types into the real tag field and moves
// focus away, exactly as a user does. The field used to commit ONLY on the
// keyboard's "done" action, so tapping the body / pressing back / dismissing
// the keyboard discarded the tag silently — and with no tag there can be no
// folder, which is why "tags don't work" was reported.
//
// A compile-clean analyzer run could never catch this; only pumping the widget
// and moving focus can.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/features/notepad/providers/notepad_provider.dart';
import 'package:smart_meal_management/features/notepad/screens/note_editor_screen.dart';

/// The tag input, located the way the user sees it — by its hint.
final tagField = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Add tag',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(NotepadProvider, String)> openEditor(WidgetTester tester) async {
    final p = NotepadProvider();
    await p.load();
    final note = p.createNote();
    p.editContent(note.id, body: 'hello');

    await tester.pumpWidget(MaterialApp(
      home: NoteEditorScreen(provider: p, noteId: note.id),
    ));
    await tester.pump();
    return (p, note.id);
  }

  testWidgets('the tag field is actually on screen', (tester) async {
    await openEditor(tester);
    expect(tagField, findsOneWidget, reason: 'guards against a vacuous test');
  });

  testWidgets('typing a tag then moving focus away SAVES it', (tester) async {
    final (p, id) = await openEditor(tester);

    await tester.enterText(tagField, 'work');
    await tester.pump();
    // The user taps elsewhere / dismisses the keyboard — no "done" pressed.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(p.noteById(id)!.tags, contains('work'),
        reason: 'a typed tag must survive losing focus');
    // The whole point of the feature: a saved tag IS a folder holding the note.
    // Asserted in the same scenario on purpose — as a separate test it passed
    // even with the fix reverted, because the previous test's screen teardown
    // persisted a tag into the shared SharedPreferences that the next
    // provider then loaded. Same-test assertion cannot be contaminated.
    expect(p.tagCounts['work'], 1);
  });

  testWidgets('pressing done still saves (existing path unchanged)',
      (tester) async {
    final (p, id) = await openEditor(tester);

    await tester.enterText(tagField, 'home');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(p.noteById(id)!.tags, contains('home'));
  });

  testWidgets('an empty tag field adds nothing', (tester) async {
    final (p, id) = await openEditor(tester);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(p.noteById(id)!.tags, isEmpty);
  });

  testWidgets('an EMPTY draft with only a tag is still discarded on close',
      (tester) async {
    // `Note.isEmpty` ignores tags, so a draft carrying nothing but a tag is
    // still an empty draft. Committing the tag on close would issue a
    // `_repo.put` while `_repo.remove` is already in flight for the same note,
    // which can resurrect the deleted draft. The tag must NOT be committed on
    // the delete path.
    SharedPreferences.setMockInitialValues({});
    final p = NotepadProvider();
    await p.load();
    final note = p.createNote(); // no title, no body — an empty draft
    final id = note.id;

    await tester.pumpWidget(MaterialApp(
      home: NoteEditorScreen(provider: p, noteId: id),
    ));
    await tester.pump();

    await tester.enterText(tagField, 'work');
    await tester.pump();

    // Close the editor — dispose runs.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(p.noteById(id), isNull,
        reason: 'the empty draft must be discarded, not kept alive by a tag');
    expect(p.tagCounts, isEmpty,
        reason: 'and it must not leave an orphan folder behind');

    // PERSISTED state is what matters after a restart: a `put` racing the
    // `remove` would leave the draft on disk and it would reappear on reload.
    final reloaded = NotepadProvider();
    await reloaded.load();
    expect(reloaded.noteById(id), isNull,
        reason: 'the discarded draft must not come back after a reload');
    expect(reloaded.tagCounts, isEmpty);
  });
}
