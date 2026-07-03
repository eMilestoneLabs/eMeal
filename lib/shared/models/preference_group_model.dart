/// Module 36 (FR-PG-*): multi-dimensional meal preference groups.
///
/// A meal may carry N choice dimensions ("Staple", "Non-Veg"), each with its
/// own pick rule and priced options. Meals without explicit groups keep the
/// legacy flat `enabledPreferences` UX untouched (FR-PG-021).
class PreferenceGroupModel {
  const PreferenceGroupModel({
    required this.id,
    required this.label,
    this.description,
    this.order = 0,
    this.selectionType = 'single',
    this.minSelect = 1,
    this.maxSelect = 1,
    this.required = true,
    this.quantityEnabled = false,
    this.visibleWhenGroupId,
    this.visibleWhenOptionKey,
    this.vegOnly = false,
    this.options = const [],
  });

  final String id;
  final String label;
  final String? description;
  final int order;
  final String selectionType; // single | multiple
  final int minSelect;
  final int maxSelect;
  final bool required;
  final bool quantityEnabled;

  /// FR-PG-060: this group is visible only when the referenced option is
  /// chosen in the referenced group (both null = always visible).
  final String? visibleWhenGroupId;
  final String? visibleWhenOptionKey;
  final bool vegOnly;
  final List<PreferenceOptionModel> options;

  bool get isSingle => selectionType == 'single';

  factory PreferenceGroupModel.fromJson(Map<String, dynamic> j) {
    final vw = j['visibleWhen'];
    return PreferenceGroupModel(
      id: (j['id'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      description: j['description']?.toString(),
      order: (j['order'] as num?)?.toInt() ?? 0,
      selectionType: (j['selectionType'] ?? 'single').toString(),
      minSelect: (j['minSelect'] as num?)?.toInt() ?? 1,
      maxSelect: (j['maxSelect'] as num?)?.toInt() ?? 1,
      required: j['required'] != false,
      quantityEnabled: j['quantityEnabled'] == true,
      visibleWhenGroupId:
          vw is Map<String, dynamic> ? vw['groupId']?.toString() : null,
      visibleWhenOptionKey:
          vw is Map<String, dynamic> ? vw['optionKey']?.toString() : null,
      vegOnly: j['vegOnly'] == true,
      options: (j['options'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PreferenceOptionModel.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'description': description,
        'order': order,
        'selectionType': selectionType,
        'minSelect': minSelect,
        'maxSelect': maxSelect,
        'required': required,
        'quantityEnabled': quantityEnabled,
        'visibleWhen': visibleWhenGroupId != null
            ? {'groupId': visibleWhenGroupId, 'optionKey': visibleWhenOptionKey}
            : null,
        'vegOnly': vegOnly,
        'options': options.map((o) => o.toJson()).toList(),
      };

  /// Human rule caption, e.g. "Choose 1" / "Choose up to 2" / "Optional".
  String get ruleLabel {
    if (!required && maxSelect <= 1) return 'Optional';
    if (isSingle || maxSelect == 1) return 'Choose 1';
    if (!required) return 'Optional · up to $maxSelect';
    return minSelect == maxSelect
        ? 'Choose $minSelect'
        : 'Choose $minSelect–$maxSelect';
  }
}

/// One option inside a preference group (FR-PG-011).
class PreferenceOptionModel {
  const PreferenceOptionModel({
    required this.key,
    required this.label,
    this.id = '',
    this.emoji,
    this.color,
    this.isVeg = true,
    this.priceDelta = 0,
    this.minQty = 1,
    this.maxQty = 1,
    this.order = 0,
  });

  final String id;
  final String key;
  final String label;
  final String? emoji;
  final String? color;
  final bool isVeg;

  /// ₹ minor units added to base price (client shows priceDelta / 100).
  final int priceDelta;
  final int minQty;
  final int maxQty;
  final int order;

  factory PreferenceOptionModel.fromJson(Map<String, dynamic> j) {
    return PreferenceOptionModel(
      id: (j['id'] ?? '').toString(),
      key: (j['key'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      emoji: j['emoji']?.toString(),
      color: j['color']?.toString(),
      isVeg: j['isVeg'] != false,
      priceDelta: (j['priceDelta'] as num?)?.toInt() ?? 0,
      minQty: (j['minQty'] as num?)?.toInt() ?? 1,
      maxQty: (j['maxQty'] as num?)?.toInt() ?? 1,
      order: (j['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'label': label,
        'emoji': emoji,
        'color': color,
        'isVeg': isVeg,
        'priceDelta': priceDelta,
        'minQty': minQty,
        'maxQty': maxQty,
        'order': order,
      };

  String get displayLabel => emoji != null && emoji!.isNotEmpty
      ? '$emoji $label'
      : label;
}

/// A member's chosen option (outgoing selection — FR-PG-013/031).
class PreferenceSelection {
  const PreferenceSelection({
    required this.groupId,
    required this.optionKey,
    this.quantity = 1,
  });

  final String groupId;
  final String optionKey;
  final int quantity;

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'optionKey': optionKey,
        if (quantity != 1) 'quantity': quantity,
      };
}
