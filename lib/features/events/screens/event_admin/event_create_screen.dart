import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/features/events/providers/event_admin_provider.dart';

// ── EventCreateScreen ──────────────────────────────────────────────────────────

/// Premium event creation form.
///
/// Fields:
///   - Event name
///   - Event type (chip selector)
///   - Event date (date picker)
///   - Expected guest count
///   - Auto-delete after 7 days toggle
///   - Meal options: veg, non-veg, children's meals
///
/// On success → navigates to EventAdminShell for the created event.
/// On cancel → pops back to EventAdminLandingScreen.
class EventCreateScreen extends StatefulWidget {
  const EventCreateScreen({super.key});

  @override
  State<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends State<EventCreateScreen>
    with TickerProviderStateMixin {
  // ── Form state ─────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _guestCountCtrl = TextEditingController(text: '50');
  final _guestCountFocus = FocusNode();

  EventType _selectedType = EventType.wedding;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  bool _autoDelete = true;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _isCreating = false;
  String? _nameError;
  String? _guestError;

  // ── Animations ─────────────────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entryFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ));
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _guestCountCtrl.dispose();
    _guestCountFocus.dispose();
    super.dispose();
  }

  // ── Date picker ────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.vacation,
                  onPrimary: Colors.white,
                  surface: isDark ? AppColors.surfaceDark : AppColors.surface,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  bool _validate() {
    bool ok = true;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Event name is required');
      ok = false;
    } else if (name.length < 3) {
      setState(() => _nameError = 'Name must be at least 3 characters');
      ok = false;
    } else {
      setState(() => _nameError = null);
    }

    final guestStr = _guestCountCtrl.text.trim();
    final guestCount = int.tryParse(guestStr);
    if (guestCount == null || guestCount < 1) {
      setState(() => _guestError = 'Enter a valid guest count (min 1)');
      ok = false;
    } else {
      setState(() => _guestError = null);
    }

