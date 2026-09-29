import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/config/feature_flags.dart';

/// Every route that belongs to the Events module (entry, signup, guest join,
/// event admin and event guest screens).
bool isEventsLocation(String location) =>
    location == RouteNames.eventEntry ||
    location == RouteNames.eventSignup ||
    location == RouteNames.eventGuestJoin ||
    location.startsWith('/event-admin') ||
    location.startsWith('/event-guest');

/// Router gate for the Events module. While Events is switched off, any
/// Events route (tap, deep link, QR code, notification or an event account's
/// home) opens the Coming-soon preview. Returns null when nothing changes.
///
/// PURE: [enabled] defaults to the build flag so tests can check both states.
String? eventsRedirect(
  String location, {
  bool enabled = FeatureFlags.eventsEnabled,
}) {
  if (enabled || !isEventsLocation(location)) return null;
  return RouteNames.eventsComingSoon;
}
