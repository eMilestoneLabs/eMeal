import 'package:equatable/equatable.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

/// ISSUE-001: lightweight per-membership brief carried on the user payload so
/// the group switcher can label chips with REAL group names (never "Group N")
/// and show the member's per-group functional role after a switch.
class UserGroupBrief extends Equatable {
  const UserGroupBrief({required this.id, required this.name, this.role});

  final String id;
  final String name;

  /// Per-group functional role name (e.g. 'messManager'), null → global role.
  final String? role;

  factory UserGroupBrief.fromJson(Map<String, dynamic> j) => UserGroupBrief(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        role: j['role'] as String?,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};

  @override
  List<Object?> get props => [id, name, role];
}

/// Core user model shared across student and admin features.
class UserModel extends Equatable {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.organizationId,
    this.groupId,
    this.groupIds = const [],
    this.groups = const [],
    this.avatarUrl,
    this.phone,
    this.gender,
    this.age,
    this.isActive = true,
    this.isVacationMode = false,
    this.isDefaultAttendance = false,
    this.vacationScopedGroupIds,
    this.remindersEnabled = true,
    this.emailVerified = false,
    this.loginPreference = 'email',
    this.createdAt,
    this.groupFunctionalRole,
    this.membershipStatus,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String organizationId;
  final String? groupId;
  final List<String> groupIds;

  /// ISSUE-001: membership briefs ({id, name, role}) parallel to [groupIds].
  /// Additive — empty when the backend payload predates the field.
  final List<UserGroupBrief> groups;

  final String? avatarUrl;
  final String? phone;

  /// Gender collected at signup (e.g. 'Male', 'Female', 'Other').
  final String? gender;

  /// Age collected at signup.
  final int? age;

  final bool isActive;
  final bool isVacationMode;
  final bool isDefaultAttendance;

  /// Which groups [isVacationMode] actually applies to.
  ///
  /// The flag is ONE user-level bit, but an approved vacation request may be
  /// scoped to a single group — and the server sets the bit from any covering
  /// request. Without this, `override ?? isVacationMode` reports "on vacation"
  /// in a group the member never requested leave from.
  ///
  ///   null      → governs EVERY group. Both a pure self-service toggle and an
  ///               ORG-LEVEL request land here, and an older server that does
  ///               not send the field also does — so this is exactly the
  ///               previous behaviour and nothing regresses.
  ///   [ids]     → only these groups; the member is NOT on vacation elsewhere.
  final List<String>? vacationScopedGroupIds;

  /// Whether attendance-window reminders are enabled for this user.
  ///
  /// Persisted in user model so the preference survives cold restarts.
  final bool remindersEnabled;

  /// SRS AUTH-036/040 — true once the user's email has been verified via OTP.
  /// Drives the verified/unverified badge on profile screens.
  final bool emailVerified;

  /// SRS AUTH-011/012 — default credential for password login ('email' or
  /// 'mobile'). Changeable from Profile settings after email verification.
  final String loginPreference;

  final DateTime? createdAt;

  /// #2: the member's per-group DISPLAY role for the group currently in context
  /// (from GroupMember.functionalRole). Display-only — never a permission grant.
  /// Null for account-level user objects; set when a user is loaded as a group
  /// member so the admin member list can show their chosen role. [role] (the
  /// global account role) is left untouched so any isAdmin gating is unaffected.
  final UserRole? groupFunctionalRole;

  /// Live-Test-15 ISSUE-1: the member's `GroupMember.status` for the group
  /// currently in context ('active' | 'pending' | 'blocked' | 'removed').
  ///
  /// SERVER TRUTH — the backend already emits it on every member row
  /// (`GroupMemberSerializer.toResponse`), it was simply discarded by the
  /// client. Null for account-level user objects (a plain `/users/me` payload
  /// carries no membership), which is why every consumer treats null as
  /// "not a member row / unknown" and falls back to prior behaviour.
  ///
  /// Display + affordance gating only — enforcement stays server-side.
  final String? membershipStatus;

  /// True when this member row is blocked in the group currently in context.
  /// Null-safe: an account-level user object is never "blocked" here.
  bool get isBlockedMember => membershipStatus == 'blocked';

