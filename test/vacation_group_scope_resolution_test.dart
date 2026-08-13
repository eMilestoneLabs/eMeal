// Client half of the vacation-scope rule (audit 2026-08-12, option (b)).
//
// `isVacationMode` is the ACCOUNT-level bit and now means exactly ORG-WIDE
// leave — a group-scoped approved request is stored on the membership row
// instead (A-full fixed ownership at the write).
//
// `vacationScopedGroupIds` is still required: a covering request governs its
// group from the moment it is approved, BEFORE the read-time sync or the
// FR-VACX-006 sweep activates the membership. Resolving with it means the
// client never disagrees with the server during that activation lag — the
// same reason getVacationCoveredUserIds lets a request win over the flag.
//
// These tests call the PRODUCTION rule directly rather than building the
// provider (which needs AuthProvider + ThemeProvider + a BuildContext). The
// provider is a one-line delegation to that rule, so the rule is where drift
// would actually happen and where it is worth pinning.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// The rule under test is the PRODUCTION one — `MemberSettingOverrides
/// .resolveVacationForGroup`, which StudentSettingsProvider.isVacationMode
/// now delegates to. Asserting a local copy would pass forever while the
/// provider drifted, so there is deliberately no copy here.
bool resolveVacation({
  required bool? override,
  required bool userFlag,
  required List<String>? scopedGroupIds,
  required String groupId,
}) =>
    MemberSettingOverrides.resolveVacationForGroup(
      override: override,
      userFlag: userFlag,
      scopedGroupIds: scopedGroupIds,
      groupId: groupId,
    );

void main() {
  profileChipGuards();
  phase1Guards();
  group('vacation scope resolution', () {
    test('BASELINE: null scope → the user flag governs every group', () {
      // Pure self-service toggle, ORG-LEVEL request, or an older server that
      // omits the field. All three must behave exactly as before.
      expect(
        resolveVacation(
          override: null,
          userFlag: true,
          scopedGroupIds: null,
          groupId: 'grp_B',
        ),
        isTrue,
      );
      expect(
        resolveVacation(
          override: null,
          userFlag: false,
          scopedGroupIds: null,
          groupId: 'grp_B',
        ),
        isFalse,
      );
    });

    test('THE LEAK: a group-A vacation does NOT show as ON in group B', () {
      expect(
        resolveVacation(
          override: null,
          userFlag: true, // set by the server from the group-A request
          scopedGroupIds: ['grp_A'],
          groupId: 'grp_B',
        ),
        isFalse,
      );
    });

    test('the group the leave was requested for still shows ON', () {
      expect(
        resolveVacation(
          override: null,
          userFlag: true,
          scopedGroupIds: ['grp_A'],
          groupId: 'grp_A',
        ),
        isTrue,
      );
    });

    test('a covering request wins even before the flag activates', () {
      // Activation lag must never change what the member sees — the same
      // reason the server ignores the flag once a request governs the date.
      expect(
        resolveVacation(
          override: null,
          userFlag: false,
          scopedGroupIds: ['grp_A'],
          groupId: 'grp_A',
        ),
        isTrue,
      );
    });

    test('an explicit per-group override ALWAYS wins over the scope', () {
      expect(
        resolveVacation(
          override: false,
          userFlag: true,
          scopedGroupIds: ['grp_A'],
          groupId: 'grp_A',
        ),
        isFalse,
      );
      expect(
        resolveVacation(
          override: true,
          userFlag: false,
          scopedGroupIds: ['grp_A'],
          groupId: 'grp_B',
        ),
        isTrue,
      );
    });

    test('unknown group falls back to the flag, never guesses OFF', () {
      // Settings is reachable via a notification deep-link before the shell
      // scope resolves; guessing OFF there would hide a real vacation.
      expect(
        resolveVacation(
          override: null,
          userFlag: true,
          scopedGroupIds: ['grp_A'],
          groupId: '',
        ),
        isTrue,
      );
    });

    test('leave in several groups shows ON in each of them', () {
      for (final g in ['grp_A', 'grp_B']) {
        expect(
          resolveVacation(
            override: null,
            userFlag: true,
            scopedGroupIds: ['grp_A', 'grp_B'],
            groupId: g,
          ),
          isTrue,
        );
      }
      expect(
        resolveVacation(
          override: null,
          userFlag: true,
          scopedGroupIds: ['grp_A', 'grp_B'],
          groupId: 'grp_C',
        ),
        isFalse,
      );
    });
  });

  group('UserModel.vacationScopedGroupIds parsing', () {
    test('an absent field parses as null = governs every group', () {
      // A session cached before this field existed must not change meaning.
      final u = UserModel.fromJson(const {
        'id': 'u1',
        'name': 'A',
        'role': 'student',
        'isVacationMode': true,
      });
      expect(u.vacationScopedGroupIds, isNull);
      expect(u.isVacationMode, isTrue);
    });

    test('a present field parses into the group list', () {
      final u = UserModel.fromJson(const {
        'id': 'u1',
        'name': 'A',
        'role': 'student',
        'isVacationMode': true,
        'vacationScopedGroupIds': ['grp_A'],
      });
      expect(u.vacationScopedGroupIds, ['grp_A']);
    });

    test('it survives a toJson → fromJson round trip (SWR cache)', () {
      final u = UserModel.fromJson(const {
        'id': 'u1',
        'name': 'A',
        'role': 'student',
        'isVacationMode': true,
        'vacationScopedGroupIds': ['grp_A', 'grp_B'],
      });
      expect(
        UserModel.fromJson(u.toJson()).vacationScopedGroupIds,
        ['grp_A', 'grp_B'],
      );
    });

    test('scope is part of equality so the toggle repaints when it changes', () {
      UserModel make(List<String>? scope) => UserModel.fromJson({
            'id': 'u1',
            'name': 'A',
            'role': 'student',
            'isVacationMode': true,
            'vacationScopedGroupIds': scope,
          });
      // Same flag, different scope — without equality the switch would keep
      // painting the pre-approval value.
      expect(make(['grp_A']) == make(['grp_B']), isFalse);
      expect(make(['grp_A']) == make(['grp_A']), isTrue);
    });
  });
}

