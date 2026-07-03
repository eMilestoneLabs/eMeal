import 'package:equatable/equatable.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

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

  /// SINGLE SOURCE OF TRUTH for preference-tag display across the whole app
  /// (Meal Config, Planner, Daily Overrides, Student Attendance, Reports).
  /// Case-insensitive emoji for known standard tags; ANY custom tag is allowed
  /// and shown with its exact name and no emoji. No fixed 6-value restriction.
  static const Map<String, String> standardEmoji = {
    'veg': '🥗',
    'non-veg': '🍖',
    'nonveg': '🍖',
    'egg': '🥚',
    'fish': '🐟',
    'chicken': '🍗',
    'mutton': '🥩',
    'jain': '🌱',
    'vegan': '🥬',
  };

  /// Display (emoji, label) for ANY preference key — standard or custom.
  /// Emoji is auto-assigned when the (case-insensitive) name matches a known
  /// standard tag; unknown custom tags get an empty emoji (name only).
  static ({String emoji, String label}) display(String key) {
    final t = key.trim();
    final emoji = standardEmoji[t.toLowerCase()] ?? '';
    final label = t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
    return (emoji: emoji, label: label);
  }

  /// Parse a list of preference keys (as sent by the backend on a meal's
  /// enabledPreferences) into options, dropping any unknown keys.
  ///
  /// Case-INSENSITIVE: tolerates legacy capitalized values ("Veg", "Egg") that
  /// older app builds saved, as well as the current lowercase keys, so existing
  /// published schedules keep working without a re-save.
  static List<MealPreferenceOption> parseList(List<String> names) {
    final out = <MealPreferenceOption>[];
    for (final n in names) {
      final key = n.trim().toLowerCase();
      for (final p in MealPreferenceOption.values) {
        if (p.name == key) {
          out.add(p);
          break;
        }
      }
    }
    return out;
  }
}

// ── GroupMealConfig ────────────────────────────────────────────────────────────

/// Meal system configuration for a group.
///
/// No hardcoded attendance windows — windows live on each [MealModel].
class GroupMealConfig extends Equatable {
  // SRS FR-MODE-005: an UNRESOLVED config (no payload yet / partial load)
  // degrades to Attendance-Only — never show meal UI the mode can't support.
  // Real group configs always arrive with explicit values from the backend.
  const GroupMealConfig({
    this.mealsEnabled = false,
    this.weeklyMenuEnabled = true,
    this.dayWiseMealsEnabled = false,
    this.preferencesEnabled = false,
    this.enabledPreferences = const [],
    this.vacationModeEnabled = false,
    this.mealPricingEnabled = false,
  });

  final bool mealsEnabled;

  /// When false, the Weekly Menu tab and any menu-related UI are hidden.
  final bool weeklyMenuEnabled;

  /// Day-Wise Meal Mode — mutually exclusive with [weeklyMenuEnabled].
  /// When true, students see only today's configured meals and the Weekly
  /// Menu tab is hidden.
  final bool dayWiseMealsEnabled;

  final bool preferencesEnabled;
  final List<MealPreferenceOption> enabledPreferences;
  final bool vacationModeEnabled;

  /// Additive: when true, meals carry a ₹ price shown to students and used for
  /// billing/exports. When false, no price UI appears anywhere.
  final bool mealPricingEnabled;

  factory GroupMealConfig.fromJson(Map<String, dynamic> j) => GroupMealConfig(
        // FR-MODE-005: a partial payload missing the mode flag = unresolved
        // mode → safe Attendance-Only default (backend always sends it).
        mealsEnabled: j['mealsEnabled'] ?? false,
        weeklyMenuEnabled: j['weeklyMenuEnabled'] ?? true,
        dayWiseMealsEnabled: j['dayWiseMealsEnabled'] ?? false,
        preferencesEnabled: j['preferencesEnabled'] ?? false,
        enabledPreferences: MealPreferenceOption.parseList(
          (j['enabledPreferences'] as List? ?? [])
              .map((e) => e.toString())
              .toList(),
        ),
        vacationModeEnabled: j['vacationModeEnabled'] ?? false,
        mealPricingEnabled: j['mealPricingEnabled'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'mealsEnabled': mealsEnabled,
        'weeklyMenuEnabled': weeklyMenuEnabled,
        'dayWiseMealsEnabled': dayWiseMealsEnabled,
        'preferencesEnabled': preferencesEnabled,
        'enabledPreferences': enabledPreferences.map((e) => e.name).toList(),
        'vacationModeEnabled': vacationModeEnabled,
        'mealPricingEnabled': mealPricingEnabled,
      };

  GroupMealConfig copyWith({
    bool? mealsEnabled,
    bool? weeklyMenuEnabled,
    bool? dayWiseMealsEnabled,
    bool? preferencesEnabled,
    List<MealPreferenceOption>? enabledPreferences,
    bool? vacationModeEnabled,
    bool? mealPricingEnabled,
  }) =>
      GroupMealConfig(
        mealsEnabled: mealsEnabled ?? this.mealsEnabled,
        weeklyMenuEnabled: weeklyMenuEnabled ?? this.weeklyMenuEnabled,
        dayWiseMealsEnabled: dayWiseMealsEnabled ?? this.dayWiseMealsEnabled,
        preferencesEnabled: preferencesEnabled ?? this.preferencesEnabled,
        enabledPreferences: enabledPreferences ?? this.enabledPreferences,
        vacationModeEnabled: vacationModeEnabled ?? this.vacationModeEnabled,
        mealPricingEnabled: mealPricingEnabled ?? this.mealPricingEnabled,
      );

  @override
  List<Object?> get props => [
        mealsEnabled,
        weeklyMenuEnabled,
        dayWiseMealsEnabled,
        preferencesEnabled,
        enabledPreferences,
        vacationModeEnabled,
        mealPricingEnabled,
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
    this.functionalRole,
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

  /// The CURRENT user's functional role for THIS group (#8), e.g. hostelAdmin
  /// in one group, messManager in another. null -> use the global user role.
  final UserRole? functionalRole;

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
        functionalRole: UserRole.fromName(j['functionalRole'] as String?),
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
        'functionalRole': functionalRole?.name,
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
    UserRole? functionalRole,
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
        functionalRole: functionalRole ?? this.functionalRole,
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
        functionalRole,
      ];
}
