import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';

/// Module 36 (FR-PG-030): grouped meal-preference selector.
///
/// Renders each effective preference group as a labelled section with its
/// options and rule ("Choose 1", "Optional · up to 2"), supports quantity
/// steppers when enabled, mirrors conditional visibility (FR-PG-060) and
/// veg-only filtering (FR-PG-061), and reports the live price delta.
/// Server-side validation remains authoritative — this mirrors it for UX.
class PreferenceGroupSelector extends StatefulWidget {
  const PreferenceGroupSelector({
    super.key,
    required this.groups,
    required this.onChanged,
    this.enabled = true,
  });

  final List<PreferenceGroupModel> groups;
  final bool enabled;

  /// Fires on every change: current selections, Σ price delta (minor units),
  /// and whether all visible required groups are satisfied (Present gate).
  final void Function(
    List<PreferenceSelection> selections,
    int totalDelta,
    bool complete,
  ) onChanged;

  @override
  State<PreferenceGroupSelector> createState() =>
      _PreferenceGroupSelectorState();
}

class _PreferenceGroupSelectorState extends State<PreferenceGroupSelector> {
  /// groupId → (optionKey → quantity)
  final Map<String, Map<String, int>> _picked = {};

  bool _isVisible(PreferenceGroupModel g) {
    if (g.visibleWhenGroupId == null || g.visibleWhenOptionKey == null) {
      return true;
    }
    return _picked[g.visibleWhenGroupId]?.containsKey(g.visibleWhenOptionKey) ??
        false;
  }

  List<PreferenceOptionModel> _visibleOptions(PreferenceGroupModel g) =>
      g.vegOnly ? g.options.where((o) => o.isVeg).toList() : g.options;

  int get _totalDelta {
    var sum = 0;
    for (final g in widget.groups) {
      if (!_isVisible(g)) continue;
      final picks = _picked[g.id] ?? const {};
      for (final entry in picks.entries) {
        final opt = g.options.where((o) => o.key == entry.key).firstOrNull;
        if (opt != null) sum += opt.priceDelta * entry.value;
      }
    }
    return sum;
  }

  bool get _complete {
    for (final g in widget.groups) {
      if (!_isVisible(g) || !g.required) continue;
      if (_visibleOptions(g).isEmpty) continue; // fail-safe (FR-PG-031)
      final count = _picked[g.id]?.length ?? 0;
      if (count < (g.minSelect < 1 ? 1 : g.minSelect)) return false;
    }
    return true;
  }

  void _emit() {
    final selections = <PreferenceSelection>[];
    for (final g in widget.groups) {
      if (!_isVisible(g)) continue;
      for (final entry in (_picked[g.id] ?? const <String, int>{}).entries) {
        selections.add(PreferenceSelection(
          groupId: g.id,
          optionKey: entry.key,
          quantity: entry.value,
        ));
      }
    }
    widget.onChanged(selections, _totalDelta, _complete);
  }

  void _toggle(PreferenceGroupModel g, PreferenceOptionModel o) {
    if (!widget.enabled) return;
    setState(() {
      final picks = _picked.putIfAbsent(g.id, () => {});
      if (picks.containsKey(o.key)) {
        picks.remove(o.key);
      } else {
        if (g.isSingle || g.maxSelect == 1) picks.clear();
        if (picks.length < g.maxSelect || g.maxSelect == 1) {
          picks[o.key] = g.quantityEnabled ? o.minQty : 1;
        }
      }
    });
    _emit();
  }

  void _setQty(PreferenceGroupModel g, PreferenceOptionModel o, int qty) {
    if (!widget.enabled) return;
    setState(() {
      _picked.putIfAbsent(g.id, () => {})[o.key] =
          qty.clamp(o.minQty, o.maxQty);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.groups.where(_isVisible).toList();
    final delta = _totalDelta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in visible) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    g.label,
                    style: AppTypography.labelMedium
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  g.ruleLabel,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in _visibleOptions(g))
                _OptionChip(
                  option: o,
                  selected: _picked[g.id]?.containsKey(o.key) ?? false,
                  quantity: _picked[g.id]?[o.key] ?? 0,
                  quantityEnabled: g.quantityEnabled,
                  enabled: widget.enabled,
                  onTap: () => _toggle(g, o),
                  onQty: (q) => _setQty(g, o, q),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (delta > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '+ ₹${(delta / 100).toStringAsFixed(delta % 100 == 0 ? 0 : 2)} added to meal price',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.option,
    required this.selected,
    required this.quantity,
    required this.quantityEnabled,
    required this.enabled,
    required this.onTap,
    required this.onQty,
  });

  final PreferenceOptionModel option;
  final bool selected;
  final int quantity;
  final bool quantityEnabled;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deltaText = option.priceDelta > 0
        ? ' +₹${(option.priceDelta / 100).toStringAsFixed(option.priceDelta % 100 == 0 ? 0 : 2)}'
        : '';
    final color = selected ? AppColors.primary : AppColors.textTertiary;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : (isDark ? AppColors.surfaceDark : AppColors.surface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : color.withValues(alpha: 0.35),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!option.isVeg) ...[
              const Icon(Icons.circle, size: 8, color: AppColors.error),
              const SizedBox(width: 5),
            ],
            Text(
              '${option.displayLabel}$deltaText',
              style: AppTypography.bodySmall.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary),
              ),
            ),
            if (selected && quantityEnabled && option.maxQty > option.minQty) ...[
              const SizedBox(width: 8),
              _qtyBtn(Icons.remove, () => onQty(quantity - 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('×$quantity',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.primary)),
              ),
              _qtyBtn(Icons.add, () => onQty(quantity + 1)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onPressed) => InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(10),
        child: Icon(icon, size: 16, color: AppColors.primary),
      );
}
