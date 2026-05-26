import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/data/contracts/i_event_repository.dart';
import 'package:smart_meal_management/data/repositories/event_repository.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

// ── EventGuestProvider ─────────────────────────────────────────────────────────

/// Manages state for the event guest dashboard (temporary session).
///
/// A guest session is intentionally lightweight:
///   1. Guest scans QR → enters name + adult/child counts → joins event
///   2. Provider stores their [EventGuestParty] in memory for the session
///   3. Guest selects meal preferences per person from their dashboard
///   4. Guest can rename "Guest-N" entries to actual names
///
/// This provider does NOT require permanent account creation.
/// The session is persisted to SharedPreferences so a guest can return
/// after backgrounding the app or a cold restart before clearing it.
/// Call [restoreSession] on startup, then [clearSession] on exit.
class EventGuestProvider extends ChangeNotifier {
  /// Defaults to [EventRepository] which internally dispatches to mock or live
  /// based on [EnvConfig.current.mockAuthEnabled].
  EventGuestProvider({IEventRepository? repo})
      : _repo = repo ?? EventRepository();

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const _kParty = 'event_guest_party';
  static const _kEventId = 'event_guest_event_id';
  static const _kEventName = 'event_guest_event_name';
  static const _kJoinCode = 'event_guest_join_code';
  /// Full event JSON — introduced to persist mealTypes across cold restarts.
  static const _kEventJson = 'event_guest_event_json';

  final IEventRepository _repo;

  // ── State ─────────────────────────────────────────────────────────────────

  EventModel? _event;
  EventGuestParty? _myParty;
  bool _isLoading = false;
  String? _error;

  /// True while the join flow is being processed.
  bool _isJoining = false;

  // ── Public getters ────────────────────────────────────────────────────────

  EventModel? get event => _event;
  EventGuestParty? get myParty => _myParty;
  bool get isLoading => _isLoading;
  bool get isJoining => _isJoining;
  String? get error => _error;

  bool get hasJoined => _myParty != null;

  // ── Join flow ─────────────────────────────────────────────────────────────

  /// Called when a guest scans a QR or enters a join code.
  ///
  /// [joinCode] is the 6-character alphanumeric code from the event QR.
  /// Returns true if the event was found and loaded successfully.
  Future<bool> loadEventByJoinCode(String joinCode) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    if (joinCode.trim().length < 4) {
      _error = 'Invalid join code. Please scan the QR again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Look up from shared mock repository (same data as admin side)
    final result = await _repo.getEventByJoinCode(joinCode.trim());
    switch (result) {
      case Ok(:final value):
        _event = value;
      case Err(:final failure):
        // In live mode the backend is the authority — reject invalid codes.
        if (!EnvConfig.current.mockAuthEnabled) {
          _error = failure.message.isNotEmpty
              ? failure.message
              : 'Invalid or expired event code. Please scan a valid QR.';
          _isLoading = false;
          notifyListeners();
          return false;
        }
        // Mock/dev fallback: create a minimal placeholder event so guests can
        // still join during local development even when the code is not yet
        // registered in the mock store.
        final code = joinCode.trim().toLowerCase();
        _event = EventModel(
          id: 'evt_$code',
          name: 'Event',
          type: EventType.corporate,
          date: DateTime.now(),
          expectedGuestCount: 50,
          adminId: 'admin_001',
          adminName: 'Event Admin',
          joinCode: joinCode.trim(),
        );
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Completes the join flow — creates the guest's [EventGuestParty].
  ///
  /// Called after the guest fills in their name, adult count, and child count.
  Future<bool> joinEvent({
    required String primaryName,
    required int adultsCount,
    required int childrenCount,
  }) async {
    if (_event == null) {
      _error = 'No event loaded. Please scan the QR again.';
      notifyListeners();
      return false;
    }

    if (primaryName.trim().isEmpty) {
      _error = 'Please enter your name.';
      notifyListeners();
      return false;
    }

    if (adultsCount < 1) {
      _error = 'At least one adult is required.';
      notifyListeners();
      return false;
    }

    _isJoining = true;
    _error = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 400));

    final partyId = 'party_${DateTime.now().millisecondsSinceEpoch}';
    _myParty = EventGuestParty(
      id: partyId,
      eventId: _event!.id,
      primaryName: primaryName.trim(),
      adultsCount: adultsCount,
      childrenCount: childrenCount,
      joinedAt: DateTime.now(),
    );

    _isJoining = false;
    notifyListeners();
    unawaited(_persistSession());
    return true;
  }