// ── Phase 1 regression guards ───────────────────────────────────────────────
//
// The student shell resolves vacation ONCE, in StudentDashboardProvider, and
// Attendance / Today's Meals / the banner / reminders / billing all read that
// one value. These pin the two ways that single point historically broke.
void phase1Guards() {
  group('student shell — one resolution point', () {
    test('THE BLOCKER: leave in group A must not gate marking in group B', () {
      // dashProvider.isVacationMode gates the Attendance action card and
      // Today's Meals. Taking user.isVacationMode raw made a member on
      // group-A leave unable to mark in group B, while the SERVER accepted
      // the mark — the client refused an action the server allowed.
      expect(
        MemberSettingOverrides.resolveVacationForGroup(
          override: null,
          userFlag: true,
          scopedGroupIds: ['grp_A'],
          groupId: 'grp_B',
        ),
        isFalse,
      );
    });

    test('and still gates marking in the group the leave IS for', () {
      expect(
        MemberSettingOverrides.resolveVacationForGroup(
          override: null,
          userFlag: true,
          scopedGroupIds: ['grp_A'],
          groupId: 'grp_A',
        ),
        isTrue,
      );
    });

    test('BILLING: group-A leave must not suppress group-B auto-skip rows', () {
      // student_billing_screen feeds this into BillingService.buildRows as
      // vacationUserIds; a wrong true suppresses virtual auto-skip rows and
      // under-states the member's own charges for the group on screen.
      expect(
        MemberSettingOverrides.resolveVacationForGroup(
          override: null,
          userFlag: true,
          scopedGroupIds: ['grp_A'],
          groupId: 'grp_B',
        ),
        isFalse,
      );
    });

    test('BASELINE PRESERVED: an org-wide vacation still gates every group', () {
      // Null scope = pure toggle or ORG-LEVEL request. Must behave exactly as
      // before Phase 1 in every group.
      for (final g in ['grp_A', 'grp_B', 'grp_C']) {
        expect(
          MemberSettingOverrides.resolveVacationForGroup(
            override: null,
            userFlag: true,
            scopedGroupIds: null,
            groupId: g,
          ),
          isTrue,
        );
      }
    });
  });
}

// ── Profile chip: ACCOUNT view, so it means "on vacation ANYWHERE" ──────────
//
// BASELINE PRESERVATION. The profile has no group context, so its chip has
// always meant "on vacation" — not "on vacation in some particular group".
// After A-full a group-scoped leave lives on the membership row, so reading
// only the account flag would silently drop the chip for a member on
// group-scoped leave. That is a baseline behaviour change, not a fix.
void profileChipGuards() {
  bool profileChip(UserModel u) =>
      (u.isVacationMode) || (u.vacationScopedGroupIds?.isNotEmpty ?? false);

  UserModel user({required bool flag, List<String>? scope}) =>
      UserModel.fromJson({
        'id': 'u1',
        'name': 'A',
        'role': 'student',
        'isVacationMode': flag,
        if (scope != null) 'vacationScopedGroupIds': scope,
      });

  group('profile vacation chip — account-level meaning preserved', () {
    test('ORG-WIDE leave shows the chip (baseline)', () {
      expect(profileChip(user(flag: true)), isTrue);
    });

    test('GROUP-SCOPED leave still shows the chip (no silent regression)', () {
      // Pre-A-full the account flag was set by ANY request, so this member saw
      // the chip. It must keep showing.
      expect(profileChip(user(flag: false, scope: ['grp_A'])), isTrue);
    });

    test('no vacation anywhere shows no chip', () {
      expect(profileChip(user(flag: false)), isFalse);
      expect(profileChip(user(flag: false, scope: [])), isFalse);
    });

    test('older server omitting the field falls back to the account flag', () {
      expect(profileChip(user(flag: true)), isTrue);
      expect(profileChip(user(flag: false)), isFalse);
    });
  });
}