  /// Resolved group membership list.
  ///
  /// Falls back to [groupId] when [groupIds] is empty so that users
  /// constructed with only the legacy `groupId` field (e.g. mock fixtures)
  /// still pass the "has joined a group" check correctly.
  List<String> get effectiveGroupIds =>
      groupIds.isNotEmpty ? groupIds : (groupId != null ? [groupId!] : const []);

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        email: j['email'] ?? '',
        role: UserRole.values.firstWhere(
          (r) => r.name == j['role'],
          orElse: () => UserRole.student,
        ),
        organizationId: j['organizationId'] ?? '',
        groupId: j['groupId'],
        groupIds: List<String>.from(j['groupIds'] ?? []),
        groups: (j['groups'] as List?)
                ?.whereType<Map>()
                .map((g) =>
                    UserGroupBrief.fromJson(Map<String, dynamic>.from(g)))
                .toList() ??
            const [],
        avatarUrl: j['avatarUrl'],
        phone: j['phone'],
        gender: j['gender'],
        age: j['age'] as int?,
        isActive: j['isActive'] ?? true,
        isVacationMode: j['isVacationMode'] ?? false,
        isDefaultAttendance: j['isDefaultAttendance'] ?? false,
        // Absent (older server, or a cached session written before this
        // field existed) stays null = "governs every group" = old behaviour.
        vacationScopedGroupIds: (j['vacationScopedGroupIds'] as List?)
            ?.map((e) => e as String)
            .toList(),
        remindersEnabled: j['remindersEnabled'] ?? true,
        emailVerified: j['emailVerified'] ?? false,
        loginPreference: j['loginPreference'] ?? 'email',
        createdAt:
            j['createdAt'] != null ? DateTime.parse(j['createdAt']) : null,
        groupFunctionalRole:
            UserRole.fromName(j['groupFunctionalRole'] as String?),
        // Round-trips through the SWR cache (see toJson) so a cache-first
        // paint can never show a blocked member as active.
        membershipStatus: j['membershipStatus'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.name,
        'organizationId': organizationId,
        'groupId': groupId,
        'groupIds': groupIds,
        'groups': groups.map((g) => g.toJson()).toList(),
        'avatarUrl': avatarUrl,
        'phone': phone,
        'gender': gender,
        'age': age,
        'isActive': isActive,
        'isVacationMode': isVacationMode,
        'isDefaultAttendance': isDefaultAttendance,
        'vacationScopedGroupIds': vacationScopedGroupIds,
        'remindersEnabled': remindersEnabled,
        'emailVerified': emailVerified,
        'loginPreference': loginPreference,
        'createdAt': createdAt?.toIso8601String(),
        'groupFunctionalRole': groupFunctionalRole?.name,
        'membershipStatus': membershipStatus,
      };

  // Sentinel used to distinguish "caller passed null intentionally" from
  // "caller omitted the argument" in [copyWith] for nullable fields.
  static const Object _absent = Object();

  /// Returns a copy with updated fields.
  ///
  /// Nullable fields ([groupId], [avatarUrl], [phone], [gender], [age],
  /// [createdAt]) can be explicitly cleared to `null` by passing
  /// `const UserModelNull()` — i.e. the typed sentinel — via [clearGroupId]
  /// etc.  The simpler sentinel approach below uses a private [_absent] object
  /// so callers don't need a separate type:
  ///
  /// ```dart
  /// // Clear groupId
  /// user.copyWith(groupId: null, clearGroupId: true);
  /// ```
  ///
  /// For backwards-compatible nullable clearing the [Object?] sentinel
  /// overload is used for [groupId] specifically since it's the field most
  /// often cleared when a user leaves a group.
  UserModel copyWith({
    String? name,
    String? email,
    UserRole? role,
    String? organizationId,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? groupId = _absent,
    List<String>? groupIds,
    List<UserGroupBrief>? groups,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? avatarUrl = _absent,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? phone = _absent,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? gender = _absent,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? age = _absent,
    bool? isActive,
    bool? isVacationMode,
    bool? isDefaultAttendance,
    List<String>? vacationScopedGroupIds,
    bool? remindersEnabled,
    bool? emailVerified,
    String? loginPreference,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? createdAt = _absent,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? groupFunctionalRole = _absent,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? membershipStatus = _absent,
  }) =>
      UserModel(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role ?? this.role,
        organizationId: organizationId ?? this.organizationId,
        groupId: identical(groupId, _absent)
            ? this.groupId
            : groupId as String?,
        groupIds: groupIds ?? this.groupIds,
        groups: groups ?? this.groups,
        avatarUrl: identical(avatarUrl, _absent)
            ? this.avatarUrl
            : avatarUrl as String?,
        phone: identical(phone, _absent) ? this.phone : phone as String?,
        gender: identical(gender, _absent) ? this.gender : gender as String?,
        age: identical(age, _absent) ? this.age : age as int?,
        isActive: isActive ?? this.isActive,
        isVacationMode: isVacationMode ?? this.isVacationMode,
        isDefaultAttendance: isDefaultAttendance ?? this.isDefaultAttendance,
        vacationScopedGroupIds:
            vacationScopedGroupIds ?? this.vacationScopedGroupIds,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        emailVerified: emailVerified ?? this.emailVerified,
        loginPreference: loginPreference ?? this.loginPreference,
        createdAt: identical(createdAt, _absent)
            ? this.createdAt
            : createdAt as DateTime?,
        groupFunctionalRole: identical(groupFunctionalRole, _absent)
            ? this.groupFunctionalRole
            : groupFunctionalRole as UserRole?,
        membershipStatus: identical(membershipStatus, _absent)
            ? this.membershipStatus
            : membershipStatus as String?,
      );

  /// Sentinel value to pass for nullable [copyWith] fields when you want to
  /// explicitly set them to `null`.
  ///
  /// ```dart
  /// // Remove user from their group:
  /// final updated = user.copyWith(groupId: UserModel.absent);
  /// ```
  static const Object absent = _absent;

  @override
  List<Object?> get props => [
        id,
        email,
        role,
        organizationId,
        groupId,
        groupIds,
        isVacationMode,
        isDefaultAttendance,
        // Part of equality: the flag alone is unchanged when a vacation's
        // SCOPE changes (approval landing on one group), and the Settings
        // toggle must repaint for that.
        vacationScopedGroupIds,
        remindersEnabled,
        emailVerified,
        loginPreference,
        groupFunctionalRole,
        // ISSUE-1: part of equality so a status flip repaints the tile.
        membershipStatus,
      ];
}