  // ── Event meal type (event system) ───────────────────────────────────────

  /// Sets the event meal type for one person (uses selectedMealTypeId).
  ///
  /// This is the event-system equivalent of [setMealPreference].
  /// [mealTypeId] must match one of [event.mealTypes] ids.
  void setEventMealType(String personId, String? mealTypeId) {
    if (_myParty == null) return;
    _myParty = _myParty!.setEventMealTypeId(personId, mealTypeId);
    notifyListeners();
    unawaited(_persistSession());
  }

  // ── Meal preference (hostel system, kept for compatibility) ──────────────

  /// Sets the meal preference for one person in the guest's party.
  void setMealPreference(String personId, MealPreferenceOption preference) {
    if (_myParty == null) return;
    _myParty = _myParty!.setMealPreference(personId, preference);
    notifyListeners();
    unawaited(_persistSession());
  }

  // ── Attendance ────────────────────────────────────────────────────────────

  /// Toggles present/absent for one person in the guest's party.
  void toggleAttendance(String personId) {
    if (_myParty == null) return;
    _myParty = _myParty!.toggleAttendance(personId);
    notifyListeners();
    unawaited(_persistSession());
  }

  // ── Guest name editing ────────────────────────────────────────────────────

  /// Renames a non-primary guest in the party.
  ///
  /// Only non-primary guests can be renamed (the primary guest's name is
  /// set at join time).
  void renamePerson(String personId, String newName) {
    if (_myParty == null) return;
    final person = _myParty!.persons.firstWhere(
      (p) => p.id == personId,
      orElse: () => throw ArgumentError('Person $personId not found'),
    );
    if (person.isPrimary) return; // Primary guest name is fixed.
    _myParty = _myParty!.renamePerson(personId, newName.trim());
    notifyListeners();
    unawaited(_persistSession());
  }

  // ── Session persistence ───────────────────────────────────────────────────

  /// Saves the current party + minimal event info to SharedPreferences.
  ///
  /// Called automatically after every state mutation so the guest can
  /// resume after the app is backgrounded or killed.
  Future<void> _persistSession() async {
    if (_myParty == null || _event == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kParty, jsonEncode(_myParty!.toJson()));
      await prefs.setString(_kEventId, _event!.id);
      await prefs.setString(_kEventName, _event!.name);
      await prefs.setString(_kJoinCode, _event!.joinCode ?? '');
      // Persist the full event JSON so mealTypes survive cold restarts.
      await prefs.setString(_kEventJson, jsonEncode(_event!.toJson()));
    } catch (_) {
      // Non-critical: if persistence fails the in-memory state is still valid.
    }
  }

  /// Attempts to restore a previously persisted guest session.
  ///
  /// Call this once on app startup from the event guest shell.
  /// Returns true if a session was successfully restored.
  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final partyJson = prefs.getString(_kParty);
      final eventId = prefs.getString(_kEventId);
      final eventName = prefs.getString(_kEventName);
      final joinCode = prefs.getString(_kJoinCode);
      final eventJson = prefs.getString(_kEventJson);

      if (partyJson == null || eventId == null) return false;

      final party = EventGuestParty.fromJson(
        Map<String, dynamic>.from(jsonDecode(partyJson) as Map),
      );

      if (eventJson != null) {
        // Preferred path: restore full event including mealTypes.
        _event = EventModel.fromJson(
          Map<String, dynamic>.from(jsonDecode(eventJson) as Map),
        );
      } else {
        // Legacy fallback: reconstruct a minimal event without mealTypes.
        // This path is only hit for sessions persisted before _kEventJson was
        // introduced. The guest will need to rejoin to see meal type options.
        _event = EventModel(
          id: eventId,
          name: eventName ?? 'Event',
          type: EventType.corporate,
          date: party.joinedAt ?? DateTime.now(),
          expectedGuestCount: 50,
          adminId: 'admin',
          adminName: 'Event Admin',
          joinCode: joinCode,
        );
      }

      _myParty = party;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Session reset ─────────────────────────────────────────────────────────

  /// Clears all guest session data (called on logout or event exit).
  Future<void> clearSession() async {
    _event = null;
    _myParty = null;
    _error = null;
    _isLoading = false;
    _isJoining = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kParty);
      await prefs.remove(_kEventId);
      await prefs.remove(_kEventName);
      await prefs.remove(_kJoinCode);
      await prefs.remove(_kEventJson);
    } catch (_) {}
  }
}
