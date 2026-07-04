import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/guest_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Module 22 (Pass 9) — hosted-guest API calls (host + admin flows).
///
/// Route map (backend GuestsController, all under /attendance):
///   POST   /attendance/:mealId/guests        — book N guests
///   GET    /attendance/guests?date=&mealId=  — list (member: own; admin: group)
///   PATCH  /attendance/guests/:id            — edit name/preference
///   DELETE /attendance/guests/:id            — cancel
///   POST   /attendance/guests/:id/approve    — admin approves member booking
///   POST   /attendance/guests/:id/reject     — admin rejects
///   POST   /attendance/guests/:id/confirm    — HOST confirms admin-added guest
///   POST   /attendance/guests/:id/decline    — HOST declines admin-added guest
class GuestRepository {
  GuestRepository();

  /// Books [guests] on [mealId] for [attendanceDate] (YYYY-MM-DD).
  /// Admins pass [hostUserId] to book on behalf of a member — the booking
  /// parks as pendingApproval until the HOST confirms (FR-HG-062).
  Future<Result<GuestBookingResult>> bookGuests({
    required String mealId,
    required String attendanceDate,
    required List<GuestDraft> guests,
    String? hostUserId,
  }) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/attendance/$mealId/guests',
      body: {
        'attendanceDate': attendanceDate,
        'guests': guests.map((g) => g.toJson()).toList(),
        if (hostUserId != null) 'hostUserId': hostUserId,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(GuestBookingResult.fromJson(value)),
    };
  }

  /// Lists guests. Members receive only their own; admins may filter by
  /// [groupId]/[mealId]/[date]/[hostUserId] and see the whole group.
  Future<Result<List<MealGuestModel>>> listGuests({
    String? date,
    String? groupId,
    String? mealId,
    String? hostUserId,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/attendance/guests',
      queryParameters: {
        if (date != null) 'date': date,
        if (groupId != null) 'groupId': groupId,
        if (mealId != null) 'mealId': mealId,
        if (hostUserId != null) 'hostUserId': hostUserId,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(((value['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => MealGuestModel.fromJson(e.cast<String, dynamic>()))
          .toList()),
    };
  }

  /// Edits a booked guest's name/preference (host in-window; admin anytime).
  Future<Result<MealGuestModel>> updateGuest({
    required String id,
    String? displayName,
    String? mealPreference,
  }) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/attendance/guests/$id',
      body: {
        if (displayName != null) 'displayName': displayName,
        if (mealPreference != null) 'mealPreference': mealPreference,
      },
    );
    return _single(result);
  }

  /// Cancels a booked guest (host in-window; admin any time — FR-HG-033/052).
  Future<Result<MealGuestModel>> cancelGuest(String id) async {
    final result = await DioApiService.instance
        .delete<Map<String, dynamic>>('/attendance/guests/$id');
    return _single(result);
  }

  /// Admin approves a member-created pending booking (FR-HG-042).
  Future<Result<MealGuestModel>> approveGuest(String id, {String? note}) =>
      _decide(id, 'approve', note: note);

  /// Admin rejects a member-created pending booking.
  Future<Result<MealGuestModel>> rejectGuest(String id, {String? note}) =>
      _decide(id, 'reject', note: note);

  /// HOST confirms an admin-proposed guest — accepts the charge (FR-HG-062).
  Future<Result<MealGuestModel>> confirmGuest(String id) =>
      _decide(id, 'confirm');

  /// HOST declines an admin-proposed guest — cancelled, never billed.
  Future<Result<MealGuestModel>> declineGuest(String id) =>
      _decide(id, 'decline');

  Future<Result<MealGuestModel>> _decide(
    String id,
    String action, {
    String? note,
  }) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/attendance/guests/$id/$action',
      body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    return _single(result);
  }

  Result<MealGuestModel> _single(Result<Map<String, dynamic>> result) =>
      switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(MealGuestModel.fromJson(value)),
      };
}
