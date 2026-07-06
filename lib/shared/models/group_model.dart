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

// ── GroupGuestConfig ───────────────────────────────────────────────────────────

/// Module 22 (FR-HG-020, Pass 9): per-group hosted-guest configuration.
///
/// Mirrors the backend's nested `mealConfig.guestConfig` payload
/// (GroupSerializer.guestConfig — additive key, server defaults resolved).
class GroupGuestConfig extends Equatable {
  const GroupGuestConfig({
    this.guestAttendanceEnabled = false,
    this.maxGuestsPerMemberPerMeal = 5,
    this.maxGuestsPerMemberPerDay,
    this.guestPricingMode = 'sameAsMember',
    this.guestAdultPrice,
    this.guestChildPrice,
    this.guestSurcharge,
    this.guestRequiresApproval = false,
    this.guestCutoffMinutesBeforeClose = 0,
    this.guestAdvanceBookingDays = 0,
    this.guestPreferenceRequired = false,
    this.allowGuestWithoutHost = false,
    this.billNoShowGuests = true,
  });

  final bool guestAttendanceEnabled;
  final int maxGuestsPerMemberPerMeal;
  final int? maxGuestsPerMemberPerDay;

  /// sameAsMember | perGuestPrice | flatSurcharge (FR-HG-051).
  final String guestPricingMode;
  final int? guestAdultPrice;
  final int? guestChildPrice;
  final int? guestSurcharge;
  final bool guestRequiresApproval;
  final int guestCutoffMinutesBeforeClose;
  final int guestAdvanceBookingDays;
  final bool guestPreferenceRequired;
  final bool allowGuestWithoutHost;
  final bool billNoShowGuests;

  static int? _asIntOrNull(dynamic v) =>
      v == null ? null : (v is int ? v : int.tryParse(v.toString()));

  /// FR-HG-034: client-side price estimate for the cost preview — mirrors the
  /// backend's resolveGuestPrice exactly. Null = headcount-only (pricing off).
  int? estimatePrice({
    required int? mealPrice,
    required bool isAdult,
    required bool pricingEnabled,
  }) {
    if (!pricingEnabled) return null;
    switch (guestPricingMode) {
      case 'perGuestPrice':
        return isAdult
            ? (guestAdultPrice ?? mealPrice)
            : (guestChildPrice ?? guestAdultPrice ?? mealPrice);
      case 'flatSurcharge':
        return (mealPrice ?? 0) + (guestSurcharge ?? 0);
      default: // sameAsMember
        return mealPrice;
    }
  }

