// ── QrPayloadParser ────────────────────────────────────────────────────────────
//
// Central utility for encoding and decoding QR payloads used across the app.
//
// ## Payload Formats
//
// ### Group QR
//   Full:  `group:{groupId}:{joinToken}`
//   e.g.   `group:grp_001:BLOCK-A-2024`
//
//   Plain 6-char (legacy / simple codes):
//          `ABC123`   (uppercase alphanumeric, exactly 6 chars)
//
//   Deep-link URL:
//          `mealattend://join?code=ABC123`
//          `https://app.mealattend.com/join?code=ABC123`
//
// ### Event QR
//   Full:  `event:{eventId}:{joinToken}`
//   e.g.   `event:evt_001:EVT-XYZ`
//
// ## Future Backend Token Injection
// When the backend is integrated, replace the `joinToken` segment with a
// short-lived JWT. The parse methods return the raw token in [joinToken] —
// all backend validation lives in one place: the API repository layer.
// No scanner or UI code needs to change.
//
// ## Single-Point-of-Change Guarantee
// Both the admin QR generator ([QrPayloadParser.encodeGroupQr]) and the
// student scanner ([QrPayloadParser.parseGroupQr]) use the same format.
// Updating the format requires changes only in this file.

/// Value object returned when a group QR is successfully parsed.
class GroupQrPayload {
  const GroupQrPayload({
    required this.groupId,
    required this.joinToken,
  });

  /// The group identifier extracted from the QR payload.
  final String groupId;

  /// The join code / token. Used as the join code in the student flow.
  ///
  /// In MVP this is the plain 6-char join code.
  /// In production this will be a short-lived JWT.
  final String joinToken;

  @override
  String toString() => 'GroupQrPayload(groupId: $groupId, joinToken: $joinToken)';
}

/// Value object returned when an event QR is successfully parsed.
class EventQrPayload {
  const EventQrPayload({
    required this.eventId,
    required this.joinToken,
  });

  /// The event identifier extracted from the QR payload.
  final String eventId;

  /// The join code / token.
  final String joinToken;

  @override
  String toString() => 'EventQrPayload(eventId: $eventId, joinToken: $joinToken)';
}

/// Utility for encoding and decoding structured QR payloads.
///
/// Usage — parse scanned QR:
/// ```dart
/// final payload = QrPayloadParser.parseGroupQr(rawValue);
/// if (payload != null) {
///   await joinGroup(joinCode: payload.joinToken);
/// }
/// ```
///
/// Usage — generate QR data string for display:
/// ```dart
/// final qrData = QrPayloadParser.encodeGroupQr(
///   groupId: group.id,
///   joinToken: group.joinCode ?? '',
/// );
/// ```
abstract final class QrPayloadParser {
  // ── Group QR ───────────────────────────────────────────────────────────────

  /// Encode a group QR payload string.
  ///
  /// Format: `group:{groupId}:{joinToken}`
  static String encodeGroupQr({
    required String groupId,
    required String joinToken,
  }) {
    return 'group:$groupId:$joinToken';
  }

  /// Parse a raw QR scan value and return a [GroupQrPayload] if valid.
  ///
  /// Supports:
  /// 1. Structured: `group:{groupId}:{joinToken}` (preferred)
  /// 2. Deep-link URL: `mealattend://join?code=ABC123`
  ///                   `https://app.mealattend.com/join?code=ABC123`
  /// 3. Plain 6-char alphanumeric code: `ABC123` (legacy / admin-printed codes)
  ///
  /// Returns `null` if the payload does not match any supported format.
  static GroupQrPayload? parseGroupQr(String raw) {
    final trimmed = raw.trim();

    // 1. Structured format: group:{groupId}:{joinToken}
    if (trimmed.startsWith('group:')) {
      final parts = trimmed.split(':');
      // Expect exactly 3 parts: ['group', groupId, joinToken]
      if (parts.length >= 3 && parts[1].isNotEmpty && parts[2].isNotEmpty) {
        return GroupQrPayload(
          groupId: parts[1],
          joinToken: parts.sublist(2).join(':'), // rejoin in case token has colons
        );
      }
      return null; // Malformed group QR
    }

    // 2. Deep-link / URL with ?code= parameter
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final code = uri.queryParameters['code'];
      if (code != null && _isValidJoinCode(code)) {
        return GroupQrPayload(
          groupId: '', // groupId unknown from plain code — resolved server-side
          joinToken: code.toUpperCase(),
        );
      }
    }

    // 3. Plain 6-char alphanumeric code (case-insensitive)
    if (_isValidJoinCode(trimmed)) {
      return GroupQrPayload(
        groupId: '', // groupId unknown from plain code — resolved server-side
        joinToken: trimmed.toUpperCase(),
      );
    }

    return null;
  }

  // ── Event QR ───────────────────────────────────────────────────────────────

  /// Encode an event QR payload string.
  ///
  /// Format: `event:{eventId}:{joinToken}`
  static String encodeEventQr({
    required String eventId,
    required String joinToken,
  }) {
    return 'event:$eventId:$joinToken';
  }

  /// Parse a raw QR scan value and return an [EventQrPayload] if valid.
  ///
  /// Supports:
  /// 1. Structured: `event:{eventId}:{joinToken}` (preferred)
  /// 2. Deep-link URL: `mealattend://event-join?code=EVTXXX`
  ///
  /// Returns `null` if the payload does not match any supported format.
  static EventQrPayload? parseEventQr(String raw) {
    final trimmed = raw.trim();

    // 1. Structured format: event:{eventId}:{joinToken}
    if (trimmed.startsWith('event:')) {
      final parts = trimmed.split(':');
      if (parts.length >= 3 && parts[1].isNotEmpty && parts[2].isNotEmpty) {
        return EventQrPayload(
          eventId: parts[1],
          joinToken: parts.sublist(2).join(':'),
        );
      }
      return null; // Malformed event QR
    }

    // 2. Deep-link URL with event code
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        return EventQrPayload(
          eventId: uri.queryParameters['eventId'] ?? '',
          joinToken: code,
        );
      }
    }

    return null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static final _plainCodeRegex = RegExp(r'^[A-Za-z0-9]{6}$');

  /// Returns true if [code] is a valid plain 6-char alphanumeric join code.
  static bool _isValidJoinCode(String code) =>
      _plainCodeRegex.hasMatch(code.trim());
}
