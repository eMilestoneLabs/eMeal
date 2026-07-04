import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/guest_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/guest_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Module 22 (Pass 9) — hosted-guest management sheet (FR-HG-031/033/034/062).
///
/// One sheet serves both flows:
///  - **Host** (student): add guests to their own meal with per-guest
///    Adult/Child + name + preference, live cost preview, edit/cancel, and
///    Confirm/Decline for admin-proposed guests.
///  - **Admin on behalf** ([hostUserId] + [asAdmin]): the booking parks as
///    pendingApproval until the HOST confirms — governed, never silent.
///
/// Returns `true` when anything changed so callers can refresh.
Future<bool?> showGuestSheet(
  BuildContext context, {
  required String mealId,
  required String mealName,
  required String dateStr, // YYYY-MM-DD
  required GroupGuestConfig config,
  required bool pricingEnabled,
  required List<String> enabledPreferences,
  int? mealPrice,
  String? hostUserId,
  String? hostName,
  bool asAdmin = false,
  String? currentUserId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GuestSheet(
      mealId: mealId,
      mealName: mealName,
      dateStr: dateStr,
      config: config,
      pricingEnabled: pricingEnabled,
      enabledPreferences: enabledPreferences,
      mealPrice: mealPrice,
      hostUserId: hostUserId,
      hostName: hostName,
      asAdmin: asAdmin,
      currentUserId: currentUserId,
    ),
  );
}

class _GuestSheet extends StatefulWidget {
  const _GuestSheet({
    required this.mealId,
    required this.mealName,
    required this.dateStr,
    required this.config,
    required this.pricingEnabled,
    required this.enabledPreferences,
    this.mealPrice,
    this.hostUserId,
    this.hostName,
    this.asAdmin = false,
    this.currentUserId,
  });

  final String mealId;
  final String mealName;
  final String dateStr;
  final GroupGuestConfig config;
  final bool pricingEnabled;
  final List<String> enabledPreferences;
  final int? mealPrice;

  /// Admin flow: the member being hosted for. Null = the caller hosts.
  final String? hostUserId;
  final String? hostName;
  final bool asAdmin;
  final String? currentUserId;

  @override
  State<_GuestSheet> createState() => _GuestSheetState();
}

class _GuestSheetState extends State<_GuestSheet> {
  final GuestRepository _repo = GuestRepository();