  factory GroupGuestConfig.fromJson(Map<String, dynamic> j) =>
      GroupGuestConfig(
        guestAttendanceEnabled: j['guestAttendanceEnabled'] ?? false,
        maxGuestsPerMemberPerMeal:
            _asIntOrNull(j['maxGuestsPerMemberPerMeal']) ?? 5,
        maxGuestsPerMemberPerDay: _asIntOrNull(j['maxGuestsPerMemberPerDay']),
        guestPricingMode:
            j['guestPricingMode']?.toString() ?? 'sameAsMember',
        guestAdultPrice: _asIntOrNull(j['guestAdultPrice']),
        guestChildPrice: _asIntOrNull(j['guestChildPrice']),
        guestSurcharge: _asIntOrNull(j['guestSurcharge']),
        guestRequiresApproval: j['guestRequiresApproval'] ?? false,
        guestCutoffMinutesBeforeClose:
            _asIntOrNull(j['guestCutoffMinutesBeforeClose']) ?? 0,
        guestAdvanceBookingDays:
            _asIntOrNull(j['guestAdvanceBookingDays']) ?? 0,
        guestPreferenceRequired: j['guestPreferenceRequired'] ?? false,
        allowGuestWithoutHost: j['allowGuestWithoutHost'] ?? false,
        billNoShowGuests: j['billNoShowGuests'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'guestAttendanceEnabled': guestAttendanceEnabled,
        'maxGuestsPerMemberPerMeal': maxGuestsPerMemberPerMeal,
        'maxGuestsPerMemberPerDay': maxGuestsPerMemberPerDay,
        'guestPricingMode': guestPricingMode,
        'guestAdultPrice': guestAdultPrice,
        'guestChildPrice': guestChildPrice,
        'guestSurcharge': guestSurcharge,
        'guestRequiresApproval': guestRequiresApproval,
        'guestCutoffMinutesBeforeClose': guestCutoffMinutesBeforeClose,
        'guestAdvanceBookingDays': guestAdvanceBookingDays,
        'guestPreferenceRequired': guestPreferenceRequired,
        'allowGuestWithoutHost': allowGuestWithoutHost,
        'billNoShowGuests': billNoShowGuests,
      };

  GroupGuestConfig copyWith({
    bool? guestAttendanceEnabled,
    int? maxGuestsPerMemberPerMeal,
    int? maxGuestsPerMemberPerDay,
    String? guestPricingMode,
    int? guestAdultPrice,
    int? guestChildPrice,
    int? guestSurcharge,
    bool? guestRequiresApproval,
    int? guestCutoffMinutesBeforeClose,
    int? guestAdvanceBookingDays,
    bool? guestPreferenceRequired,
    bool? allowGuestWithoutHost,
    bool? billNoShowGuests,
  }) =>
      GroupGuestConfig(
        guestAttendanceEnabled:
            guestAttendanceEnabled ?? this.guestAttendanceEnabled,
        maxGuestsPerMemberPerMeal:
            maxGuestsPerMemberPerMeal ?? this.maxGuestsPerMemberPerMeal,
        maxGuestsPerMemberPerDay:
            maxGuestsPerMemberPerDay ?? this.maxGuestsPerMemberPerDay,
        guestPricingMode: guestPricingMode ?? this.guestPricingMode,
        guestAdultPrice: guestAdultPrice ?? this.guestAdultPrice,
        guestChildPrice: guestChildPrice ?? this.guestChildPrice,
        guestSurcharge: guestSurcharge ?? this.guestSurcharge,
        guestRequiresApproval:
            guestRequiresApproval ?? this.guestRequiresApproval,
        guestCutoffMinutesBeforeClose: guestCutoffMinutesBeforeClose ??
            this.guestCutoffMinutesBeforeClose,
        guestAdvanceBookingDays:
            guestAdvanceBookingDays ?? this.guestAdvanceBookingDays,
        guestPreferenceRequired:
            guestPreferenceRequired ?? this.guestPreferenceRequired,
        allowGuestWithoutHost:
            allowGuestWithoutHost ?? this.allowGuestWithoutHost,
        billNoShowGuests: billNoShowGuests ?? this.billNoShowGuests,
      );

  @override
  List<Object?> get props => [
        guestAttendanceEnabled,
        maxGuestsPerMemberPerMeal,
        maxGuestsPerMemberPerDay,
        guestPricingMode,
        guestAdultPrice,
        guestChildPrice,
        guestSurcharge,
        guestRequiresApproval,
        guestCutoffMinutesBeforeClose,
        guestAdvanceBookingDays,
        guestPreferenceRequired,
        allowGuestWithoutHost,
        billNoShowGuests,
      ];
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
    this.vacationRequiresApproval = false,
    this.billingCycleStartDay,
    this.mealPricingEnabled = false,
    this.attendanceDefault = 'absent',
    this.guestConfig = const GroupGuestConfig(),
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

  /// Pass 11 (FR-VACX-001): when true, members must use a dated vacation
  /// request (admin-approved) — the instant self-service toggle is disabled.
  final bool vacationRequiresApproval;

  /// Pass 12 (FR-BILLX-020): day-of-month (1–28) the billing cycle starts.
  /// Null = calendar month. Period math happens server-side in org time.
  final int? billingCycleStartDay;

  /// Additive: when true, meals carry a ₹ price shown to students and used for
  /// billing/exports. When false, no price UI appears anywhere.
  final bool mealPricingEnabled;

  /// SRS FR-TRUST-001 (Pass 7): group trust model. 'absent' = opt-in (legacy —
  /// not marking means not counted/billed); 'present' = opt-out (unmarked
  /// members are auto-marked Present at window close, reversibly).
  final String attendanceDefault;

  /// Module 22 (FR-HG-020, Pass 9): hosted-guest settings — nested additive
  /// key from the backend; a missing payload degrades to guests-disabled.
  final GroupGuestConfig guestConfig;

  bool get isOptOut => attendanceDefault == 'present';

  /// Hosted guests are usable only in Meal Mode with the feature flag on.
  bool get guestsEnabled =>
      mealsEnabled && guestConfig.guestAttendanceEnabled;

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
        vacationRequiresApproval: j['vacationRequiresApproval'] ?? false,
        billingCycleStartDay: (j['billingCycleStartDay'] is num)
            ? (j['billingCycleStartDay'] as num).toInt()
            : null,
        mealPricingEnabled: j['mealPricingEnabled'] ?? false,
        attendanceDefault: j['attendanceDefault']?.toString() ?? 'absent',
        guestConfig: j['guestConfig'] is Map
            ? GroupGuestConfig.fromJson(
                (j['guestConfig'] as Map).cast<String, dynamic>())
            : const GroupGuestConfig(),
      );

