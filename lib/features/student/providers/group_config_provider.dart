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

  GroupMealConfig get config => _config;
  String get groupName => _groupName;

  bool get mealsEnabled => _config.mealsEnabled;
  bool get weeklyMenuEnabled => _config.weeklyMenuEnabled;
  bool get dayWiseMealsEnabled => _config.dayWiseMealsEnabled;
  bool get preferencesEnabled => _config.preferencesEnabled;
  List<MealPreferenceOption> get enabledPreferences =>
      _config.enabledPreferences;

  /// Called by [StudentDashboardProvider] once the group is fetched.
  void update({required GroupMealConfig config, required String groupName}) {
    if (_config == config && _groupName == groupName) return;
    _config = config;
    _groupName = groupName;
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
}
