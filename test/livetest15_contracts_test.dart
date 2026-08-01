import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/models/vacation_request_model.dart';

/// Live-Test-15 client-side contracts.
///
/// These two rules are invisible to `flutter analyze` and would regress
/// silently, so they are pinned here:
///   ISSUE-1  membership status must survive the SWR cache round-trip,
///            otherwise a cache-first paint shows a blocked member as active.
///   ISSUE-2B an APPROVED vacation that has ended is never cancellable, and a
///            vacation ending TODAY still is.
void main() {
  group('ISSUE-1 — membership status survives the SWR cache', () {
    UserModel base(String? status) => UserModel(
          id: 'u1',
          name: 'Member',
          email: 'm@example.com',
          role: UserRole.student,
          organizationId: 'org1',
          membershipStatus: status,
        );

    test('blocked status round-trips through toJson/fromJson', () {
      final restored = UserModel.fromJson(base('blocked').toJson());
      expect(restored.membershipStatus, 'blocked');
      expect(restored.isBlockedMember, isTrue);
    });

    test('active status round-trips and is not blocked', () {
      final restored = UserModel.fromJson(base('active').toJson());
      expect(restored.membershipStatus, 'active');
      expect(restored.isBlockedMember, isFalse);
    });

    test('a legacy cache entry without the field stays null (not blocked)', () {
      final legacy = base('blocked').toJson()..remove('membershipStatus');
      final restored = UserModel.fromJson(legacy);
      expect(restored.membershipStatus, isNull);
      expect(restored.isBlockedMember, isFalse);
    });

    test('copyWith can flip the status in place (optimistic block/unblock)', () {
      expect(base('active').copyWith(membershipStatus: 'blocked').isBlockedMember,
          isTrue);
      expect(base('blocked').copyWith(membershipStatus: 'active').isBlockedMember,
          isFalse);
    });
  });

  group('ISSUE-2B — ended vacation is immutable', () {
    VacationRequestModel req(String status, DateTime start, DateTime end) =>
        VacationRequestModel(
          id: 'vr1',
          organizationId: 'org1',
          userId: 'u1',
          startDate: start,
          endDate: end,
          status: status,
        );

    final now = DateTime(2026, 8, 1);

    test('a vacation that ended yesterday HAS ended', () {
      final r = req('approved', DateTime(2026, 7, 29), DateTime(2026, 7, 31));
      expect(r.hasEnded(now: now), isTrue);
    });

    test('a vacation ending TODAY has NOT ended — still cancellable', () {
      final r = req('approved', DateTime(2026, 7, 29), DateTime(2026, 8, 1));
      expect(r.hasEnded(now: now), isFalse);
    });

    test('a future vacation has not ended', () {
      final r = req('approved', DateTime(2026, 8, 5), DateTime(2026, 8, 9));
      expect(r.hasEnded(now: now), isFalse);
    });

    test('an approved+ended vacation is NOT cancellable by anyone', () {
      final r = req('approved', DateTime(2000, 1, 1), DateTime(2000, 1, 5));
      expect(r.isCancellable, isFalse);
    });

    test('an expired PENDING request stays cancellable', () {
      final r = req('pending', DateTime(2000, 1, 1), DateTime(2000, 1, 5));
      expect(r.isCancellable, isTrue);
    });
  });
}
