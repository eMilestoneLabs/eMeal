import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/utils/image_compression.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/data/repositories/preference_repository.dart';
import 'package:smart_meal_management/features/admin/meals/screens/preference_groups_screen.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/cached_photo.dart';

/// Form for creating or editing a meal.
///
/// Collects: name, slot key, display order, attendance window (open/close times
/// with validation + visual timeline), description, menu items, preference tags,
/// and a single compressed image (≤100 KB, replaced on each upload).
class MealConfigForm extends StatefulWidget {
  const MealConfigForm({
    super.key,
    this.initialMeal,
    required this.onSave,
    this.onSaveForGroups,
    this.isSaving = false,
    this.initialPreferencesEnabled = false,
    this.pricingEnabled = false,
  });

  /// If non-null, pre-populates the form for editing.
  final MealModel? initialMeal;

  /// Live-Test-9 ISSUE-001: returns null on SUCCESS, or a user-facing error
  /// message on failure. The form shows the message inline and preserves every
  /// entered value — the host must only pop its sheet on success, never on
  /// failure (popping on failure lost the admin's data and, combined with an
  /// un-disabled Save button, stacked multiple pops into a black screen).
  final Future<String?> Function(MealFormData data) onSave;

  /// Live-Test-9 ISSUE-5.2 (create mode only): invoked when the admin picks
  /// "Preference Groups" on a NEW meal. The host saves the meal (groups need
  /// a meal id), closes the sheet and opens the Groups builder for the newly
  /// created meal — one seamless step, no manual re-edit. Same success/error
  /// contract as [onSave].
  final Future<String?> Function(MealFormData data)? onSaveForGroups;
  final bool isSaving;

  /// When creating a new meal ([initialMeal] == null), this mirrors the
  /// group-level global preference state so new meals inherit it by default.
  /// Admins can still toggle the per-meal switch off before saving.
  final bool initialPreferencesEnabled;

  /// Additive: when true (group meal pricing ON), a Meal Price (₹) field shows.
  final bool pricingEnabled;

  @override
  State<MealConfigForm> createState() => _MealConfigFormState();
}

/// Default preference tags shown when admin first enables the preference system.
// Live-Test-7 ISSUE-2: standalone sets carry 2-5 options (server-enforced) -
// the old 6-tag seed exceeded the cap and failed the very first save.
const _kDefaultPreferenceTags = [
  'Veg',
  'Non-Veg',
  'Egg',
  'Fish',
  'Chicken',
];
const _kMinPreferenceTags = 2;
const _kMaxPreferenceTags = 5;

