import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_meal_type.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/features/events/models/guest_person.dart';
import 'package:smart_meal_management/features/events/providers/event_admin_provider.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/event_admin_shell.dart';

// ── EventAdminGuestsTab ────────────────────────────────────────────────────────

/// Guests tab — full party list with expandable rows, inline name editing,
/// and per-person event meal type assignment.
class EventAdminGuestsTab extends StatelessWidget {
  const EventAdminGuestsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = EventAdminScope.of(context);
    final isDark = EventThemeScope.isDark(context);
    final event = provider.event;

    return CustomScrollView(
      slivers: [
        // ── App bar ──────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              const Icon(Icons.people_rounded,
                  size: 20, color: AppColors.vacation),
              const SizedBox(width: 10),
              Text(
                'Guests',
                style: AppTypography.titleLarge.copyWith(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.vacation.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${provider.totalGuestCount} guests',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.vacation,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),

        if (provider.parties.isEmpty)
          SliverFillRemaining(
            child: _EmptyGuestsView(isDark: isDark),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppConstants.pagePaddingH,
              16,
              AppConstants.pagePaddingH,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PartyCard(
                    party: provider.parties[index],
                    event: event,
                    provider: provider,
                    isDark: isDark,
                  ),
                ),
                childCount: provider.parties.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Party card ─────────────────────────────────────────────────────────────────

class _PartyCard extends StatefulWidget {
  const _PartyCard({
    required this.party,
    required this.event,
    required this.provider,
    required this.isDark,
  });

  final EventGuestParty party;
  final EventModel? event;
  final EventAdminProvider provider;
  final bool isDark;

  @override
  State<_PartyCard> createState() => _PartyCardState();
}

class _PartyCardState extends State<_PartyCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final party = widget.party;
    final event = widget.event;
    final mealTypes = event?.mealTypes ?? [];

    // Completion: if event has meal types, check allEventMealsSelected;
    // otherwise consider it complete (meal tracking not active)
    final allDone = mealTypes.isEmpty || party.allEventMealsSelected;

    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: widget.isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
        ),
        boxShadow: widget.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          // ── Party header ────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.vacation.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        party.primaryName.isNotEmpty
                            ? party.primaryName[0].toUpperCase()
                            : '?',
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.vacation,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name + count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          party.primaryName,
                          style: AppTypography.bodyMedium.copyWith(
                            color: widget.isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              '${party.totalCount} people  ·  ${party.adultsCount}A',
                              style: AppTypography.bodySmall.copyWith(
                                color: widget.isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary,
                              ),
                            ),
                            if (party.childrenCount > 0)
                              Text(
                                ' + ${party.childrenCount}C',
                                style: AppTypography.bodySmall.copyWith(
                                  color: widget.isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Meal status badge
                  if (mealTypes.isNotEmpty)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: allDone
                            ? AppColors.present.withValues(alpha: 0.12)
                            : AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        allDone ? '✓ Done' : 'Pending',
                        style: AppTypography.labelSmall.copyWith(
                          color: allDone ? AppColors.present : AppColors.warning,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  // Chevron
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: widget.isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded person list ─────────────────────────────────────────
          if (_expanded) ...[
            Divider(
              height: 1,
              color: widget.isDark
                  ? AppColors.borderDark.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
            ...party.persons.map((person) => _PersonRow(
                  person: person,
                  party: party,
                  event: event,
                  provider: widget.provider,
                  isDark: widget.isDark,
                )),
          ],
        ],
      ),
    );
  }
}

// ── Person row ─────────────────────────────────────────────────────────────────

class _PersonRow extends StatefulWidget {
  const _PersonRow({
    required this.person,
    required this.party,
    required this.event,
    required this.provider,
    required this.isDark,
  });

  final GuestPerson person;
  final EventGuestParty party;
  final EventModel? event;
  final EventAdminProvider provider;
  final bool isDark;

  @override
  State<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<_PersonRow> {
  bool _editingName = false;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.person.displayName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _saveName() {
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty && name != widget.person.displayName) {
      widget.provider.renameGuest(
        partyId: widget.party.id,
        personId: widget.person.id,
        newName: name,
      );
    }
    setState(() => _editingName = false);
  }

  void _showMealTypePicker() {
    final mealTypes = widget.event?.mealTypes ?? [];
    if (mealTypes.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EventMealTypePicker(
        mealTypes: mealTypes,
        currentMealTypeId: widget.person.selectedMealTypeId,
        personName: widget.person.displayName,
        isDark: widget.isDark,
        onSelect: (mealTypeId) {
          widget.provider.setGuestEventMealType(
            partyId: widget.party.id,
            personId: widget.person.id,
            mealTypeId: mealTypeId,
          );
          Navigator.pop(context);
        },
        onClear: () {
          widget.provider.setGuestEventMealType(
            partyId: widget.party.id,
            personId: widget.person.id,
            mealTypeId: null,
          );
          Navigator.pop(context);
        },
      ),
    );
  }

  /// Look up the EventMealType for the person's selectedMealTypeId.
  EventMealType? get _selectedMealType {
    final id = widget.person.selectedMealTypeId;
    if (id == null) return null;
    final mealTypes = widget.event?.mealTypes ?? [];
    try {
      return mealTypes.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final isDark = widget.isDark;
    final selectedMeal = _selectedMealType;
    final hasMealTypes = (widget.event?.mealTypes ?? []).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Age dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: person.isAdult ? AppColors.info : AppColors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),

          // Name / inline editor
          Expanded(
            child: _editingName && !person.isPrimary
                ? TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    onSubmitted: (_) => _saveName(),
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppColors.vacation),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppColors.vacation, width: 1.5),
                      ),
                      suffixIcon: GestureDetector(
                        onTap: _saveName,
                        child: const Icon(Icons.check_rounded,
                            size: 16, color: AppColors.vacation),
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: person.isPrimary
                        ? null
                        : () => setState(() {
                              _editingName = true;
                              _nameCtrl.text = person.displayName;
                            }),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            person.displayName,
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                              fontWeight: person.isPrimary
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (!person.isPrimary) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_rounded,
                            size: 11,
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(width: 8),

          // Age tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: person.isAdult
                  ? AppColors.info.withValues(alpha: 0.12)
                  : AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              person.ageLabel,
              style: AppTypography.labelSmall.copyWith(
                color: person.isAdult ? AppColors.info : AppColors.warning,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),

          // Event meal type chip (only when event has configured meal types)
          if (hasMealTypes) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showMealTypePicker,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: selectedMeal != null
                      ? selectedMeal.color.withValues(alpha: isDark ? 0.18 : 0.12)
                      : (isDark
                          ? AppColors.borderDark.withValues(alpha: 0.4)
                          : AppColors.surfaceVariant),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selectedMeal != null
                        ? selectedMeal.color.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedMeal != null) ...[
                      Text(selectedMeal.emoji,
                          style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        selectedMeal.title,
                        style: AppTypography.labelSmall.copyWith(
                          color: selectedMeal.color,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ] else
                      Text(
                        'Set meal',
                        style: AppTypography.labelSmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Event meal type picker ─────────────────────────────────────────────────────

class _EventMealTypePicker extends StatelessWidget {
  const _EventMealTypePicker({
    required this.mealTypes,
    required this.currentMealTypeId,
    required this.personName,
    required this.isDark,
    required this.onSelect,
    required this.onClear,
  });

  final List<EventMealType> mealTypes;
  final String? currentMealTypeId;
  final String personName;
  final bool isDark;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.borderDark : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Meal Type for $personName',
            style: AppTypography.titleSmall.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Assign which meal this guest will have',
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // Meal type grid
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: mealTypes.map((m) {
              final isSelected = m.id == currentMealTypeId;
              return GestureDetector(
                onTap: () => onSelect(m.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? m.color.withValues(alpha: isDark ? 0.22 : 0.14)
                        : (isDark
                            ? AppColors.surfaceVariantDark
                            : AppColors.surfaceVariant),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? m.color
                          : Colors.transparent,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(
                        m.title,
                        style: AppTypography.bodySmall.copyWith(
                          color: isSelected
                              ? m.color
                              : (isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary),
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.check_circle_rounded,
                            size: 14, color: m.color),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          // Clear button
          if (currentMealTypeId != null) ...[
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: isDark ? AppColors.borderDark : AppColors.border,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onClear,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.clear_rounded,
                      size: 14,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Text(
                    'Clear Selection',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyGuestsView extends StatelessWidget {
  const _EmptyGuestsView({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.vacation.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_add_rounded,
                  size: 34, color: AppColors.vacation),
            ),
            const SizedBox(height: 20),
            Text(
              'No guests yet',
              style: AppTypography.titleMedium.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share the QR code or join code from the Dashboard tab so guests can register.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