    return ok;
  }

  // ── Create event ───────────────────────────────────────────────────────────

  Future<void> _createEvent() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    final auth = AuthProviderScope.of(context);
    final provider = EventAdminProvider();

    setState(() => _isCreating = true);

    final created = await provider.createEvent(
      name: _nameCtrl.text.trim(),
      type: _selectedType,
      date: _selectedDate,
      expectedGuestCount: int.parse(_guestCountCtrl.text.trim()),
      adminId: auth.currentUser?.id ?? 'admin_event_001',
      adminName: auth.currentUser?.name ?? 'Event Admin',
      autoDeleteAfter7Days: _autoDelete,
    );

    provider.dispose();

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (created != null) {
      context.go('/event-admin/event/${created.id}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to create event. Please try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ── Formatted date ─────────────────────────────────────────────────────────

  String get _formattedDate {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${_selectedDate.day} ${months[_selectedDate.month - 1]} ${_selectedDate.year}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      body: Stack(
        children: [
          _EventCreateBackground(isDark: isDark),
          SafeArea(
            child: Column(
              children: [
                // ── Navigation bar ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                      // Event tag pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.vacation, Color(0xFFEC4899)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_rounded,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              'New Event',
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),

                // ── Scrollable form ────────────────────────────────────────
                Expanded(
                  child: FadeTransition(
                    opacity: _entryFade,
                    child: SlideTransition(
                      position: _entrySlide,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                            AppConstants.pagePaddingH,
                            4,
                            AppConstants.pagePaddingH,
                            40),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Header ─────────────────────────────────
                              const SizedBox(height: 8),
                              Text(
                                'Create Event',
                                style: AppTypography.headlineMedium.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Set up your event, generate a QR, and start managing guests.',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 28),

                              // ── Event name ─────────────────────────────
                              _SectionLabel(
                                  label: 'Event Name', isDark: isDark),
                              const SizedBox(height: 10),
                              _GlassField(
                                controller: _nameCtrl,
                                focusNode: _nameFocus,
                                hint: 'e.g. Mahanta Wedding Reception',
                                isDark: isDark,
                                errorText: _nameError,
                                textCapitalization:
                                    TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) =>
                                    setState(() => _nameError = null),
                                onSubmitted: (_) =>
                                    _guestCountFocus.requestFocus(),
                              ),
                              if (_nameError != null) ...[
                                const SizedBox(height: 6),
                                _ErrorText(
                                    text: _nameError!, isDark: isDark),
                              ],
                              const SizedBox(height: 24),

                              // ── Event type ─────────────────────────────
                              _SectionLabel(
                                  label: 'Event Type', isDark: isDark),
                              const SizedBox(height: 12),
                              _EventTypeSelector(
                                selected: _selectedType,
                                isDark: isDark,
                                onChanged: (t) =>
                                    setState(() => _selectedType = t),
                              ),
                              const SizedBox(height: 24),

                              // ── Event date ─────────────────────────────
                              _SectionLabel(
                                  label: 'Event Date', isDark: isDark),
                              const SizedBox(height: 10),
                              _DatePickerTile(
                                formattedDate: _formattedDate,
                                isDark: isDark,
                                onTap: _pickDate,
                              ),
                              const SizedBox(height: 24),

                              // ── Expected guests ────────────────────────
                              _SectionLabel(
                                  label: 'Expected Guests',
                                  isDark: isDark),
                              const SizedBox(height: 10),
                              _GlassField(
                                controller: _guestCountCtrl,
                                focusNode: _guestCountFocus,
                                hint: 'e.g. 100',
                                isDark: isDark,
                                errorText: _guestError,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                                textInputAction: TextInputAction.done,
                                onChanged: (_) =>
                                    setState(() => _guestError = null),
                              ),
                              if (_guestError != null) ...[
                                const SizedBox(height: 6),
                                _ErrorText(
                                    text: _guestError!, isDark: isDark),
                              ],
                              const SizedBox(height: 28),

                              // ── Meal types info ────────────────────────
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.info.withValues(
                                      alpha: isDark ? 0.1 : 0.06),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppColors.info
                                          .withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                        Icons.restaurant_menu_rounded,
                                        size: 16,
                                        color: AppColors.info),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Meal types are configured in the Meals tab after creating the event. You can add Veg, Chicken, Mutton, Dessert and any custom type.',
                                        style:
                                            AppTypography.bodySmall.copyWith(
                                          color: isDark
                                              ? AppColors.textPrimaryDark
                                              : AppColors.textPrimary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),

                              // ── Auto-delete ────────────────────────────
                              _SectionLabel(
                                  label: 'Auto-Delete', isDark: isDark),
                              const SizedBox(height: 10),
                              _AutoDeleteCard(
                                value: _autoDelete,
                                isDark: isDark,
                                onChanged: (v) =>
                                    setState(() => _autoDelete = v),
                              ),
                              const SizedBox(height: 36),

                              // ── Create button ──────────────────────────
                              _CreateEventButton(
                                isLoading: _isCreating,
                                onTap: _isCreating ? () {} : _createEvent,
                              ),
                              const SizedBox(height: 12),
                              // Cancel
                              Center(
                                child: TextButton(
                                  onPressed: _isCreating
                                      ? null
                                      : () => context.pop(),
                                  child: Text(
                                    'Cancel',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event type selector ────────────────────────────────────────────────────────

class _EventTypeSelector extends StatelessWidget {
  const _EventTypeSelector({
    required this.selected,
    required this.isDark,
    required this.onChanged,
  });

  final EventType selected;
  final bool isDark;
  final ValueChanged<EventType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: EventType.values.map((type) {
        final isActive = selected == type;
        return GestureDetector(
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.vacation.withValues(alpha: 0.15)
                  : (isDark
                      ? AppColors.surfaceDark
                      : AppColors.surface),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? AppColors.vacation.withValues(alpha: 0.5)
                    : (isDark
                        ? AppColors.borderDark.withValues(alpha: 0.5)
                        : AppColors.border),
                width: isActive ? 1.5 : 1.0,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppColors.vacation
                            .withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(type.emoji,
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  type.label,
                  style: AppTypography.labelMedium.copyWith(
                    color: isActive
                        ? AppColors.vacation
                        : (isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary),
                    fontWeight: isActive
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Date picker tile ───────────────────────────────────────────────────────────

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.formattedDate,
    required this.isDark,
    required this.onTap,
  });

  final String formattedDate;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.space16, vertical: AppConstants.space16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          border: Border.all(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.vacation.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.calendar_today_rounded,
                  size: 18, color: AppColors.vacation),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Event Date',
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formattedDate,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.edit_calendar_rounded,
              size: 18,
              color: isDark
                  ? AppColors.textTertiaryDark
                  : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Auto-delete card ───────────────────────────────────────────────────────────

class _AutoDeleteCard extends StatelessWidget {
  const _AutoDeleteCard({
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: value
              ? AppColors.warning.withValues(alpha: 0.35)
              : (isDark
                  ? AppColors.borderDark.withValues(alpha: 0.4)
                  : AppColors.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              value
                  ? Icons.auto_delete_rounded
                  : Icons.save_rounded,
              size: 22,
              color: value
                  ? AppColors.warning
                  : (isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-delete after 7 days',
                  style: AppTypography.bodyMedium.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value
                      ? 'All event data and guest records will be automatically deleted 7 days after the event date.'
                      : 'Event data will be retained indefinitely until manually closed.',
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.warning,
          ),
        ],
      ),
    );
  }
}

// ── Create event button ────────────────────────────────────────────────────────

class _CreateEventButton extends StatefulWidget {
  const _CreateEventButton({
    required this.isLoading,
    required this.onTap,
  });

  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<_CreateEventButton> createState() => _CreateEventButtonState();
}

class _CreateEventButtonState extends State<_CreateEventButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Transform.scale(
        scale: _scale.value,
        child: GestureDetector(
          onTapDown: widget.isLoading ? null : (_) => _ctrl.forward(),
          onTapUp: widget.isLoading
              ? null
              : (_) {
                  _ctrl.reverse();
                  widget.onTap();
                },
          onTapCancel: () => _ctrl.reverse(),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.vacation, Color(0xFFEC4899)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius:
                  BorderRadius.circular(AppConstants.buttonRadius + 4),
              boxShadow: widget.isLoading
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.vacation.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: widget.isLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.celebration_rounded,
                          size: 20, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        'Create Event',
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
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

// ── Glass text field ───────────────────────────────────────────────────────────

class _GlassField extends StatefulWidget {
  const _GlassField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.isDark,
    this.errorText,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool isDark;
  final String? errorText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<_GlassField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    widget.focusNode.addListener(() {
      final focused = widget.focusNode.hasFocus;
      if (focused != _hasFocus) {
        setState(() => _hasFocus = focused);
        if (focused) {
          _ctrl.forward();
        } else {
          _ctrl.reverse();
        }
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError =
        widget.errorText != null && widget.errorText!.isNotEmpty;
    final accent = AppColors.vacation;
    final borderColor = hasError
        ? AppColors.error
        : _hasFocus
            ? accent
            : accent.withValues(alpha: widget.isDark ? 0.20 : 0.15);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.inputRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? AppColors.surfaceDark
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.inputRadius),
              border: Border.all(
                color: borderColor,
                width: _hasFocus && !hasError ? 1.8 : 1.2,
              ),
              boxShadow: _hasFocus
                  ? [
                      BoxShadow(
                        color: accent.withValues(
                            alpha: 0.08 + 0.07 * _ctrl.value),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
              textCapitalization: widget.textCapitalization,
              textInputAction: widget.textInputAction,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: AppTypography.bodyLarge.copyWith(
                color: widget.isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: (widget.isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary)
                      .withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.labelLarge.copyWith(
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    );
  }
}

// ── Error text ─────────────────────────────────────────────────────────────────

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text, required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 13, color: AppColors.error),
        const SizedBox(width: 5),
        Text(
          text,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.error,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Background ─────────────────────────────────────────────────────────────────

class _EventCreateBackground extends StatelessWidget {
  const _EventCreateBackground({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.vacation
                        .withValues(alpha: isDark ? 0.10 : 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFEC4899)
                        .withValues(alpha: isDark ? 0.08 : 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
