// Issues_Live_Test_16 — widget-level RUNTIME checks (pumped, tapped, no
// crash): ISSUE-4 guest settings sheet and ISSUE-10 quantity stepper.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/features/admin/meals/widgets/guest_config_sheet.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/widgets/preference_group_selector.dart';
import 'package:smart_meal_management/shared/widgets/saved_choice_line.dart';

void main() {
  // ── ISSUE-4 ────────────────────────────────────────────────────────────
  testWidgets(
      'guest sheet opens for a group STORED with the retired adult/child mode '
      '(no dropdown assertion), shows the capped value, no adult/child fields',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final legacy = GroupGuestConfig.fromJson({
      'guestAttendanceEnabled': true,
      'guestPricingMode': 'perGuestPrice',
      'maxGuestsPerMemberPerMeal': 10,
      'guestAdultPrice': 80,
      'guestChildPrice': 40,
    });
    GroupGuestConfig? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => saved = await showGuestConfigSheet(ctx,
                config: legacy, pricingEnabled: true),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Same as member price'), findsOneWidget);
    expect(find.textContaining('adult/child'), findsNothing);
    expect(find.text('Adult price (₹)'), findsNothing);
    expect(find.text('5'), findsWidgets); // capped from the stored 10

    // Typing above the ceiling is clamped on save.
    await tester.enterText(find.byType(TextField).first, '9');
    // The sheet scrolls (measured: 216 px of range; Save 962 → 746 on an
    // 800-tall screen). Scroll the sheet's own VERTICAL scroller to its end —
    // a drag gesture would be captured by the focused text field.
    // Keyboard "Done" first — a still-focused field keeps pulling the sheet
    // back to itself (Flutter's caret-visibility behaviour).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final sheetScroll = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) =>
            s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0);
    sheetScroll.position.jumpTo(sheetScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save guest settings'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.maxGuestsPerMemberPerMeal, 5);
    expect(saved!.guestPricingMode, 'sameAsMember');
    // Stored adult/child values round-trip untouched (no column rewritten).
    expect(saved!.guestAdultPrice, 80);
    expect(saved!.guestChildPrice, 40);
  });

  // ── ISSUE-10 ───────────────────────────────────────────────────────────
  testWidgets('− / + step the quantity and NEVER deselect the option',
      (tester) async {
    const group = PreferenceGroupModel(
      id: 'pg1',
      label: 'Option 1',
      quantityEnabled: true,
      options: [
        PreferenceOptionModel(key: 'pareta', label: 'Pareta', minQty: 1, maxQty: 4),
        PreferenceOptionModel(key: 'roti', label: 'Roti', minQty: 1, maxQty: 4),
      ],
    );
    List<PreferenceSelection> last = const [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PreferenceGroupSelector(
          groups: [group],
          initialSelections: const [
            PreferenceSelection(groupId: 'pg1', optionKey: 'pareta', quantity: 2),
          ],
          onChanged: (s, _, _) => last = s,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('×2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('×3'), findsOneWidget);
    expect(last.single.optionKey, 'pareta');
    expect(last.single.quantity, 3);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('×2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('×1'), findsOneWidget);
    // Tapping − at the minimum is swallowed: still selected, still ×1.
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(find.text('×1'), findsOneWidget);
    expect(last.single.optionKey, 'pareta');
    expect(tester.takeException(), isNull);
  });

  // ── ISSUE-5 ────────────────────────────────────────────────────────────
  testWidgets(
      'a SAVED pick re-seeds clamped to the CURRENT option max; a removed '
      'option is ignored', (tester) async {
    final group = const PreferenceGroupModel(
      id: 'pg1',
      label: 'Option 1',
      quantityEnabled: true,
      options: [
        PreferenceOptionModel(key: 'roti', label: 'Roti', minQty: 1, maxQty: 2),
      ],
    );
    List<PreferenceSelection> last = const [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PreferenceGroupSelector(
          groups: [group],
          initialSelections: const [
            // saved when the max was 4; the admin has since lowered it to 2
            PreferenceSelection(groupId: 'pg1', optionKey: 'roti', quantity: 4),
            // option deleted after the record was saved
            PreferenceSelection(groupId: 'pg1', optionKey: 'gone', quantity: 1),
          ],
          onChanged: (s, _, _) => last = s,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('×2'), findsOneWidget);
    expect(last.single.optionKey, 'roti');
    expect(last.single.quantity, 2);
  });

  testWidgets('saved choice line renders the chosen options by name',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SavedChoiceLine(text: 'Non-Veg: Chicken · Veg: Dal')),
    ));
    expect(find.textContaining('Your choice: '), findsOneWidget);
    expect(find.textContaining('Chicken'), findsOneWidget);
  });
}
