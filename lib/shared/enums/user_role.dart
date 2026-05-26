/// All roles a user can hold in the MealAttend platform.
///
/// Roles fall into three groups:
///   - **Student group**: student, member, guest — attend meals, mark attendance
///   - **Admin group**: messManager, hostelManager, hostelAdmin, organizationManager — manage groups/meals
///   - **Event group**: eventAdmin, eventGuest — create/join temporary events
///
/// Use [isStudentGroup], [isAdminGroup], [isEventGroup] for role-based routing
/// and UI visibility decisions. Never compare directly to a single role
/// where a group check is more appropriate.
enum UserRole {
  // ── Student / User group ──────────────────────────────────────────────────

  /// Enrolled in an educational or hostel group. Semi-permanent membership.
  student,

  /// Member of an org, factory, cafeteria, or community group. Semi-permanent.
  member,

  /// Short-term participant — temporary mess guest or day pass. Limited access.
  guest,

  // ── Admin / Manager group ─────────────────────────────────────────────────

  /// Manages a mess or canteen. Full meal + attendance configuration rights.
  messManager,

  /// Manages a hostel group. Full group + meal management rights.
  hostelManager,

  /// Top-level admin for a hostel organization. Can manage multiple groups.
  hostelAdmin,

  /// Admin for an organization (factory, office, coaching, community, etc.).
  organizationManager,

  // ── Event group ───────────────────────────────────────────────────────────

  /// Creates and manages a temporary event. Generates event QR, manages guests.
  eventAdmin,

  /// Temporary event participant. Session-based — not a permanent account.
  eventGuest;

  // ── Display ───────────────────────────────────────────────────────────────

  String get label {
    switch (this) {
      case UserRole.student:
        return 'Student';
      case UserRole.member:
        return 'Member';
      case UserRole.guest:
        return 'Guest';
      case UserRole.messManager:
        return 'Mess Manager';
      case UserRole.hostelManager:
        return 'Hostel Manager';
      case UserRole.hostelAdmin:
        return 'Hostel Admin';
      case UserRole.organizationManager:
        return 'Organization Manager';
      case UserRole.eventAdmin:
        return 'Event Admin';
      case UserRole.eventGuest:
        return 'Event Guest';
    }
  }

  /// Short label used in compact UI contexts (chips, badges).
  String get shortLabel {
    switch (this) {
      case UserRole.student:
        return 'Student';
      case UserRole.member:
        return 'Member';
      case UserRole.guest:
        return 'Guest';
      case UserRole.messManager:
        return 'Mess Mgr';
      case UserRole.hostelManager:
        return 'Hostel Mgr';
      case UserRole.hostelAdmin:
        return 'Admin';
      case UserRole.organizationManager:
        return 'Org Manager';
      case UserRole.eventAdmin:
        return 'Event Admin';
      case UserRole.eventGuest:
        return 'Event Guest';
    }
  }

  /// Alias for [label] — used by screens that call `.displayName`.
  String get displayName => label;

  // ── Group membership ──────────────────────────────────────────────────────

  /// True for student, member, guest — routed to StudentShell.
  bool get isStudentGroup =>
      this == UserRole.student ||
      this == UserRole.member ||
      this == UserRole.guest;

  /// True for all admin/manager roles — routed to AdminShell.
  bool get isAdminGroup =>
      this == UserRole.messManager ||
      this == UserRole.hostelManager ||
      this == UserRole.hostelAdmin ||
      this == UserRole.organizationManager;

  /// True for event-specific roles — routed to Event shells.
  bool get isEventGroup =>
      this == UserRole.eventAdmin || this == UserRole.eventGuest;

  // ── Convenience aliases (backward-compat for existing router/guards) ──────

  /// True if this role has admin-level access. Alias for [isAdminGroup].
  bool get isAdmin => isAdminGroup;

  /// True if this role has student-level access. Alias for [isStudentGroup].
  bool get isStudent => isStudentGroup;
}