  Map<String, dynamic> toJson() => {
        'mealsEnabled': mealsEnabled,
        'weeklyMenuEnabled': weeklyMenuEnabled,
        'dayWiseMealsEnabled': dayWiseMealsEnabled,
        'preferencesEnabled': preferencesEnabled,
        'enabledPreferences': enabledPreferences.map((e) => e.name).toList(),
        'vacationModeEnabled': vacationModeEnabled,
        'vacationRequiresApproval': vacationRequiresApproval,
        // OMITTED when null — an explicit null would CLEAR the configured
        // cycle day on every unrelated toggle (FR-HG-021 bug class). Day 1 is
        // semantically identical to calendar month, so "clear" is never needed.
        if (billingCycleStartDay != null)
          'billingCycleStartDay': billingCycleStartDay,
        'mealPricingEnabled': mealPricingEnabled,
        'attendanceDefault': attendanceDefault,
        'guestConfig': guestConfig.toJson(),
      };

  GroupMealConfig copyWith({
    bool? mealsEnabled,
    bool? weeklyMenuEnabled,
    bool? dayWiseMealsEnabled,
    bool? preferencesEnabled,
    List<MealPreferenceOption>? enabledPreferences,
    bool? vacationModeEnabled,
    bool? vacationRequiresApproval,
    int? billingCycleStartDay,
    bool clearBillingCycleStartDay = false,
    bool? mealPricingEnabled,
    String? attendanceDefault,
    GroupGuestConfig? guestConfig,
  }) =>
      GroupMealConfig(
        mealsEnabled: mealsEnabled ?? this.mealsEnabled,
        weeklyMenuEnabled: weeklyMenuEnabled ?? this.weeklyMenuEnabled,
        dayWiseMealsEnabled: dayWiseMealsEnabled ?? this.dayWiseMealsEnabled,
        preferencesEnabled: preferencesEnabled ?? this.preferencesEnabled,
        enabledPreferences: enabledPreferences ?? this.enabledPreferences,
        vacationModeEnabled: vacationModeEnabled ?? this.vacationModeEnabled,
        vacationRequiresApproval:
            vacationRequiresApproval ?? this.vacationRequiresApproval,
        billingCycleStartDay: clearBillingCycleStartDay
            ? null
            : (billingCycleStartDay ?? this.billingCycleStartDay),
        mealPricingEnabled: mealPricingEnabled ?? this.mealPricingEnabled,
        attendanceDefault: attendanceDefault ?? this.attendanceDefault,
        guestConfig: guestConfig ?? this.guestConfig,
      );

