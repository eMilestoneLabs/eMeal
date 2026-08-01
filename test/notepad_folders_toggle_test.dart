// The Folders toggle must stay reachable in BOTH body branches.
//
// It used to live in the app bar (always visible). Moving it into _buildBody
// broke that: `if (_browsingFolders) return TagFolderGrid(...)` returns BEFORE
// the column holding it, so opening Folders left the grid with no way back
// except the system back gesture. Pinned here because it is a UI-STRUCTURE
// bug — the analyzer and every unit test passed while it was broken.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/notepad/screens/notepad_list_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the toggle is visible in the note list AND in the folder grid',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthProviderScope(
          provider: AuthProvider(),
          child: const NotepadListScreen(),
        ),
      ),
    );
    await tester.pump(); // let the provider load

    // Branch 1 — note list.
    expect(find.text('Folders'), findsOneWidget,
        reason: 'entry point must exist on the notes list');

    await tester.tap(find.text('Folders'));
    await tester.pump();

    // Branch 2 — folder grid. The toggle flips to "Close" and MUST remain on
    // screen; without it the grid is a dead end.
    expect(find.text('Close'), findsOneWidget,
        reason: 'the way back must survive the early-return grid branch');

    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(find.text('Folders'), findsOneWidget, reason: 'and it toggles back');

    // Tear the tree down and drain the provider's autosave debounce so the
    // binding does not report a pending Timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