  bool _loading = true;
  bool _submitting = false;
  bool _changed = false;
  String? _error;
  List<MealGuestModel> _guests = const [];
  List<GuestDraft> _drafts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _repo.listGuests(
      date: widget.dateStr,
      mealId: widget.mealId,
      hostUserId: widget.asAdmin ? widget.hostUserId : null,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _guests = value.where((g) => g.isBooked).toList();
          _error = null;
        case Err(:final failure):
          _error = failure.message;
      }
    });
  }

  // ── Derived ────────────────────────────────────────────────────────────────

  int get _activeCount => _guests.length;

  int get _remainingAllowance =>
      (widget.config.maxGuestsPerMemberPerMeal - _activeCount)
          .clamp(0, widget.config.maxGuestsPerMemberPerMeal);

  int? _priceFor(bool isAdult) => widget.config.estimatePrice(
        mealPrice: widget.mealPrice,
        isAdult: isAdult,
        pricingEnabled: widget.pricingEnabled,
      );

  /// FR-HG-034: live cost preview for the drafts about to be booked.
  int get _draftCost => _drafts.fold(
      0, (sum, d) => sum + (_priceFor(d.isAdult) ?? 0));

  /// Booked (confirmed) guest cost already committed for this meal.
  int get _bookedCost => _guests
      .where((g) => g.isConfirmed)
      .fold(0, (sum, g) => sum + (g.priceSnapshot ?? 0));

  bool get _prefsSatisfied =>
      !widget.config.guestPreferenceRequired ||
      _drafts.every(
          (d) => d.mealPreference != null && d.mealPreference!.isNotEmpty);

  bool get _canSubmit =>
      _drafts.isNotEmpty && !_submitting && _prefsSatisfied;

  // ── Actions ────────────────────────────────────────────────────────────────

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? AppColors.error : null,
    ));
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final result = await _repo.bookGuests(
      mealId: widget.mealId,
      attendanceDate: widget.dateStr,
      guests: _drafts,
      hostUserId: widget.asAdmin ? widget.hostUserId : null,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Ok(:final value):
        _changed = true;
        _drafts = [];
        final pending = value.pendingApproval > 0;
        _snack(pending
            ? (widget.asAdmin
                ? 'Proposed — the member must confirm the guest charge.'
                : 'Requested — awaiting admin approval.')
            : 'Guests added for ${widget.mealName}.');
        setState(() => _loading = true);
        await _load();
      case Err(:final failure):
        _snack(failure.message, isError: true);
    }
  }

  Future<void> _act(
    Future<Result<MealGuestModel>> Function() action, {
    required String success,
  }) async {
    final result = await action();
    if (!mounted) return;
    switch (result) {
      case Ok():
        _changed = true;
        _snack(success);
        setState(() => _loading = true);
        await _load();
      case Err(:final failure):
        _snack(failure.message, isError: true);
    }
  }

  Future<void> _editGuest(MealGuestModel guest) async {
    final updated = await showDialog<({String name, String? preference})>(
      context: context,
      builder: (_) => _EditGuestDialog(
        guest: guest,
        enabledPreferences: widget.enabledPreferences,
      ),
    );
    if (updated == null) return;
    await _act(
      () => _repo.updateGuest(
        id: guest.id,
        displayName: updated.name,
        mealPreference: updated.preference,
      ),
      success: 'Guest updated.',
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: EdgeInsets.only(bottom: bottomInset),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.bottomSheetRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(isDark),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(AppConstants.space32),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2.5),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.space20,
                        0,
                        AppConstants.space20,
                        AppConstants.space20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_error != null) _errorBanner(isDark),
                          ..._pendingHostSection(isDark),
                          ..._guestListSection(isDark),
                          ..._draftSection(isDark),
                          const SizedBox(height: AppConstants.space12),
                          _costPreview(isDark),
                          const SizedBox(height: AppConstants.space12),
                          _submitButton(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isDark) {
    final hostLine = widget.asAdmin && (widget.hostName?.isNotEmpty ?? false)
        ? ' · hosted by ${widget.hostName}'
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space20,
        AppConstants.space20,
        AppConstants.space12,
        AppConstants.space12,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.group_add_rounded,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guests — ${widget.mealName}',
                  style: AppTypography.titleMedium.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${widget.dateStr}$hostLine · up to '
                  '${widget.config.maxGuestsPerMemberPerMeal} per meal',
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(_changed),
            icon: Icon(
              Icons.close_rounded,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.space12),
        child: Container(
          padding: const EdgeInsets.all(AppConstants.space12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 16, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  /// FR-HG-062: admin-proposed guests the HOST must confirm or decline.
  List<Widget> _pendingHostSection(bool isDark) {
    final mine = widget.currentUserId;
    final proposals = _guests
        .where((g) =>
            g.isPending &&
            g.isAdminProposed &&
            !widget.asAdmin &&
            (mine == null || g.hostUserId == mine))
        .toList();
    if (proposals.isEmpty) return const [];
    return [
      _sectionTitle('Awaiting your confirmation', isDark,
          color: AppColors.warning),
      ...proposals.map((g) => Container(
            margin: const EdgeInsets.only(bottom: AppConstants.space8),
            padding: const EdgeInsets.all(AppConstants.space12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _guestLine(g, isDark),
                const SizedBox(height: 4),
                Text(
                  'Added by your admin — confirming accepts the charge.',
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppConstants.space8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _act(
                          () => _repo.confirmGuest(g.id),
                          success: 'Guest confirmed.',
                        ),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.present,
                        ),
                        child: const Text('Confirm'),
                      ),
                    ),
                    const SizedBox(width: AppConstants.space8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _act(
                          () => _repo.declineGuest(g.id),
                          success: 'Guest declined.',
                        ),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.absent,
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )),
      const SizedBox(height: AppConstants.space8),
    ];
  }

  List<Widget> _guestListSection(bool isDark) {
    final rows = _guests
        .where((g) => !(g.isPending && g.isAdminProposed && !widget.asAdmin))
        .toList();
    if (rows.isEmpty && _drafts.isEmpty) {
      return [
        _sectionTitle('Your guests', isDark),
        Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.space8),
          child: Text(
            'No guests yet — add one below. Guest meals are billed to the host.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ];
    }
    if (rows.isEmpty) return const [];
    return [
      _sectionTitle(widget.asAdmin ? 'Guests' : 'Your guests', isDark),
      ...rows.map((g) => Container(
            margin: const EdgeInsets.only(bottom: AppConstants.space8),
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space12,
              vertical: AppConstants.space8,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            ),
            child: Row(
              children: [
                Expanded(child: _guestLine(g, isDark)),
                if (g.isPending)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _chip(
                      g.isAdminProposed ? 'Needs member OK' : 'Pending',
                      AppColors.warning,
                    ),
                  ),
                if (widget.asAdmin && g.isPending && !g.isAdminProposed) ...[
                  IconButton(
                    tooltip: 'Approve',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _act(
                      () => _repo.approveGuest(g.id),
                      success: 'Guest approved.',
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 20, color: AppColors.present),
                  ),
                  IconButton(
                    tooltip: 'Reject',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _act(
                      () => _repo.rejectGuest(g.id),
                      success: 'Guest rejected.',
                    ),
                    icon: const Icon(Icons.highlight_off_rounded,
                        size: 20, color: AppColors.absent),
                  ),
                ] else ...[
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editGuest(g),
                    icon: Icon(Icons.edit_rounded,
                        size: 18,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary),
                  ),
                  IconButton(
                    tooltip: 'Cancel guest',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _act(
                      () => _repo.cancelGuest(g.id),
                      success: 'Guest cancelled.',
                    ),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 19, color: AppColors.absent),
                  ),
                ],
              ],
            ),
          )),
      const SizedBox(height: AppConstants.space8),
    ];
  }

  Widget _guestLine(MealGuestModel g, bool isDark) {
    final name = (g.displayName?.isNotEmpty ?? false)
        ? g.displayName!
        : 'Guest (${g.typeLabel})';
    final parts = <String>[
      g.typeLabel,
      if (g.mealPreference != null)
        MealPreferenceOption.display(g.mealPreference!).label,
      if (g.priceSnapshot != null) '₹${g.priceSnapshot}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: AppTypography.bodyMedium.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          parts.join(' · '),
          style: AppTypography.labelSmall.copyWith(
            color:
                isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  List<Widget> _draftSection(bool isDark) {
    return [
      Row(
        children: [
          _sectionTitle('Add guests', isDark, bottomPadding: 0),
          const Spacer(),
          Text(
            '$_remainingAllowance remaining',
            style: AppTypography.labelSmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppConstants.space8),
      ..._drafts.asMap().entries.map((e) => _DraftRow(
            key: ValueKey('draft_${e.key}'),
            draft: e.value,
            index: e.key,
            isDark: isDark,
            enabledPreferences: widget.enabledPreferences,
            preferenceRequired: widget.config.guestPreferenceRequired,
            price: _priceFor(e.value.isAdult),
            onChanged: (d) => setState(() => _drafts[e.key] = d),
            onRemove: () => setState(() => _drafts.removeAt(e.key)),
          )),
      if (_drafts.length < _remainingAllowance)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _drafts = [..._drafts, const GuestDraft()]),
            icon: const Icon(Icons.person_add_alt_rounded, size: 17),
            label: Text(_drafts.isEmpty ? 'Add a guest' : 'Add another guest'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        )
      else if (_remainingAllowance == 0)
        Text(
          'Guest limit reached for this meal.',
          style: AppTypography.labelSmall.copyWith(color: AppColors.warning),
        ),
    ];
  }

  Widget _costPreview(bool isDark) {
    if (!widget.pricingEnabled) {
      return Text(
        'Headcount only — guest meals are not billed in this group.',
        style: AppTypography.labelSmall.copyWith(
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_bookedCost > 0)
            _costLine('Booked guests', '₹$_bookedCost', isDark),
          // FR-HG-034: the preview updates live as draft rows change.
          _costLine(
            'New guests (${_drafts.length})',
            '₹$_draftCost',
            isDark,
            bold: true,
          ),
          if (widget.config.guestRequiresApproval || widget.asAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.asAdmin
                    ? 'Charged only after the member confirms.'
                    : 'Charged only after admin approval.',
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.warning),
              ),
            ),
        ],
      ),
    );
  }

  Widget _costLine(String label, String value, bool isDark,
          {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              value,
              style: AppTypography.bodySmall.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Widget _submitButton() {
    final label = _drafts.isEmpty
        ? 'Add guests'
        : widget.asAdmin
            ? 'Propose ${_drafts.length} guest${_drafts.length == 1 ? '' : 's'}'
            : 'Add ${_drafts.length} guest${_drafts.length == 1 ? '' : 's'}';
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _canSubmit ? _submit : null,
        icon: _submitting
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.group_add_rounded, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          textStyle:
              AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, bool isDark,
          {Color? color, double bottomPadding = 8}) =>
      Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Text(
          text,
          style: AppTypography.labelMedium.copyWith(
            color: color ??
                (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// ── Draft row ──────────────────────────────────────────────────────────────────

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    super.key,
    required this.draft,
    required this.index,
    required this.isDark,
    required this.enabledPreferences,
    required this.preferenceRequired,
    required this.price,
    required this.onChanged,
    required this.onRemove,
  });

  final GuestDraft draft;
  final int index;
  final bool isDark;
  final List<String> enabledPreferences;
  final bool preferenceRequired;
  final int? price;
  final ValueChanged<GuestDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.space8),
      padding: const EdgeInsets.all(AppConstants.space12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _typeToggle(),
              const Spacer(),
              if (price != null)
                Text(
                  '₹$price',
                  style: AppTypography.labelMedium.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.absent),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space8),
          TextFormField(
            initialValue: draft.displayName,
            maxLength: 80,
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'Guest name (optional)',
              prefixIcon: Icon(Icons.badge_outlined, size: 18),
            ),
            onChanged: (v) => onChanged(draft.copyWith(displayName: v)),
          ),
          if (enabledPreferences.isNotEmpty) ...[
            const SizedBox(height: AppConstants.space8),
            Text(
              preferenceRequired
                  ? 'Meal preference (required)'
                  : 'Meal preference',
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: enabledPreferences.map((opt) {
                final selected = draft.mealPreference == opt;
                final disp = MealPreferenceOption.display(opt);
                return GestureDetector(
                  onTap: () => onChanged(GuestDraft(
                    isAdult: draft.isAdult,
                    displayName: draft.displayName,
                    mealPreference: selected ? null : opt,
                  )),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : isDark
                              ? AppColors.surfaceDark
                              : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : isDark
                                ? AppColors.borderDark.withValues(alpha: 0.5)
                                : AppColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (disp.emoji.isNotEmpty) ...[
                          Text(disp.emoji,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          disp.label,
                          style: AppTypography.labelSmall.copyWith(
                            color: selected
                                ? Colors.white
                                : isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeToggle() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: true,
          label: Text('Adult'),
          icon: Icon(Icons.person_rounded, size: 15),
        ),
        ButtonSegment(
          value: false,
          label: Text('Child'),
          icon: Icon(Icons.child_care_rounded, size: 15),
        ),
      ],
      selected: {draft.isAdult},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelectionChanged: (s) => onChanged(draft.copyWith(isAdult: s.first)),
    );
  }
}

// ── Edit dialog ────────────────────────────────────────────────────────────────

class _EditGuestDialog extends StatefulWidget {
  const _EditGuestDialog({
    required this.guest,
    required this.enabledPreferences,
  });

  final MealGuestModel guest;
  final List<String> enabledPreferences;

  @override
  State<_EditGuestDialog> createState() => _EditGuestDialogState();
}

class _EditGuestDialogState extends State<_EditGuestDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.guest.displayName ?? '');
  String? _preference;

  @override
  void initState() {
    super.initState();
    _preference = widget.guest.mealPreference;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit guest'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Guest name',
              counterText: '',
            ),
          ),
          if (widget.enabledPreferences.isNotEmpty) ...[
            const SizedBox(height: AppConstants.space8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.enabledPreferences.map((opt) {
                final selected = _preference == opt;
                final disp = MealPreferenceOption.display(opt);
                return FilterChip(
                  selected: selected,
                  label: Text(
                      '${disp.emoji.isNotEmpty ? '${disp.emoji} ' : ''}${disp.label}'),
                  onSelected: (_) =>
                      setState(() => _preference = selected ? null : opt),
                );
              }).toList(),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop((name: _name.text.trim(), preference: _preference)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
