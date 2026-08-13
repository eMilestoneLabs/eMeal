import 'package:flutter/widgets.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';

/// Holds the active group's [GroupMealConfig] and display name.
///
/// Created once by [StudentShell] and made available to descendants via
/// [GroupConfigScope]. [StudentDashboardProvider] updates it after loading
/// the group, which causes [StudentShell] to rebuild its bottom nav with the
/// correct tab set.
class GroupConfigProvider extends ChangeNotifier {
  GroupMealConfig _config = const GroupMealConfig();
  String _groupName = '';
  String _groupId = '';
  MemberSettingOverrides? _myMemberSettings;

  GroupMealConfig get config => _config;
  String get groupName => _groupName;

  /// The group these values describe — the scope every per-group write needs.
  String get groupId => _groupId;

  /// The signed-in member's RAW per-group overrides for THIS group. Null on a
  /// field means "inherit the user-level flag"; resolve with
  /// [MemberSettingOverrides.resolve] against the session value.
  MemberSettingOverrides? get myMemberSettings => _myMemberSettings;

  bool get mealsEnabled => _config.mealsEnabled;
  bool get weeklyMenuEnabled => _config.weeklyMenuEnabled;
  bool get dayWiseMealsEnabled => _config.dayWiseMealsEnabled;
  bool get preferencesEnabled => _config.preferencesEnabled;

  /// Live-Test-15 ISSUE-2: Meal Pricing is the MASTER GATE for meal billing.
  /// When it is OFF the group has no financial subsystem at all, so every
  /// billing surface must be hidden — not rendered as ₹0. Read from the config
  /// the shell already holds, so gating costs ZERO extra network calls.
  bool get mealPricingEnabled => _config.mealPricingEnabled;
  List<MealPreferenceOption> get enabledPreferences =>
      _config.enabledPreferences;

  /// Called by [StudentDashboardProvider] once the group is fetched.
  ///
  /// [groupId] is optional and additive so the cache-first paint can supply it
  /// without disturbing anything else. Member settings are NOT accepted here —
  /// see [setMemberSettings] for why that separation matters.
  void update({
    required GroupMealConfig config,
    required String groupName,
    String? groupId,
  }) {
    final nextId = groupId ?? _groupId;
    if (_config == config && _groupName == groupName && _groupId == nextId) {
      return;
    }
    // GROUP SWITCH: the member settings held here describe the PREVIOUS group.
    // The cache-first paint that changes the id has no settings to supply, so
    // leaving them in place would publish group B's id carrying group A's
    // vacation / auto-attendance state — another group's data under this
    // group's identity. Dropping them falls back to the inherited user-level
    // value until the live load supplies the real ones a moment later, which
    // is the correct stale-then-truth behaviour AND group-correct.
    if (_groupId != nextId) _myMemberSettings = null;
    _config = config;
    _groupName = groupName;
    _groupId = nextId;
    notifyListeners();
  }

  /// Publish the member settings for the group [update] is describing.
  ///
  /// DELIBERATELY separate from [update]: the cache-first paint has no member
  /// settings to give, and if it shared this method an omitted argument would
  /// be indistinguishable from "this group genuinely has no overrides" and
  /// would WIPE a value the user had just set. The member would then see the
  /// toggle snap back to the inherited user-level flag — the exact
  /// "setting randomly re-enables" failure this feature exists to end, and one
  /// that would persist while offline because nothing would correct it.
  ///
  /// Only the LIVE group load calls this, and it always passes the server's
  /// value — including null, which legitimately means "no override, inherit".
  void setMemberSettings(MemberSettingOverrides? overrides) {
    if (_myMemberSettings == overrides) return;
    _myMemberSettings = overrides;
    notifyListeners();
  }
}

// ── Inherited scope ────────────────────────────────────────────────────────────

/// Makes [GroupConfigProvider] available to all descendants of [StudentShell].
///
/// Widgets that need it call [GroupConfigScope.of(context)].
class GroupConfigScope extends InheritedNotifier<GroupConfigProvider> {
  const GroupConfigScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  /// Returns the nearest [GroupConfigProvider] in the widget tree.
  ///
  /// Subscribes the caller to rebuilds when the config changes.
  static GroupConfigProvider of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GroupConfigScope>();
    assert(scope != null,
        'GroupConfigScope.of() called outside of a GroupConfigScope widget.');
    return scope!.notifier!;
  }

  /// Returns the provider without subscribing to changes.
  static GroupConfigProvider? maybeOf(BuildContext context) {
    return context
        .findAncestorWidgetOfExactType<GroupConfigScope>()
        ?.notifier;
  }

  /// Null-safe AND subscribing — the combination [of] and [maybeOf] each miss.
  ///
  /// [maybeOf] deliberately does not register a dependency, so a caller that
  /// reads it inside `didChangeDependencies` is never called again when the
  /// config changes (the live group load landing after a cache-first paint, or
  /// a group switch) and silently keeps its first value. [of] does subscribe
  /// but asserts on a missing scope, which is a crash in release for any screen
  /// that could ever render outside the shell.
  static GroupConfigProvider? maybeWatch(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<GroupConfigScope>()
        ?.notifier;
  }
}
