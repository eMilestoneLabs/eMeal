import 'package:equatable/equatable.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

// ── MemberSettingOverrides ─────────────────────────────────────────────────────

/// A member's RAW per-group overrides for vacation / auto-attendance.
///
/// `null` on a field means "inherit the user-level flag" — the value the
/// session already carries. Keeping the raw override (rather than a
/// pre-resolved boolean) is deliberate: it lets the client distinguish
/// "explicitly off for this group" from "never set", which is exactly the
/// distinction that stops one group's setting governing another.
class MemberSettingOverrides extends Equatable {
  const MemberSettingOverrides({this.isVacationMode, this.isDefaultAttendance});

  final bool? isVacationMode;
  final bool? isDefaultAttendance;

  static MemberSettingOverrides? fromJson(Map<String, dynamic>? j) =>
      j == null
          ? null
          : MemberSettingOverrides(
              isVacationMode: j['isVacationMode'] as bool?,
              isDefaultAttendance: j['isDefaultAttendance'] as bool?,
            );

  Map<String, dynamic> toJson() => {
        'isVacationMode': isVacationMode,
        'isDefaultAttendance': isDefaultAttendance,
      };

  /// `override ?? userFlag` — the single resolution rule, mirroring the
  /// server's `resolveMemberFlag`. `??` (never `||`): an explicit per-group
  /// `false` must beat an inherited `true`, or turning a setting off for one
  /// group would silently fall back to the shared flag and re-enable it.
  static bool resolve(bool? override, bool userFlag) => override ?? userFlag;

  /// Vacation for ONE group — the same answer the server reaches in
  /// `getVacationCoveredUserIds`, computed on the client with no extra call.
  ///
  /// `userFlag` is a single user-level bit that the server sets from ANY
  /// covering approved request, including one scoped to a single group. So
  /// `override ?? userFlag` alone reports "on vacation" in a group the member
  /// never requested leave from. [scopedGroupIds] (from
  /// `UserModel.vacationScopedGroupIds`) names the groups the flag applies to.
  ///
  ///   • an explicit per-group override always wins;
  ///   • null scope → governs every group (pure toggle, ORG-LEVEL request, or
  ///     an older server omitting the field) — the previous behaviour;
  ///   • an unknown [groupId] falls back to the flag rather than guessing OFF,
  ///     because Settings is reachable by deep-link before the group resolves;
  ///   • otherwise the scope decides, WITHOUT consulting the flag: activation
  ///     lag must never change what the member sees, which is the same reason
  ///     the server ignores the flag once a request governs the date.
  ///
  /// Lives here, not in the provider, so the rule has exactly one definition —
  /// a second hand-written copy is how the client and server drift apart.
  static bool resolveVacationForGroup({
    required bool? override,
    required bool userFlag,
    required List<String>? scopedGroupIds,
    required String groupId,
  }) {
    if (override != null) return override;
    if (scopedGroupIds == null) return userFlag;
    if (groupId.isEmpty) return userFlag;
    return scopedGroupIds.contains(groupId);
  }

