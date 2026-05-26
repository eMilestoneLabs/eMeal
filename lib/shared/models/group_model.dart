import 'package:equatable/equatable.dart';

// ── GroupType ──────────────────────────────────────────────────────────────────

enum GroupType {
  hostel,
  mess,
  cafeteria,
  pg,
  coachingInstitute,
  office,
  // ignore: constant_identifier_names
  factory_,
  community,
  event,
  other;

  String get label {
    switch (this) {
      case GroupType.hostel:
        return 'Hostel';
      case GroupType.mess:
        return 'Mess';
      case GroupType.cafeteria:
        return 'Cafeteria';
      case GroupType.pg:
        return 'PG';
      case GroupType.coachingInstitute:
        return 'Coaching Institute';
      case GroupType.office:
        return 'Office';
      case GroupType.factory_:
        return 'Factory';
      case GroupType.community:
        return 'Community';
      case GroupType.event:
        return 'Event';
      case GroupType.other:
        return 'Other';
    }
  }
}

// ── MealPreferenceOption ───────────────────────────────────────────────────────

/// Meal preference options members select when marking attendance.
///
/// These exactly match the PRD-specified options for preference analytics.
/// Admin can enable any subset of these for their group via [GroupMealConfig].
enum MealPreferenceOption {
  /// Pure vegetarian — no meat, fish, or eggs.
  veg,

  /// Chicken dishes.
  chicken,

  /// Fish dishes.
  fish,

  /// Mutton dishes.
  mutton,

  /// Egg-inclusive vegetarian.
  egg,

  /// Jain vegetarian — no root vegetables.
  jain;

  String get label {
    switch (this) {
      case MealPreferenceOption.veg:
        return 'Veg';
      case MealPreferenceOption.chicken:
        return 'Chicken';
      case MealPreferenceOption.fish:
        return 'Fish';
      case MealPreferenceOption.mutton:
        return 'Mutton';
      case MealPreferenceOption.egg:
        return 'Egg';
      case MealPreferenceOption.jain:
        return 'Jain';
    }
  }

  String get emoji {
    switch (this) {
      case MealPreferenceOption.veg:
        return '🥗';
      case MealPreferenceOption.chicken:
        return '🍗';
      case MealPreferenceOption.fish:
        return '🐟';
      case MealPreferenceOption.mutton:
        return '🍖';
      case MealPreferenceOption.egg:
        return '🥚';
      case MealPreferenceOption.jain:
        return '🙏';
    }
  }

  /// Whether this option is vegetarian (for veg/non-veg count reporting).
  bool get isVegetarian =>
      this == MealPreferenceOption.veg || this == MealPreferenceOption.jain;
}

// ── GroupMealConfig ────────────────────────────────────────────────────────────

/// Meal system configuration for a group.
///
/// No hardcoded attendance windows — windows live on each [MealModel].
class GroupMealConfig extends Equatable {
  const GroupMealConfig({
    this.mealsEnabled = true,
    this.weeklyMenuEnabled = true,
    this.preferencesEnabled = false,
    this.enabledPreferences = const [],
    this.vacationModeEnabled = false,
  });

  final bool mealsEnabled;

  /// When false, the Weekly Menu tab and any menu-related UI are hidden.
  final bool weeklyMenuEnabled;

  final bool preferencesEnabled;
  final List<MealPreferenceOption> enabledPreferences;
  final bool vacationModeEnabled;

