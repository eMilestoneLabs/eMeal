import 'package:equatable/equatable.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

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
    this.avatarUrl,
    this.phone,
    this.gender,
    this.age,
    this.isActive = true,
    this.isVacationMode = false,
    this.isDefaultAttendance = false,
    this.remindersEnabled = true,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String organizationId;
  final String? groupId;
  final List<String> groupIds;
  final String? avatarUrl;
  final String? phone;

  /// Gender collected at signup (e.g. 'Male', 'Female', 'Other').
  final String? gender;

  /// Age collected at signup.
  final int? age;

  final bool isActive;
  final bool isVacationMode;
  final bool isDefaultAttendance;

  /// Whether attendance-window reminders are enabled for this user.
  ///
  /// Persisted in user model so the preference survives cold restarts.
  final bool remindersEnabled;

  final DateTime? createdAt;

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
        avatarUrl: j['avatarUrl'],
        phone: j['phone'],
        gender: j['gender'],
        age: j['age'] as int?,
        isActive: j['isActive'] ?? true,
        isVacationMode: j['isVacationMode'] ?? false,
        isDefaultAttendance: j['isDefaultAttendance'] ?? false,
        remindersEnabled: j['remindersEnabled'] ?? true,
        createdAt:
            j['createdAt'] != null ? DateTime.parse(j['createdAt']) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.name,
        'organizationId': organizationId,
        'groupId': groupId,
        'groupIds': groupIds,
        'avatarUrl': avatarUrl,
        'phone': phone,
        'gender': gender,
        'age': age,
        'isActive': isActive,
        'isVacationMode': isVacationMode,
        'isDefaultAttendance': isDefaultAttendance,
        'remindersEnabled': remindersEnabled,
        'createdAt': createdAt?.toIso8601String(),
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
    bool? remindersEnabled,
    /// Pass [UserModel.absent] to explicitly clear this field to null.
    Object? createdAt = _absent,
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
        avatarUrl: identical(avatarUrl, _absent)
            ? this.avatarUrl
            : avatarUrl as String?,
        phone: identical(phone, _absent) ? this.phone : phone as String?,
        gender: identical(gender, _absent) ? this.gender : gender as String?,
        age: identical(age, _absent) ? this.age : age as int?,
        isActive: isActive ?? this.isActive,
        isVacationMode: isVacationMode ?? this.isVacationMode,
        isDefaultAttendance: isDefaultAttendance ?? this.isDefaultAttendance,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        createdAt: identical(createdAt, _absent)
            ? this.createdAt
            : createdAt as DateTime?,
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
        remindersEnabled,
      ];
}