  @override
  List<Object?> get props => [isVacationMode, isDefaultAttendance];
}

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

  /// ISSUE-008: reserved key of the SYSTEM "None" choice — always offered
  /// last on standalone preference pickers ("attending, no preference item").
  static const String noneKey = 'none';

  /// ISSUE-005 (Live-Test-13): the group-mode storage key for the same system
  /// option. Standalone stores 'none', Preference Groups store '__none__' —
  /// both are the SAME system value and are deliberately NOT migrated (the key
  /// is already persisted across attendance, guests, corrections, billing,
  /// reports, exports and offline caches; rewriting it buys nothing the user
  /// can see and risks all of them).
  static const String noneGroupKey = '__none__';

  /// SINGLE SOURCE OF TRUTH for "is this the system NONE?".
  ///
  /// Every validator, counter and picker must call this instead of comparing
  /// raw strings — scattered `== 'none'` checks are how one entry point (the
  /// Today's Meals tab) ended up without the option at all. Case- and
  /// whitespace-tolerant; mirrors the backend's `isSystemNonePreference()`.
  static bool isSystemNone(String? key) {
    if (key == null) return false;
    final v = key.trim().toLowerCase();
    return v == noneKey || v == noneGroupKey;
  }

  /// Display (emoji, label) for ANY preference key — standard or custom.
  /// Emoji is auto-assigned when the (case-insensitive) name matches a known
  /// standard tag; unknown custom tags get an empty emoji (name only).
  static ({String emoji, String label}) display(String key) {
    final t = key.trim();
    // ISSUE-008: both the flat 'none' key and the group-mode '__none__'
    // snapshot key render as the same clean "None" label everywhere — the
    // internal key is never shown to the user.
    if (isSystemNone(t)) {
      return (emoji: '🚫', label: 'None');
    }
    final lower = t.toLowerCase();
    final emoji = standardEmoji[lower] ?? '';
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
    this.guestSurchargeType = 'fixed',
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

  /// SRS Module 03 GST-011: 'fixed' (₹) | 'percent' (% of effective price).
  final String guestSurchargeType;
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
        // GST-011: fixed ₹ (default) or percentage of the effective price.
        final base = mealPrice ?? 0;
        if (guestSurchargeType == 'percent') {
          return base + ((base * (guestSurcharge ?? 0)) / 100).round();
        }
        return base + (guestSurcharge ?? 0);
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
        guestSurchargeType: j['guestSurchargeType']?.toString() ?? 'fixed',
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
        'guestSurchargeType': guestSurchargeType,
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
    String? guestSurchargeType,
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
        guestSurchargeType: guestSurchargeType ?? this.guestSurchargeType,
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
        guestSurchargeType,
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
    this.billingCycleChangeUsed = false,
    this.mealPricingEnabled = false,
    this.mealPricingLocked = false,
    this.billSkippedMeals = false,
    this.billAbsentMeals = false,
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

  /// Pass 12 (FR-BILLX-020) + SRS Module 03 BILL-012: day-of-month (1–31)
  /// the billing cycle starts; days missing from a short month clamp to its
  /// last calendar day server-side. Null = calendar month.
  final int? billingCycleStartDay;

  /// True once this group has consumed its ONE-TIME billing-cycle-start-day
  /// change. Server-side truth (`billingCycleChangedAt`) — the client only
  /// mirrors it to lock the control; the backend rejects any further change.
  final bool billingCycleChangeUsed;

  /// Additive: when true, meals carry a ₹ price shown to students and used for
  /// billing/exports. When false, no price UI appears anywhere.
  final bool mealPricingEnabled;

  /// Live-Test-16 ISSUE-1: true once this group's FIRST meal schedule has been
  /// successfully published — the moment [mealPricingEnabled] became permanent.
  /// Server-side truth (`firstSchedulePublishedAt`); the client only mirrors it
  /// to lock the toggle and skip the First-Publish review. The backend rejects
  /// any locked flip regardless of what the app sends, so reinstalling the app
  /// or clearing the cache cannot restore the choice.
  ///
  /// Only the ON/OFF MODE is locked — individual meal prices stay editable.
  final bool mealPricingLocked;

  /// SRS Module 03 (survey Q17/Q22): "Bill Skip" policy — when true,
  /// system-generated Skip meals are billed at the final scheduled price.
  /// Default false (matches live behaviour).
  final bool billSkippedMeals;

  /// Live-Test-7 ISSUE-4: independent "Bill Absent" policy — when true,
  /// meals a member explicitly marked Absent are billed. The backend sends
  /// the EFFECTIVE value (an unset group follows [billSkippedMeals]), so
  /// this is always display- and calculation-ready.
  final bool billAbsentMeals;

  /// SRS FR-TRUST-001 (Pass 7): group trust model. 'absent' = opt-in (legacy —
  /// not marking means not counted/billed); 'present' = opt-out (unmarked
  /// members are auto-marked Present at window close, reversibly).
  final String attendanceDefault;

  /// Module 22 (FR-HG-020, Pass 9): hosted-guest settings — nested additive
  /// key from the backend; a missing payload degrades to guests-disabled.
  final GroupGuestConfig guestConfig;

  bool get isOptOut => attendanceDefault == 'present';

  /// Live-Test-17 ISSUE-3: the Billing Cycle is DRAFT (freely re-configurable)
  /// until the group's first successful meal-schedule publish, then PERMANENT.
  ///
  /// Deliberately derived from [mealPricingLocked] rather than from a new wire
  /// field: both locks are the same server event (`firstSchedulePublishedAt`),
  /// which the payload already carries — so this costs zero extra bytes and
  /// cannot drift out of lock-step with the pricing lock.
  ///
  /// [billingCycleChangeUsed] is intentionally NOT consulted. The former
  /// one-time-change privilege it recorded has been superseded; a legacy group
  /// that consumed it but never published is DRAFT again, exactly as the
  /// backend now decides. Reading it here would lock a control the server
  /// happily accepts.
  bool get billingCycleLocked => mealPricingLocked;

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
        billingCycleChangeUsed: j['billingCycleChangeUsed'] == true,
        billingCycleStartDay: (j['billingCycleStartDay'] is num)
            ? (j['billingCycleStartDay'] as num).toInt()
            : null,
        mealPricingEnabled: j['mealPricingEnabled'] ?? false,
        // Live-Test-16 ISSUE-1: absent on pre-fix servers → unlocked (the
        // pre-existing behaviour), so an older backend degrades gracefully.
        mealPricingLocked: j['mealPricingLocked'] == true,
        billSkippedMeals: j['billSkippedMeals'] ?? false,
        // Pre-split servers omit the key — fall back to the legacy coupling.
        billAbsentMeals:
            j['billAbsentMeals'] ?? j['billSkippedMeals'] ?? false,
        attendanceDefault: j['attendanceDefault']?.toString() ?? 'absent',
        guestConfig: j['guestConfig'] is Map
            ? GroupGuestConfig.fromJson(
                (j['guestConfig'] as Map).cast<String, dynamic>())
            : const GroupGuestConfig(),
      );

  /// Live-Test-16 ISSUE-1: keys [toJson] emits for CACHE fidelity that are
  /// read-only server truth and must never be sent in a request body (the
  /// backend mealConfig DTO is whitelist + forbidNonWhitelisted → 422).
  /// [toRequestJson] is the wire format; [toJson] is the cache format.
  static const Set<String> kServerOwnedMealConfigKeys = {
    'mealPricingLocked',
    // Pre-existing (Pass 12) gap closed alongside Live-Test-16 ISSUE-1: this
    // flag was READ by fromJson but never WRITTEN by toJson, so the SWR cache
    // round-tripped a CONSUMED one-time billing-cycle change back to `false`
    // and a cache-first paint advertised the privilege as still available.
    'billingCycleChangeUsed',
  };

  /// Wire-safe payload for POST /groups and PATCH /groups/:id — byte-identical
  /// to the pre-Live-Test-16 body.
  Map<String, dynamic> toRequestJson() {
    final json = toJson();
    for (final k in kServerOwnedMealConfigKeys) {
      json.remove(k);
    }
    // Live-Test-16 L3: once the group is locked the pricing MODE is immutable,
    // so the app stops echoing it. The whole mealConfig is re-sent on every
    // unrelated toggle (vacation approval, guest settings, meals on/off), and a
    // cached value that predates a pre-lock pricing change would otherwise read
    // as a flip attempt and 400 an edit that has nothing to do with pricing.
    //
    // This does NOT weaken the lock: a direct API call still carries the field
    // and is still rejected with MEAL_PRICING_LOCKED, so the backend remains
    // the sole authority (ISSUE-1 §9).
    if (mealPricingLocked) {
      json.remove('mealPricingEnabled');
      // Live-Test-17 ISSUE-3: the cycle day is immutable once locked, for the
      // SAME reason and by the SAME event. Stripping it is not cosmetic — the
      // whole mealConfig is re-sent on every unrelated toggle, so a cached
      // value that predates a pre-lock cycle change would read as a change
      // attempt and 400 (`BILLING_CYCLE_LOCKED`) an edit that has nothing to
      // do with billing.
      //
      // This does NOT weaken the lock: a direct API call still carries the
      // field and is still rejected, so the backend remains the sole authority.
      json.remove('billingCycleStartDay');
    }
    return json;
  }

  Map<String, dynamic> toJson() => {
        'mealsEnabled': mealsEnabled,
        'weeklyMenuEnabled': weeklyMenuEnabled,
        'dayWiseMealsEnabled': dayWiseMealsEnabled,
        'preferencesEnabled': preferencesEnabled,
        'enabledPreferences': enabledPreferences.map((e) => e.name).toList(),
        'vacationModeEnabled': vacationModeEnabled,
        'vacationRequiresApproval': vacationRequiresApproval,
        // SERVER-OWNED display flag (see [kServerOwnedMealConfigKeys]) — cached
        // so a locked billing cycle stays locked on a cache-first paint,
        // stripped from every request body.
        'billingCycleChangeUsed': billingCycleChangeUsed,
        // OMITTED when null — an explicit null would CLEAR the configured
        // cycle day on every unrelated toggle (FR-HG-021 bug class). Day 1 is
        // semantically identical to calendar month, so "clear" is never needed.
        if (billingCycleStartDay != null)
          'billingCycleStartDay': billingCycleStartDay,
        'mealPricingEnabled': mealPricingEnabled,
        // Live-Test-16 ISSUE-1: SERVER-OWNED display flag. Emitted so the SWR
        // cache round-trips the locked state (a cache-first paint must not
        // show the toggle as editable after the first publish), and STRIPPED
        // from every request body by [kServerOwnedMealConfigKeys] — the
        // backend's mealConfig DTO is whitelist+forbid and would 422 on it.
        'mealPricingLocked': mealPricingLocked,
        'billSkippedMeals': billSkippedMeals,
        'billAbsentMeals': billAbsentMeals,
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
    bool? billingCycleChangeUsed,
    bool clearBillingCycleStartDay = false,
    bool? mealPricingEnabled,
    bool? mealPricingLocked,
    bool? billSkippedMeals,
    bool? billAbsentMeals,
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
        billingCycleChangeUsed:
            billingCycleChangeUsed ?? this.billingCycleChangeUsed,
        billingCycleStartDay: clearBillingCycleStartDay
            ? null
            : (billingCycleStartDay ?? this.billingCycleStartDay),
        mealPricingEnabled: mealPricingEnabled ?? this.mealPricingEnabled,
        mealPricingLocked: mealPricingLocked ?? this.mealPricingLocked,
        billSkippedMeals: billSkippedMeals ?? this.billSkippedMeals,
        billAbsentMeals: billAbsentMeals ?? this.billAbsentMeals,
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
        billingCycleChangeUsed,
        mealPricingEnabled,
        mealPricingLocked,
        billSkippedMeals,
        billAbsentMeals,
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
    this.myMemberSettings,
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

  /// The signed-in member's RAW per-group setting overrides for THIS group.
  ///
  /// Vacation and auto-attendance are per group. A `null` field means "inherit
  /// the user-level flag" (which the session already holds), so callers resolve
  /// with [MemberSettingOverrides.resolve]. Null overall = not a member, or the
  /// server did not populate it on this read.
  final MemberSettingOverrides? myMemberSettings;

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
        myMemberSettings: MemberSettingOverrides.fromJson(
          j['myMemberSettings'] as Map<String, dynamic>?,
        ),
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
        if (myMemberSettings != null)
          'myMemberSettings': myMemberSettings!.toJson(),
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
    MemberSettingOverrides? myMemberSettings,
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
        myMemberSettings: myMemberSettings ?? this.myMemberSettings,
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
        // Equality must see the per-group overrides, or a provider comparing
        // groups would treat a changed setting as "no change" and skip rebuild.
        myMemberSettings,
        joinApprovalRequired,
        pendingCount,
        archivedAt,
      ];
}