  factory GroupMealConfig.fromJson(Map<String, dynamic> j) => GroupMealConfig(
        mealsEnabled: j['mealsEnabled'] ?? true,
        weeklyMenuEnabled: j['weeklyMenuEnabled'] ?? true,
        preferencesEnabled: j['preferencesEnabled'] ?? false,
        enabledPreferences: (j['enabledPreferences'] as List? ?? [])
            .map((e) => MealPreferenceOption.values.firstWhere(
                  (p) => p.name == e,
                  orElse: () => MealPreferenceOption.veg,
                ))
            .toList(),
        vacationModeEnabled: j['vacationModeEnabled'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'mealsEnabled': mealsEnabled,
        'weeklyMenuEnabled': weeklyMenuEnabled,
        'preferencesEnabled': preferencesEnabled,
        'enabledPreferences': enabledPreferences.map((e) => e.name).toList(),
        'vacationModeEnabled': vacationModeEnabled,
      };

  GroupMealConfig copyWith({
    bool? mealsEnabled,
    bool? weeklyMenuEnabled,
    bool? preferencesEnabled,
    List<MealPreferenceOption>? enabledPreferences,
    bool? vacationModeEnabled,
  }) =>
      GroupMealConfig(
        mealsEnabled: mealsEnabled ?? this.mealsEnabled,
        weeklyMenuEnabled: weeklyMenuEnabled ?? this.weeklyMenuEnabled,
        preferencesEnabled: preferencesEnabled ?? this.preferencesEnabled,
        enabledPreferences: enabledPreferences ?? this.enabledPreferences,
        vacationModeEnabled: vacationModeEnabled ?? this.vacationModeEnabled,
      );

  @override
  List<Object?> get props => [
        mealsEnabled,
        weeklyMenuEnabled,
        preferencesEnabled,
        enabledPreferences,
        vacationModeEnabled,
      ];
}

// ── GroupModel ─────────────────────────────────────────────────────────────────

class GroupModel extends Equatable {
  const GroupModel({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.type,
    required this.mealConfig,
    required this.memberIds,
    this.blockedMemberIds = const [],
    this.description,
    this.adminId,
    this.maxMembers,
    this.isActive = true,
    this.joinCode,
    this.createdAt,
  });

  final String id;
  final String organizationId;
  final String name;
  final GroupType type;
  final GroupMealConfig mealConfig;
  final List<String> memberIds;

  /// Member IDs blocked by the admin from attending/joining.
  ///
  /// Blocked members cannot mark attendance or re-join this group.
  /// In production this is persisted on the backend.
  final List<String> blockedMemberIds;

  final String? description;
  final String? adminId;
  final int? maxMembers;
  final bool isActive;
  final String? joinCode;
  final DateTime? createdAt;

  int get memberCount => memberIds.length;

  factory GroupModel.fromJson(Map<String, dynamic> j) => GroupModel(
        id: j['id'] ?? '',
        organizationId: j['organizationId'] ?? '',
        name: j['name'] ?? 'Group',
        type: GroupType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => GroupType.hostel,
        ),
        mealConfig: j['mealConfig'] != null
            ? GroupMealConfig.fromJson(j['mealConfig'])
            : const GroupMealConfig(),
        memberIds: List<String>.from(j['memberIds'] ?? []),
        blockedMemberIds: List<String>.from(j['blockedMemberIds'] ?? []),
        description: j['description'],
        adminId: j['adminId'],
        maxMembers: j['maxMembers'],
        isActive: j['isActive'] ?? true,
        joinCode: j['joinCode'],
        createdAt:
            j['createdAt'] != null ? DateTime.parse(j['createdAt']) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'name': name,
        'type': type.name,
        'mealConfig': mealConfig.toJson(),
        'memberIds': memberIds,
        'blockedMemberIds': blockedMemberIds,
        'description': description,
        'adminId': adminId,
        'maxMembers': maxMembers,
        'isActive': isActive,
        'joinCode': joinCode,
        'createdAt': createdAt?.toIso8601String(),
      };

  GroupModel copyWith({
    String? name,
    GroupType? type,
    GroupMealConfig? mealConfig,
    List<String>? memberIds,
    List<String>? blockedMemberIds,
    String? description,
    int? maxMembers,
    bool? isActive,
    String? joinCode,
  }) =>
      GroupModel(
        id: id,
        organizationId: organizationId,
        name: name ?? this.name,
        type: type ?? this.type,
        mealConfig: mealConfig ?? this.mealConfig,
        memberIds: memberIds ?? this.memberIds,
        blockedMemberIds: blockedMemberIds ?? this.blockedMemberIds,
        description: description ?? this.description,
        adminId: adminId,
        maxMembers: maxMembers ?? this.maxMembers,
        isActive: isActive ?? this.isActive,
        joinCode: joinCode ?? this.joinCode,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [
        id,
        organizationId,
        name,
        type,
        mealConfig,
        memberIds,
        blockedMemberIds,
        isActive,
      ];
}
