// Live-Test-14 ISSUE-3 — the admin dashboard header contract.
//
// This header slot has now been broken twice, in opposite directions, so the
// rules are pinned here rather than left to review:
//
//   1. It once showed a GROUP NAME (`_groups.first.name`) in a field labelled
//      Organisation. Because it read the FIRST group and never the SELECTED
//      one, switching groups could not update it — which is exactly the
//      "top section still shows the previous group" report.
//   2. Fixing that, the GROUP COUNT ("5 Groups") was removed, because the count
//      had been sharing that single slot as a substitute for the missing org
//      name. The count is existing behaviour and must survive.
//
// Both must hold at once: the real organisation name AND the count, on the one
// existing line — "Acme Mess · 5 groups". No group name, ever.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/features/admin/dashboard/widgets/admin_greeting_card.dart';

Future<void> pump(
  WidgetTester tester, {
  required String orgName,
  int groupCount = 0,
  String? roleLabel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AdminGreetingCard(
          adminName: 'Soumyakanti Mal',
          orgName: orgName,
          groupCount: groupCount,
          roleLabel: roleLabel,
        ),
      ),
    ),
  );
}

/// True when some Text in the tree contains [needle].
bool showsText(String needle) => find
    .byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(needle))
    .evaluate()
    .isNotEmpty;

void main() {
  group('organisation name + group count share the one existing line', () {
    testWidgets('shows the real org name AND the count', (tester) async {
      await pump(tester, orgName: 'Acme Mess', groupCount: 5);

      expect(showsText('Acme Mess · 5 groups'), isTrue,
          reason: 'both must render — one must not replace the other');
    });

    testWidgets('count is singular for exactly one group', (tester) async {
      await pump(tester, orgName: 'Acme Mess', groupCount: 1);

      expect(showsText('Acme Mess · 1 group'), isTrue);
      expect(showsText('1 groups'), isFalse, reason: 'no "1 groups"');
    });

    testWidgets('no count yet → org name alone, never a bare number',
        (tester) async {
      await pump(tester, orgName: 'Acme Mess');

      expect(showsText('Acme Mess'), isTrue);
      expect(showsText('·'), isFalse,
          reason: 'a 0 count must not render a dangling separator');
    });

    testWidgets('the placeholder still renders when no name is resolved',
        (tester) async {
      // The header must degrade to the neutral placeholder rather than
      // inventing a name — it must never fall back to a group name again.
      await pump(tester, orgName: 'Your Organisation', groupCount: 3);

      expect(showsText('Your Organisation · 3 groups'), isTrue);
    });
  });

  group('per-group role', () {
    testWidgets('renders the selected group\'s role label', (tester) async {
      // The role is what actually tracks the group switch, so it must render
      // exactly what it is handed — no caching, no defaulting over a real value.
      await pump(tester, orgName: 'Acme Mess', groupCount: 5,
          roleLabel: 'Event Admin');

      expect(showsText('Event Admin'), isTrue);
    });

    testWidgets('a different group\'s role renders instead', (tester) async {
      await pump(tester, orgName: 'Acme Mess', groupCount: 5,
          roleLabel: 'Mess Manager');

      expect(showsText('Mess Manager'), isTrue);
      expect(showsText('Event Admin'), isFalse);
    });
  });
}
