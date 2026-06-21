/// Realtime (Socket.IO) event-name constants for the eMeal NestJS backend.
///
/// These mirror the **contract-locked** server emit names in
/// `src/realtime/services/realtime-events.service.ts` and the client→server
/// message names handled by `src/realtime/gateway/attendance.gateway.ts`.
///
/// All server→client events are versioned with a `.v1` suffix and are
/// **additive-safe**: new events may be added, existing ones are never renamed
/// or removed. Listen to them via [RealtimeService.events].
///
/// Rooms the socket is auto-joined to on connect (server-side, from JWT):
///   - `user:{userId}`
///   - `organization:{organizationId}`
///   - `admin:{organizationId}` (admin roles only)
///
/// Group rooms (`group:{groupId}`) are opt-in — join them with
/// [RealtimeService.joinGroup].
abstract final class RealtimeEvents {
  // ── Server → client (versioned, .v1) ────────────────────────────────────────

  /// First-time attendance mark. Room: `group:{groupId}`.
  static const String attendanceMarked = 'attendance.marked.v1';

  /// Admin override / re-mark of an attendance record. Room: `group:{groupId}`.
  static const String attendanceUpdated = 'attendance.updated.v1';

  /// Admin override (emitted alongside [attendanceUpdated]). Room: `group:{groupId}`.
  static const String attendanceOverridden = 'attendance.overridden.v1';

  /// Attendance analytics cache invalidated. Room: `admin:{organizationId}`.
  static const String attendanceAnalyticsUpdated =
      'attendance.analytics.updated.v1';

  /// Meal config changed. Room: `organization:{organizationId}`.
  static const String mealUpdated = 'meal.updated.v1';

  /// Meal activated/published for the day. Room: `group:{groupId}`.
  static const String mealPublished = 'meal.published.v1';

  /// Weekly schedule created or entries modified. Room: `admin:{organizationId}`.
  static const String scheduleUpdated = 'schedule.updated.v1';

  /// Schedule published to students. Room: `group:{groupId}`.
  static const String schedulePublished = 'schedule.published.v1';

  /// Member blocked by admin. Room: `group:{groupId}`.
  static const String memberBlocked = 'member.blocked.v1';

  /// Member joined / removed / role changed. Room: `group:{groupId}`.
  static const String groupMemberUpdated = 'group.member.updated.v1';

  /// Admin/student dashboard cache bust. Room: org / admin.
  static const String dashboardSummaryUpdated = 'dashboard.summary.updated.v1';

  /// Full dashboard refresh signal. Room: org / admin.
  static const String dashboardUpdated = 'dashboard.updated.v1';

  /// Analytics aggregates changed. Room: `admin:{organizationId}`.
  static const String analyticsUpdated = 'analytics.updated.v1';

  /// Event data changed. Room: `organization:{organizationId}`.
  static const String eventUpdated = 'event.updated.v1';

  /// Event statistics changed (guest counts, etc.). Room: org / admin.
  static const String eventStatsUpdated = 'event.stats.updated.v1';

  /// Guest party joined an event. Room: `organization:{organizationId}`.
  static const String guestJoined = 'guest.joined.v1';

  /// Guest party / person updated. Room: `organization:{organizationId}`.
  static const String guestUpdated = 'guest.updated.v1';

  /// New notice posted (Phase B notice board). Room: group / org / admin.
  static const String noticeCreated = 'notice.created.v1';

  /// Server-side error frame (e.g. rate limit). Not versioned.
  static const String error = 'error';

  /// Every server→client event this client knows how to surface.
  static const List<String> all = <String>[
    attendanceMarked,
    attendanceUpdated,
    attendanceOverridden,
    attendanceAnalyticsUpdated,
    mealUpdated,
    mealPublished,
    scheduleUpdated,
    schedulePublished,
    memberBlocked,
    groupMemberUpdated,
    dashboardSummaryUpdated,
    dashboardUpdated,
    analyticsUpdated,
    eventUpdated,
    eventStatsUpdated,
    guestJoined,
    guestUpdated,
    noticeCreated,
  ];

  // ── Client → server (messages handled by the gateway) ───────────────────────

  /// Join a group room. Payload: `{ 'groupId': String }`.
  static const String joinGroup = 'join:group';

  /// Leave a group room. Payload: `{ 'groupId': String }`.
  static const String leaveGroup = 'leave:group';

  /// Heartbeat / latency probe. Payload: `{ 'clientTime': int }`.
  static const String ping = 'ping';
}
