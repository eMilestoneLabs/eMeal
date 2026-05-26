import 'package:flutter/material.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_meal_type.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';

/// Static mock event data for MVP development.
abstract final class MockEventsData {
  static final _now = DateTime.now();
  static final _today = DateTime(_now.year, _now.month, _now.day);

  // ── Shared meal type sets ──────────────────────────────────────────────────

  static const List<EventMealType> weddingMealTypes = [
    EventMealType(
        id: 'mt_veg',
        title: 'Veg',
        emoji: '🥗',
        color: Color(0xFF4CAF50),
        isVeg: true),
    EventMealType(
        id: 'mt_jain',
        title: 'Jain',
        emoji: '🙏',
        color: Color(0xFF8BC34A),
        isVeg: true),
    EventMealType(
        id: 'mt_chicken',
        title: 'Chicken',
        emoji: '🍗',
        color: Color(0xFFFF5722),
        isVeg: false),
    EventMealType(
        id: 'mt_mutton',
        title: 'Mutton',
        emoji: '🍖',
        color: Color(0xFF9C27B0),
        isVeg: false),
    EventMealType(
        id: 'mt_dessert',
        title: 'Dessert',
        emoji: '🎂',
        color: Color(0xFFE91E63),
        isVeg: true),
  ];

  static const List<EventMealType> conferenceMealTypes = [
    EventMealType(
        id: 'mt_veg',
        title: 'Veg',
        emoji: '🥗',
        color: Color(0xFF4CAF50),
        isVeg: true),
    EventMealType(
        id: 'mt_egg',
        title: 'Egg',
        emoji: '🥚',
        color: Color(0xFFFFC107),
        isVeg: true),
    EventMealType(
        id: 'mt_drinks',
        title: 'Drinks',
        emoji: '🥤',
        color: Color(0xFF00BCD4),
        isVeg: true),
  ];

  // ── Events ─────────────────────────────────────────────────────────────────

  static List<EventModel> get adminEvents => [
        EventModel(
          id: 'evt_001',
          name: 'Mahanta Wedding Reception',
          type: EventType.wedding,
          date: _today.add(const Duration(days: 7)),
          expectedGuestCount: 120,
          adminId: 'admin_event_001',
          adminName: 'Rajesh Kumar',
          mealTypes: weddingMealTypes,
          autoDeleteAfter7Days: false,
          isActive: true,
          createdAt: _now.subtract(const Duration(days: 2)),
          joinCode: 'WED2026',
        ),
        EventModel(
          id: 'evt_002',
          name: 'Tech Conclave 2026',
          type: EventType.conference,
          date: _today.add(const Duration(days: 3)),
          expectedGuestCount: 85,
          adminId: 'admin_event_001',
          adminName: 'Rajesh Kumar',
          mealTypes: conferenceMealTypes,
          autoDeleteAfter7Days: true,
          isActive: true,
          createdAt: _now.subtract(const Duration(days: 1)),
          joinCode: 'CONF26',
        ),
      ];

  // ── Guest parties ──────────────────────────────────────────────────────────

  static List<EventGuestParty> partiesForEvent(String eventId) {
    switch (eventId) {
      case 'evt_001':
        return _evt001Parties;
      default:
        return [];
    }
  }

  static List<EventGuestParty> get _evt001Parties {
    // ── Party 1: Rahul Mahanta — 3 adults + 2 children ─────────────────────
    final party1 = EventGuestParty(
      id: 'party_001',
      eventId: 'evt_001',
      primaryName: 'Rahul Mahanta',
      adultsCount: 3,
      childrenCount: 2,
      joinedAt: _now.subtract(const Duration(hours: 2)),
    );
    final p1 = party1
        .setEventMealTypeId('party_001_p1', 'mt_veg')
        .setEventMealTypeId('party_001_p2', 'mt_chicken')
        .setEventMealTypeId('party_001_p3', 'mt_mutton')
        .renamePerson('party_001_p4', 'Anjali Mahanta')
        .renamePerson('party_001_p5', 'Riya Mahanta')
        .setEventMealTypeId('party_001_p4', 'mt_veg')
        .setEventMealTypeId('party_001_p5', 'mt_jain');

    // ── Party 2: Priya Sharma — 2 adults ───────────────────────────────────
    final party2 = EventGuestParty(
      id: 'party_002',
      eventId: 'evt_001',
      primaryName: 'Priya Sharma',
      adultsCount: 2,
      childrenCount: 0,
      joinedAt: _now.subtract(const Duration(minutes: 45)),
    );
    final p2 = party2
        .setEventMealTypeId('party_002_p1', 'mt_jain')
        .setEventMealTypeId('party_002_p2', 'mt_veg');

    // ── Party 3: Amit Verma — 1 adult (pending) ───────────────────────────
    final party3 = EventGuestParty(
      id: 'party_003',
      eventId: 'evt_001',
      primaryName: 'Amit Verma',
      adultsCount: 1,
      childrenCount: 0,
      joinedAt: _now.subtract(const Duration(minutes: 20)),
    );

    return [p1, p2, party3];
  }

  // ── Aggregate helpers ──────────────────────────────────────────────────────

  static int totalGuests(String eventId) =>
      partiesForEvent(eventId).fold(0, (s, p) => s + p.totalCount);
}