class _MealConfigFormState extends State<MealConfigForm> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _slotKeyCtrl = TextEditingController();
  final _menuItemCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  int _order = 0;
  TimeOfDay _openTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 9, minute: 0);
  List<String> _menuItems = [];
  bool _preferencesForMeal = false;
  List<String> _preferenceTags = [];

  // ── Live-Test-8 ISSUE-002: preference MODE state (edit mode only) ──────────
  // The Edit Meal sheet exposes BOTH mutually exclusive preference modes:
  // Standalone tags (inline editor below) and Preference Groups (the premium
  // builder screen). Switching modes SUSPENDS — never deletes — the meal's
  // group bindings server-side, so the admin's configuration always survives.
  final _prefRepo = PreferenceRepository();
  List<String> _activeGroupNames = const [];
  List<String> _suspendedGroupNames = const [];
  bool _bindingsBusy = false;

  /// True when Groups was the meal's most recent active mode — the master
  /// switch restores the saved groups (instead of standalone tags) on
  /// re-enable, exactly as the admin last configured it.
  bool _lastModeWasGroups = false;

  /// Groups mode is active while the meal has ACTIVE (non-suspended) bindings.
  bool get _groupsMode => _activeGroupNames.isNotEmpty;

  // ── Image state ────────────────────────────────────────────────────────────
  final List<Uint8List> _imageBytesList = [];
  /// Existing photo when it is a network URL (MinIO/CDN) rather than base64 —
  /// shown as a preview and preserved on save unless the admin replaces or
  /// removes it. Null once replaced/removed or for base64/no-photo meals.
  String? _existingImageUrl;
  bool _isPickingImages = false;
  String? _imageError;

  static const int _maxTotalBytes = AppConstants.maxMealImageBytes; // 100 KB

  // ── Validation ─────────────────────────────────────────────────────────────
  String? _windowError;
  bool _shortWindowWarning = false;

  // ── Live-Test-9 ISSUE-001: submit lifecycle owned by the FORM ─────────────
  // The sheet that hosts this form is built once and never rebuilds on
  // provider notifications, so `widget.isSaving` is frozen at open time. The
  // form itself is stateful — it guards re-entry (rapid taps), disables the
  // button while the request runs, and surfaces the server's error inline
  // while preserving everything the admin typed.
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final m = widget.initialMeal;
    if (m != null) {
      _nameCtrl.text = m.name;
      _descCtrl.text = m.description ?? '';
      _slotKeyCtrl.text = m.slotKey;
      _order = m.order;
      _menuItems = List.of(m.menuItems);
      // Live-Test-8 ISSUE-002: the master switch covers BOTH modes — flat
      // standalone tags OR active preference groups count as "preferences ON".
      _preferencesForMeal = m.hasPreferences || m.preferenceGroups.isNotEmpty;
      _activeGroupNames = m.preferenceGroups.map((g) => g.label).toList();
      _lastModeWasGroups = m.preferenceGroups.isNotEmpty;
      // Server truth (including SAVED/suspended groups) replaces the cached
      // list-model snapshot as soon as it arrives.
      _refreshGroupState();
      _preferenceTags = m.enabledPreferences.isNotEmpty
          ? List.of(m.enabledPreferences)
          : List.of(_kDefaultPreferenceTags);
      _priceCtrl.text = m.price?.toString() ?? '';
      // Restore the existing photo when editing. Local/base64 photos decode to
      // bytes; a migrated network URL (MinIO/CDN) is kept as [_existingImageUrl]
      // so it shows as a preview and is preserved on save (not wiped).
      final existing = m.displayImageBytes;
      if (existing != null) {
        _imageBytesList.add(existing);
      } else {
        _existingImageUrl = m.networkImageUrl;
      }
      // Parse window times
      final openParts = m.attendanceWindow.openTime.split(':');
      final closeParts = m.attendanceWindow.closeTime.split(':');
      if (openParts.length >= 2) {
        _openTime = TimeOfDay(
          hour: int.tryParse(openParts[0]) ?? 7,
          minute: int.tryParse(openParts[1]) ?? 0,
        );
      }
      if (closeParts.length >= 2) {
        _closeTime = TimeOfDay(
          hour: int.tryParse(closeParts[0]) ?? 9,
          minute: int.tryParse(closeParts[1]) ?? 0,
        );
      }
    } else if (widget.initialPreferencesEnabled) {
      // New meal — inherit the global preference state so admins don't have
      // to manually enable preferences on each meal after turning the global
      // toggle on.  Individual override is still possible before saving.
      _preferencesForMeal = true;
      _preferenceTags = List.of(_kDefaultPreferenceTags);
    }
    _validateWindow();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _slotKeyCtrl.dispose();
    _menuItemCtrl.dispose();
    _tagCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  int get _windowMinutes => _toMinutes(_closeTime) - _toMinutes(_openTime);

  void _validateWindow() {
    final diff = _windowMinutes;
    if (diff <= 0) {
      _windowError = 'Close time must be after open time.';
      _shortWindowWarning = false;
    } else {
      _windowError = null;
      _shortWindowWarning = diff < 30;
    }
  }

  /// When group pricing is ON, a valid (>= 0) price is mandatory before saving.
  bool get _priceValid =>
      !widget.pricingEnabled ||
      (int.tryParse(_priceCtrl.text.trim()) != null &&
          int.parse(_priceCtrl.text.trim()) >= 0);

  /// Issue 3: once today's attendance window has opened, the price is locked so
  /// a later edit can't change what members were already shown / billed. Only
  /// applies when editing an EXISTING meal (new meals are always editable). The
  /// backend enforces the same rule; this just disables the field early.
  bool get _priceLocked {
    if (widget.initialMeal == null || !widget.pricingEnabled) return false;
    // Locked ONLY while the window is currently open (open <= now <= close).
    // Editable before it opens and after it closes (applies going forward).
    final now = TimeOfDay.now();
    final nowM = now.hour * 60 + now.minute;
    return nowM >= _toMinutes(_openTime) && nowM <= _toMinutes(_closeTime);
  }

  bool get _canSave =>
      !widget.isSaving &&
      !_submitting &&
      _nameCtrl.text.trim().isNotEmpty &&
      _windowError == null &&
      _priceValid;

  /// Snapshot of every entered value — shared by Save and the create-mode
  /// Preference-Groups auto-save so the two paths can never drift.
  MealFormData _collectFormData() {
    return MealFormData(
      name: _nameCtrl.text.trim(),
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      slotKey: _slotKeyCtrl.text.trim().isEmpty
          ? 'meal'
          : _slotKeyCtrl.text.trim().toLowerCase(),
      order: _order,
      openTime: _formatTime(_openTime),
      closeTime: _formatTime(_closeTime),
      menuItems: List.of(_menuItems),
      // Live-Test-8 ISSUE-002: flat tags apply ONLY in Standalone mode —
      // Groups mode keeps the flat list empty (mutual exclusivity; groups
      // ride on bindings).
      enablePreferences: _preferencesForMeal && !_groupsMode
          ? List.of(_preferenceTags)
          : const [],
      imageBytes: List.of(_imageBytesList),
      // No new bytes but an existing network photo remains → leave the
      // server's imageUrl untouched (don't wipe it).
      imageUntouched: _imageBytesList.isEmpty && _existingImageUrl != null,
      price:
          widget.pricingEnabled ? int.tryParse(_priceCtrl.text.trim()) : null,
    );
  }

  /// Live-Test-9 ISSUE-001: single-flight submit. Awaits the given handler and
  /// either clears (success — the host pops its own sheet) or shows the
  /// returned error inline with all entered data preserved. Re-entry is
  /// impossible while a submit is in flight. Returns true on success.
  Future<bool> _submitWith(
    Future<String?> Function(MealFormData data) handler,
  ) async {
    if (_submitting || widget.isSaving) return false;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    String? error;
    try {
      error = await handler(_collectFormData());
    } catch (_) {
      // A handler that throws must never freeze or crash the sheet.
      error = 'Something went wrong while saving. Please try again.';
    }
    if (!mounted) return error == null;
    setState(() {
      _submitting = false;
      _submitError = error;
    });
    return error == null;
  }

  Future<void> _handleSave() => _submitWith(widget.onSave);

  int get _totalImageBytes =>
      _imageBytesList.fold(0, (sum, b) => sum + b.length);

  String _formatKb(int bytes) {
    final kb = bytes / 1024;
    return kb >= 1 ? '${kb.toStringAsFixed(1)} KB' : '${bytes}B';
  }

  // ── Time picking ───────────────────────────────────────────────────────────

  Future<void> _pickTime(BuildContext context, bool isOpen) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpen ? _openTime : _closeTime,
      builder: forceAmPmTimePicker,
    );
    if (picked != null) {
      setState(() {
        if (isOpen) {
          _openTime = picked;
        } else {
          _closeTime = picked;
        }
        _validateWindow();
      });
    }
  }

  // ── Menu items ─────────────────────────────────────────────────────────────

  void _addMenuItem() {
    final text = _menuItemCtrl.text.trim();
    if (text.isNotEmpty && !_menuItems.contains(text)) {
      setState(() {
        _menuItems.add(text);
        _menuItemCtrl.clear();
      });
    }
  }

  // ── Preference tags ────────────────────────────────────────────────────────

  void _addTag() {
    final text = _tagCtrl.text.trim();
    // Live-Test-7 ISSUE-2: 2..5 window, asserted before the round-trip.
    if (_preferenceTags.length >= _kMaxPreferenceTags) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('At most $_kMaxPreferenceTags preference options.')));
      return;
    }
    if (text.isNotEmpty && !_preferenceTags.contains(text)) {
      setState(() {
        _preferenceTags.add(text);
        _tagCtrl.clear();
      });
    }
  }

  // ── Live-Test-8 ISSUE-002: preference mode helpers (edit mode only) ────────

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Refreshes the meal's ACTIVE + SAVED (suspended) preference groups so the
  /// mode cards always reflect server truth (e.g. after the premium Groups
  /// builder pops). Edit mode only — a new meal has no bindings yet.
  Future<void> _refreshGroupState() async {
    final m = widget.initialMeal;
    if (m == null) return;
    final res = await _prefRepo.getForMealWithSuspended(m.id);
    if (!mounted) return;
    if (res case Ok(:final value)) {
      setState(() {
        _activeGroupNames = value.active.map((g) => g.label).toList();
        _suspendedGroupNames = value.suspended.map((g) => g.label).toList();
        if (value.active.isNotEmpty) {
          _preferencesForMeal = true;
          _lastModeWasGroups = true;
        }
      });
    }
  }

  /// Suspend (false → Standalone) or restore (true → Groups) ALL of the
  /// meal's group bindings — the non-destructive mode switch (server keeps
  /// every group + option stored either way).
  Future<bool> _setBindingsActive(bool active) async {
    final m = widget.initialMeal;
    if (m == null) return false;
    setState(() => _bindingsBusy = true);
    final res = await _prefRepo.setMealBindingsActive(m.id, active: active);
    if (!mounted) return false;
    if (res case Err(:final failure)) {
      setState(() => _bindingsBusy = false);
      _toast(failure.message);
      return false;
    }
    setState(() {
      _bindingsBusy = false;
      if (active) {
        _activeGroupNames = List.of(_suspendedGroupNames);
        _suspendedGroupNames = const [];
      } else {
        _suspendedGroupNames = List.of(_activeGroupNames);
        _activeGroupNames = const [];
      }
    });
    return true;
  }

  /// Mode card: Standalone. Active groups are SAVED — never deleted — and
  /// restore exactly on switching back to Groups.
  Future<void> _selectStandaloneMode() async {
    if (_bindingsBusy || widget.isSaving || !_groupsMode) return;
    final count = _activeGroupNames.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch to Standalone?'),
        content: Text(
          '$count preference group(s) will be SAVED — not deleted. Members '
          'pick ONE simple tag instead. Switch back to Preference Groups any '
          'time and your groups return exactly as configured. This applies '
          'immediately.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await _setBindingsActive(false)) {
      setState(() {
        _lastModeWasGroups = false;
        if (_preferenceTags.isEmpty) {
          _preferenceTags = List.of(_kDefaultPreferenceTags);
        }
      });
      _toast('$count group(s) saved — switch back any time to restore');
    }
  }

  /// Mode card: Preference Groups → the premium Groups builder (create
  /// groups, restore saved ones, edit rules). Server truth reloads on return.
  ///
  /// Live-Test-9 ISSUE-5.1/5.2: on a NEW meal the same card now works too —
  /// groups need a meal id, so the meal is saved automatically first and the
  /// host opens the builder for it (identical workflow to Edit Meal, zero
  /// manual steps).
  Future<void> _openGroupsBuilder() async {
    if (_bindingsBusy || widget.isSaving || _submitting) return;
    final m = widget.initialMeal;
    if (m == null) {
      final handler = widget.onSaveForGroups;
      if (handler == null) return;
      if (!_canSave) {
        setState(() => _submitError =
            'Complete the meal details first — a name and a valid attendance '
            'window are required before configuring Preference Groups.');
        return;
      }
      await _submitWith(handler);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PreferenceGroupsScreen(meal: m),
    ));
    if (!mounted) return;
    await _refreshGroupState();
  }

  /// Master preference switch — non-destructive in BOTH directions: turning
  /// OFF while Groups mode is active suspends (saves) the groups; turning ON
  /// restores whichever mode was last active.
  Future<void> _onPreferenceToggle(bool v) async {
    if (_bindingsBusy) return;
    if (!v) {
      if (_groupsMode) {
        final count = _activeGroupNames.length;
        if (!await _setBindingsActive(false)) return;
        _lastModeWasGroups = true;
        _toast('$count group(s) saved — re-enable to restore');
      }
      if (mounted) setState(() => _preferencesForMeal = false);
      return;
    }
    if (_lastModeWasGroups && _suspendedGroupNames.isNotEmpty) {
      if (await _setBindingsActive(true)) {
        if (mounted) setState(() => _preferencesForMeal = true);
      }
      return;
    }
    setState(() {
      _preferencesForMeal = true;
      if (_preferenceTags.isEmpty) {
        _preferenceTags = List.of(_kDefaultPreferenceTags);
      }
    });
  }

  // ── Image picking + compression ────────────────────────────────────────────

  Future<void> _pickImages() async {
    setState(() {
      _isPickingImages = true;
      _imageError = null;
    });

    try {
      final picker = ImagePicker();
      // One photo per meal — pick a single image; a new pick REPLACES the
      // previous one (old bytes discarded) so storage never keeps copies.
      final file = await picker.pickImage(source: ImageSource.gallery);

      // The gallery picker backgrounds the activity; on aggressive OEMs (MIUI)
      // this form's state can be disposed before the pick returns. Every resume
      // point below re-checks `mounted` — a setState on a disposed state throws
      // into the global error handler.
      if (!mounted) return;
      if (file == null) {
        setState(() => _isPickingImages = false);
        return;
      }

      final rawBytes = await file.readAsBytes();

      // Live-Test-11 ISSUE-007: guaranteed-fit ladder (resolution + quality
      // steps, aspect ratio preserved, no cropping) — the old quality-only
      // ladder rejected detailed photos that stayed over the cap at q=20.
      final compressed =
          await compressImageToBudget(rawBytes, _maxTotalBytes);

      if (!mounted) return;
      if (compressed == null || compressed.isEmpty) {
        setState(() => _imageError =
            'Could not process this photo. Please try another.');
        return;
      }

      if (compressed.length > _maxTotalBytes) {
        setState(() => _imageError =
            'Photo is too large even after compression (limit '
            '${_maxTotalBytes ~/ 1024} KB). Try a smaller image.');
        return;
      }

      // Replace any existing image with the new single photo (this also
      // supersedes a migrated network photo, if any).
      setState(() {
        _existingImageUrl = null;
        _imageBytesList
          ..clear()
          ..add(compressed);
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => _imageError = 'Could not pick the photo. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isPickingImages = false);
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageBytesList.removeAt(index);
      _imageError = null;
    });
  }

  /// Remove the existing (migrated network) photo — clears it on save.
  void _removeExistingImage() {
    setState(() {
      _existingImageUrl = null;
      _imageError = null;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Name ──────────────────────────────────────────────────────────
        TextField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Meal Name *',
            hintText: 'e.g. Breakfast, Evening Tea',
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.inputRadius),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Slot key ──────────────────────────────────────────────────────
        const Text(
          'Slot Key',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'Lowercase identifier for this meal slot (e.g. "breakfast", "morning_tea", "iftar"). Used for analytics grouping.',
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _slotKeyCtrl,
          decoration: InputDecoration(
            hintText: 'e.g. breakfast, lunch, morning_tea',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.inputRadius),
            ),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),

        // ── Display order ─────────────────────────────────────────────────
        const Text(
          'Display Order',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'Position in the daily timeline (0 = first).',
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.outlined(
              icon: const Icon(Icons.remove),
              onPressed: _order > 0 ? () => setState(() => _order--) : null,
            ),
            const SizedBox(width: 12),
            Text(
              '$_order',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            IconButton.outlined(
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _order++),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Attendance window ─────────────────────────────────────────────
        const Text(
          'Attendance Window',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TimePicker(
                label: 'Opens at',
                time: _openTime,
                onTap: () => _pickTime(context, true),
                hasError: _windowError != null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimePicker(
                label: 'Closes at',
                time: _closeTime,
                onTap: () => _pickTime(context, false),
                hasError: _windowError != null,
              ),
            ),
          ],
        ),

        // ── Error / warning ───────────────────────────────────────────────
        if (_windowError != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 14, color: AppColors.error),
              const SizedBox(width: 4),
              Text(
                _windowError!,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.error),
              ),
            ],
          ),
        ] else if (_shortWindowWarning) ...[
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 14, color: AppColors.warning),
              SizedBox(width: 4),
              Text(
                'Window is less than 30 minutes — students may miss it.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.warning),
              ),
            ],
          ),
        ],

        // ── Visual timeline ───────────────────────────────────────────────
        if (_windowError == null) ...[
          const SizedBox(height: 10),
          _AttendanceTimeline(
            openTime: _openTime,
            closeTime: _closeTime,
          ),
        ],
        const SizedBox(height: 16),

        // ── Description ───────────────────────────────────────────────────
        TextField(
          controller: _descCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Description (optional)',
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.inputRadius),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Meal price (when group pricing enabled) ───────────────────────
        if (widget.pricingEnabled) ...[
          TextField(
            controller: _priceCtrl,
            enabled: !_priceLocked,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Meal Price (₹) *',
              hintText: 'e.g. 75',
              prefixText: '₹ ',
              suffixIcon: _priceLocked
                  ? const Icon(Icons.lock_rounded,
                      size: 18, color: AppColors.textTertiary)
                  : null,
              helperText: _priceLocked
                  ? 'Price locked — attendance window has started.'
                  : 'Required while meal pricing is enabled.',
              helperStyle: _priceLocked
                  ? const TextStyle(color: AppColors.warning)
                  : null,
              errorText: _priceValid ? null : 'Enter a valid price',
              filled: true,
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.inputRadius),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Meal images ───────────────────────────────────────────────────
        _buildImageSection(colorScheme),
        const SizedBox(height: 16),

        // ── Menu items ────────────────────────────────────────────────────
        const Text(
          'Menu Items',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _menuItemCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Dal, Rice, Chapati',
                  filled: true,
                  fillColor: colorScheme.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.inputRadius),
                  ),
                ),
                onSubmitted: (_) => _addMenuItem(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _addMenuItem,
              icon: const Icon(Icons.add_rounded, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(10),
              ),
            ),
          ],
        ),
        if (_menuItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Builder(builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final chipBg = isDark
                ? AppColors.surfaceVariantDark
                : AppColors.primary.withValues(alpha: 0.08);
            final chipFg =
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _menuItems
                  .map((item) => Chip(
                        label: Text(
                          item,
                          style: TextStyle(
                            fontSize: 12,
                            color: chipFg,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        backgroundColor: chipBg,
                        side: BorderSide(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.border,
                        ),
                        deleteIcon: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: chipFg.withValues(alpha: 0.7),
                        ),
                        onDeleted: () =>
                            setState(() => _menuItems.remove(item)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            );
          }),
        ],
        const SizedBox(height: 16),

        // ── Preference tags toggle ─────────────────────────────────────────
        _buildPreferenceToggle(colorScheme),
        const SizedBox(height: 24),

        // ── Live-Test-9 ISSUE-001: inline save error (data preserved) ─────
        if (_submitError != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 18, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _submitError!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Save button ───────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _canSave ? _handleSave : null,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppConstants.buttonRadius),
              ),
            ),
            child: widget.isSaving || _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Meal'),
          ),
        ),
      ],
    );
  }

  // ── Image section widget ───────────────────────────────────────────────────

  Widget _buildImageSection(ColorScheme colorScheme) {
    final usedKb = _totalImageBytes;
    final limitKb = _maxTotalBytes;
    final usageRatio = (usedKb / limitKb).clamp(0.0, 1.0);
    final isNearLimit = usageRatio > 0.8;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _imageError != null
              ? AppColors.error.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      size: 16, color: AppColors.info),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Meal Image',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        'One photo · ${limitKb ~/ 1024} KB max',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Always allow picking — a new pick replaces the existing photo.
                _isPickingImages
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton.icon(
                        onPressed: _pickImages,
                        icon: Icon(
                          (_imageBytesList.isEmpty && _existingImageUrl == null)
                              ? Icons.add_photo_alternate_rounded
                              : Icons.swap_horiz_rounded,
                          size: 16,
                        ),
                        label: Text(
                          (_imageBytesList.isEmpty && _existingImageUrl == null)
                              ? 'Add'
                              : 'Replace',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
              ],
            ),
          ),

          // Image preview gallery
          if (_imageBytesList.isNotEmpty) ...[
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _imageBytesList.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  return _ImageThumb(
                    bytes: _imageBytesList[i],
                    sizeLabel: _formatKb(_imageBytesList[i].length),
                    onRemove: () => _removeImage(i),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ]
          // Existing photo stored as a network URL (migrated to MinIO/CDN) —
          // shown with caching; preserved on save unless replaced/removed.
          else if (_existingImageUrl != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _NetworkImageThumb(
                url: _existingImageUrl!,
                onRemove: _removeExistingImage,
              ),
            ),
            const SizedBox(height: 10),
          ],

          // KB usage bar
          if (usedKb > 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usageRatio,
                      minHeight: 5,
                      backgroundColor:
                          colorScheme.outlineVariant.withValues(alpha: 0.3),
                      color: isNearLimit
                          ? AppColors.warning
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatKb(usedKb)} used of ${_formatKb(limitKb)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isNearLimit
                          ? AppColors.warning
                          : colorScheme.onSurfaceVariant,
                      fontWeight: isNearLimit
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Empty state
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: GestureDetector(
                onTap: _isPickingImages ? null : _pickImages,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.4),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Center(
                    child: _isPickingImages
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Text(
                                'Tap to add photo',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],

          // Error message
          if (_imageError != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 13, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _imageError!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Preference toggle widget ───────────────────────────────────────────────

  Widget _buildPreferenceToggle(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _preferencesForMeal
              ? AppColors.primary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Icon(
                  Icons.local_offer_rounded,
                  size: 18,
                  color: _preferencesForMeal
                      ? AppColors.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enable Meal Preferences',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        _groupsMode
                            ? 'Members complete each preference group when marking attendance.'
                            : 'Students select a tag (Veg, Fish, etc.) when marking attendance.',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _preferencesForMeal,
                  // Live-Test-8 ISSUE-002: non-destructive both ways — OFF
                  // saves active groups, ON restores the last active mode.
                  onChanged:
                      _bindingsBusy ? null : (v) => _onPreferenceToggle(v),
                ),
              ],
            ),
          ),
          if (_preferencesForMeal) ...[
            Divider(
                height: 1,
                color: colorScheme.outlineVariant
                    .withValues(alpha: 0.4)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Live-Test-9 ISSUE-5.1: BOTH preference modes on CREATE
                  // and EDIT — the exact same workflow. On a new meal,
                  // choosing Preference Groups auto-saves it and opens the
                  // builder (ISSUE-5.2); modes stay mutually exclusive and
                  // switchable without losing configuration.
                  // Live-Test-11 ISSUE-011: IntrinsicHeight + stretch — both
                  // mode cards stay the same height however their subtitles
                  // wrap (identical size/spacing across Create/Edit/Override).
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _PrefModeCard(
                            icon: Icons.sell_rounded,
                            title: 'Standalone',
                            subtitle: 'Members pick ONE simple tag',
                            selected: !_groupsMode,
                            busy: _bindingsBusy || _submitting,
                            accent: AppColors.secondary,
                            onTap: _selectStandaloneMode,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PrefModeCard(
                            icon: Icons.account_tree_rounded,
                            title: 'Preference Groups',
                            subtitle: widget.initialMeal == null
                                ? 'Saves the meal & opens the builder'
                                : _groupsMode
                                    ? '${_activeGroupNames.length} active group(s)'
                                    : (_suspendedGroupNames.isNotEmpty
                                        ? '${_suspendedGroupNames.length} saved — tap to manage'
                                        : 'Rules, veg flags, price add-ons'),
                            selected: _groupsMode,
                            busy: _bindingsBusy || _submitting,
                            accent: AppColors.primary,
                            onTap: _openGroupsBuilder,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_groupsMode)
                    _buildGroupsSummary(colorScheme)
                  else ...[
                  Text(
                    'Tags  ·  ${_preferenceTags.length} of $_kMaxPreferenceTags',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _preferenceTags
                        .map((tag) => _PreferenceTagChip(
                              label: tag,
                              // ISSUE-2: keep the 2-option floor — one
                              // option is not a choice.
                              onRemove: _preferenceTags.length >
                                      _kMinPreferenceTags
                                  ? () => setState(
                                      () => _preferenceTags.remove(tag))
                                  : null,
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagCtrl,
                          textCapitalization:
                              TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: 'Add custom tag…',
                            filled: true,
                            fillColor:
                                colorScheme.surfaceContainerLowest,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.inputRadius),
                              borderSide: BorderSide(
                                  color: colorScheme.outlineVariant),
                            ),
                          ),
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _addTag,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap × to remove a tag. At least one tag required.',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Live-Test-8 ISSUE-002: Groups-mode body — the active groups at a glance
  /// with a direct path into the premium Groups builder.
  Widget _buildGroupsSummary(ColorScheme colorScheme) {
    return InkWell(
      onTap: _openGroupsBuilder,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _activeGroupNames
                  .map((n) => Chip(
                        label: Text(n,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                            color:
                                AppColors.primary.withValues(alpha: 0.35)),
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.08),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.tune_rounded,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Tap to manage groups, options & rules',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Live-Test-9 ISSUE-5.3/5.4: premium preference mode card ──────────────────

/// Rich selection card for the preference mode switch (Create AND Edit Meal —
/// identical workflow). Gradient-tinted icon badge, animated gradient fill,
/// glow shadow and scaling check on selection; explicit high-contrast colors
/// in both themes.
class _PrefModeCard extends StatelessWidget {
  const _PrefModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.busy,
    required this.onTap,
    this.accent = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  /// Per-mode identity color — Standalone and Groups get distinct vibrant
  /// accents so the two modes read at a glance.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: busy ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              accent.withValues(alpha: 0.28),
                              accent.withValues(alpha: 0.10),
                            ]
                          : [
                              accent.withValues(alpha: 0.14),
                              accent.withValues(alpha: 0.04),
                            ],
                    )
                  : null,
              color: selected ? null : colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? accent
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: isDark ? 0.30 : 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Gradient icon badge — the card's visual identity.
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: selected
                              ? [accent, Color.lerp(accent, Colors.black, 0.25)!]
                              : [
                                  accent.withValues(alpha: 0.18),
                                  accent.withValues(alpha: 0.10),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon,
                          size: 16,
                          color: selected ? Colors.white : accent),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        key: ValueKey(selected),
                        size: 18,
                        color: selected
                            ? accent
                            : colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                    color: selected
                        ? (isDark
                            ? Color.lerp(accent, Colors.white, 0.45)!
                            : Color.lerp(accent, Colors.black, 0.25)!)
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.25,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Attendance timeline ────────────────────────────────────────────────────────

/// Visual horizontal bar showing the full 24-hour day with the attendance
/// window highlighted in primary colour.
class _AttendanceTimeline extends StatelessWidget {
  const _AttendanceTimeline({
    required this.openTime,
    required this.closeTime,
  });

  final TimeOfDay openTime;
  final TimeOfDay closeTime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final openFraction = (openTime.hour * 60 + openTime.minute) / (24 * 60);
    final closeFraction = (closeTime.hour * 60 + closeTime.minute) / (24 * 60);
    final windowFraction = (closeFraction - openFraction).clamp(0.0, 1.0);
    final durationMin =
        closeTime.hour * 60 + closeTime.minute - openTime.hour * 60 - openTime.minute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Window: ${TimeFormat.tod12(openTime)} → ${TimeFormat.tod12(closeTime)} '
          '($durationMin min)',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final leftOffset = totalWidth * openFraction;
                final barWidth = totalWidth * windowFraction;

                return Stack(
                  children: [
                    // Track
                    Container(
                      width: totalWidth,
                      height: 10,
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.25),
                    ),
                    // Active window
                    Positioned(
                      left: leftOffset,
                      child: Container(
                        width: barWidth,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '00:00',
              style: TextStyle(
                  fontSize: 9, color: colorScheme.onSurfaceVariant),
            ),
            Text(
              '12:00',
              style: TextStyle(
                  fontSize: 9, color: colorScheme.onSurfaceVariant),
            ),
            Text(
              '24:00',
              style: TextStyle(
                  fontSize: 9, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Image thumbnail ────────────────────────────────────────────────────────────

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({
    required this.bytes,
    required this.sizeLabel,
    required this.onRemove,
  });

  final Uint8List bytes;
  final String sizeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            bytes,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            cacheWidth: 160, // 2x for sharp rendering, no larger
          ),
        ),
        // Size label
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              sizeLabel,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        // Remove button
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 13, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Network image thumbnail (existing migrated photo) ───────────────────────────

class _NetworkImageThumb extends StatelessWidget {
  const _NetworkImageThumb({
    required this.url,
    required this.onRemove,
  });

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedPhoto(
            url: url,
            width: 80,
            height: 80,
            cacheWidth: 160, // 2x for sharp rendering, no larger
            useThumbnail: true,
            placeholder: Container(
              width: 80,
              height: 80,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.image_outlined, size: 22),
            ),
          ),
        ),
        // Remove button
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 13, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Time picker tile ──────────────────────────────────────────────────────────

class _TimePicker extends StatelessWidget {
  const _TimePicker({
    required this.label,
    required this.time,
    required this.onTap,
    this.hasError = false,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          border: Border.all(
            color: hasError
                ? AppColors.error
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.access_time_rounded,
              size: 16,
              color: hasError
                  ? AppColors.error
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: hasError
                        ? AppColors.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  TimeFormat.tod12(time),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: hasError ? AppColors.error : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preference tag chip ───────────────────────────────────────────────────────

class _PreferenceTagChip extends StatelessWidget {
  const _PreferenceTagChip({
    required this.label,
    this.onRemove,
  });

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(
        left: 10,
        right: onRemove != null ? 4 : 10,
        top: 6,
        bottom: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color:
                      colorScheme.onSurface.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 11,
                  color: AppColors.primary.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Data class returned by form ───────────────────────────────────────────────

class MealFormData {
  const MealFormData({
    required this.name,
    required this.slotKey,
    required this.order,
    required this.openTime,
    required this.closeTime,
    this.description,
    this.menuItems = const [],
    this.enablePreferences = const [],
    this.imageBytes = const [],
    this.imageUntouched = false,
    this.price,
  });

  final String name;
  final String slotKey;
  final int order;
  final String openTime;   // "HH:mm"
  final String closeTime;  // "HH:mm"
  final String? description;
  final List<String> menuItems;
  final List<String> enablePreferences;
  /// Compressed image bytes ready for storage. Empty list = no images.
  final List<Uint8List> imageBytes;

  /// True when [imageBytes] is empty only because an existing network photo was
  /// kept as-is (not replaced/removed). Callers should then leave the server's
  /// imageUrl untouched (pass null) instead of clearing it.
  final bool imageUntouched;

  /// Additive: ₹ meal price (null when pricing disabled or left blank).
  final int? price;
}