  @override
  List<Object?> get props => [
        mealsEnabled,
        weeklyMenuEnabled,
        dayWiseMealsEnabled,
        preferencesEnabled,
        enabledPreferences,
        vacationModeEnabled,
        vacationRequiresApproval,
        billingCycleStartDay,
        mealPricingEnabled,
        attendanceDefault,
        guestConfig,
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
    this.adminName,
    this.organizationName,
    // ── Module 02 (Organization & Group Management) — additive ───────────────
    this.joinApprovalRequired = false,
    this.pendingCount = 0,
    this.pendingMemberIds = const [],
    this.country,
    this.state,
    this.city,
    this.pin,
    this.address,
    this.timezone,
    this.currency,
    this.qrExpiryDays,
    this.joinCodeExpiresAt,
    this.archivedAt,
    this.joinStatus,
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

  /// ISSUE 2 (additive): read-only detail context, populated only by
  /// GET /groups/:id. null on list responses / when unavailable.
  final String? adminName;
  final String? organizationName;

  // ── Module 02 (Organization & Group Management) — additive ─────────────────

  /// GRP-003/MEM-004: when true, joining creates a pending request an admin
  /// must approve.
  final bool joinApprovalRequired;

  /// MEM-008/010: pending join requests (for the admin approvals badge).
  final int pendingCount;
  final List<String> pendingMemberIds;

  /// GRP-003: extended metadata captured at creation (immutable afterward).
  final String? country;
  final String? state;
  final String? city;

  /// GRP-003 (command_3 Issue 8): postal / PIN code captured at creation.
  final String? pin;
  final String? address;
  final String? timezone;
  final String? currency;

  /// GRP-013/CFG-014: QR expiry policy (days; null = Never) + concrete deadline.
  final int? qrExpiryDays;
  final DateTime? joinCodeExpiresAt;

  /// GRP-016: archive timestamp (null while active).
  final DateTime? archivedAt;

  /// MEM-004: transient join outcome returned by POST /groups/join —
  /// 'active' (joined) or 'pending' (awaiting admin approval). null elsewhere.
  final String? joinStatus;

  /// True when the most recent join created a pending approval request.
  bool get isPendingApproval => joinStatus == 'pending';

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
        adminName: j['adminName'] as String?,
        organizationName: j['organizationName'] as String?,
        joinApprovalRequired: j['joinApprovalRequired'] ?? false,
        pendingCount: j['pendingCount'] ?? 0,
        pendingMemberIds: List<String>.from(j['pendingMemberIds'] ?? []),
        country: j['country'] as String?,
        state: j['state'] as String?,
        city: j['city'] as String?,
        pin: j['pin'] as String?,
        address: j['address'] as String?,
        timezone: j['timezone'] as String?,
        currency: j['currency'] as String?,
        qrExpiryDays: j['qrExpiryDays'] as int?,
        joinCodeExpiresAt: j['joinCodeExpiresAt'] != null
            ? DateTime.tryParse(j['joinCodeExpiresAt'])
            : null,
        archivedAt: j['archivedAt'] != null
            ? DateTime.tryParse(j['archivedAt'])
            : null,
        joinStatus: j['joinStatus'] as String?,
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
        'adminName': adminName,
        'organizationName': organizationName,
        'joinApprovalRequired': joinApprovalRequired,
        'pendingCount': pendingCount,
        'pendingMemberIds': pendingMemberIds,
        'country': country,
        'state': state,
        'city': city,
        'pin': pin,
        'address': address,
        'timezone': timezone,
        'currency': currency,
        'qrExpiryDays': qrExpiryDays,
        'joinCodeExpiresAt': joinCodeExpiresAt?.toIso8601String(),
        'archivedAt': archivedAt?.toIso8601String(),
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
    String? adminName,
    String? organizationName,
    bool? joinApprovalRequired,
    int? pendingCount,
    List<String>? pendingMemberIds,
    DateTime? joinCodeExpiresAt,
    DateTime? archivedAt,
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
        adminName: adminName ?? this.adminName,
        organizationName: organizationName ?? this.organizationName,
        // Module 02: preserve immutable metadata through copies; allow the
        // few mutable lifecycle fields to be overridden.
        joinApprovalRequired: joinApprovalRequired ?? this.joinApprovalRequired,
        pendingCount: pendingCount ?? this.pendingCount,
        pendingMemberIds: pendingMemberIds ?? this.pendingMemberIds,
        country: country,
        state: state,
        city: city,
        pin: pin,
        address: address,
        timezone: timezone,
        currency: currency,
        qrExpiryDays: qrExpiryDays,
        joinCodeExpiresAt: joinCodeExpiresAt ?? this.joinCodeExpiresAt,
        archivedAt: archivedAt ?? this.archivedAt,
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
        joinApprovalRequired,
        pendingCount,
        archivedAt,
      ];
}
