import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_meal_type.dart';
import 'package:smart_meal_management/features/events/models/guest_person.dart';
import 'package:smart_meal_management/features/events/providers/event_guest_provider.dart';

// ── EventGuestShell ────────────────────────────────────────────────────────────

/// Root shell for the event guest experience.
class EventGuestShell extends StatefulWidget {
  const EventGuestShell({super.key, this.joinCode, this.joinExtra});

  final String? joinCode;
  final EventGuestJoinExtra? joinExtra;

  @override
  State<EventGuestShell> createState() => _EventGuestShellState();
}

class _EventGuestShellState extends State<EventGuestShell> {
  late final EventGuestProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = EventGuestProvider();
    _provider.addListener(_rebuild);
    _init();
  }

  Future<void> _init() async {
    if (widget.joinExtra != null) {
      // Fresh join from QR scan — always supersedes any persisted session.
      final e = widget.joinExtra!;
      final ok = await _provider.loadEventByJoinCode(e.joinCode);
      if (ok) {
        await _provider.joinEvent(
          primaryName: e.primaryName,
          adultsCount: e.adultsCount,
          childrenCount: e.childrenCount,
        );
      }
    } else if (widget.joinCode != null) {
      await _provider.loadEventByJoinCode(widget.joinCode!);
    } else {
      // No incoming join data — try to restore a previously persisted session.
      await _provider.restoreSession();
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EventGuestScope(
      provider: _provider,
      child: _provider.hasJoined
          ? _EventGuestDashboard(provider: _provider)
          : _EventGuestLoadingView(provider: _provider),
    );
  }
}

// ── EventGuestScope ────────────────────────────────────────────────────────────

class EventGuestScope extends InheritedNotifier<EventGuestProvider> {
  const EventGuestScope({
    super.key,
    required EventGuestProvider provider,
    required super.child,
  }) : super(notifier: provider);

  static EventGuestProvider of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<EventGuestScope>();
    assert(scope != null, 'EventGuestScope.of() called outside EventGuestShell');
    return scope!.notifier!;
  }
}

// ── Loading / error view ───────────────────────────────────────────────────────

class _EventGuestLoadingView extends StatelessWidget {
  const _EventGuestLoadingView({required this.provider});
  final EventGuestProvider provider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (provider.isLoading || provider.isJoining) ...[
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.vacation),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  provider.isJoining ? 'Joining event…' : 'Loading event…',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
                ),
              ] else if (provider.error != null) ...[
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline_rounded,
                      size: 36, color: AppColors.error),
                ),
                const SizedBox(height: 20),
                Text(
                  provider.error!,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go(RouteNames.eventGuestJoin),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back to Join'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.vacation,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Full dashboard ─────────────────────────────────────────────────────────────

class _EventGuestDashboard extends StatefulWidget {
  const _EventGuestDashboard({required this.provider});
  final EventGuestProvider provider;

  @override
  State<_EventGuestDashboard> createState() => _EventGuestDashboardState();
}

class _EventGuestDashboardState extends State<_EventGuestDashboard>
    with TickerProviderStateMixin {
  bool _confirmed = false;

  // Dark/light theme toggle scoped to the guest experience
  final ValueNotifier<bool> _isDark = ValueNotifier<bool>(true);

  // Celebration animation controllers
  late final AnimationController _celebrationCtrl;
  late final AnimationController _confirmCheckCtrl;
  final List<_ConfettiParticle> _particles = [];

  @override
  void initState() {
    super.initState();

    _celebrationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _confirmCheckCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Pre-generate confetti particles
    final rng = math.Random();
    for (var i = 0; i < 36; i++) {
      _particles.add(_ConfettiParticle(
        x: rng.nextDouble(),
        delay: rng.nextDouble() * 0.6,
        color: _confettiColors[rng.nextInt(_confettiColors.length)],
        size: 6 + rng.nextDouble() * 7,
        rotationSpeed: (rng.nextDouble() - 0.5) * 4,
        horizontalDrift: (rng.nextDouble() - 0.5) * 0.4,
      ));
    }
  }

  static const List<Color> _confettiColors = [
    AppColors.vacation,
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFF97316),
  ];

  @override
  void dispose() {
    _isDark.dispose();
    _celebrationCtrl.dispose();
    _confirmCheckCtrl.dispose();
    super.dispose();
  }

  // ── Confirmation logic ────────────────────────────────────────────────────

  void _confirmSelections() {
    final party = widget.provider.myParty;
    if (party == null) return;

    final mealTypes = widget.provider.event?.mealTypes ?? [];

    if (mealTypes.isNotEmpty) {
      final pendingCount = party.persons
          .where((p) => p.isPresent && p.selectedMealTypeId == null)
          .length;

      if (pendingCount > 0) {
        _showPendingWarning(pendingCount);
        return;
      }
    }

    HapticFeedback.mediumImpact();
    setState(() => _confirmed = true);
    _confirmCheckCtrl.forward();
    _celebrationCtrl.forward();

    _celebrationCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _celebrationCtrl.reset();
        });
      }
    });

    // Show premium celebration modal after a brief delay
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _showCelebrationModal();
    });
  }

  void _showCelebrationModal() {
    final party = widget.provider.myParty;
    final event = widget.provider.event;
    final mealTypes = event?.mealTypes ?? [];
    final isDark = _isDark.value;

    final Map<String, int> mealCounts = {};
    for (final mt in mealTypes) {
      final count = party?.persons
              .where((p) => p.isPresent && p.selectedMealTypeId == mt.id)
              .length ??
          0;
      if (count > 0) mealCounts[mt.id] = count;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Celebration',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 450),
      transitionBuilder: (ctx, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
      pageBuilder: (ctx, _, _) => _CelebrationModal(
        eventName: event?.name ?? 'Event',
        party: party,
        mealTypes: mealTypes,
        mealCounts: mealCounts,
        isDark: isDark,
      ),
    );
  }

  void _showPendingWarning(int count) {
    final isDark = _isDark.value;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Incomplete Selections',
                style: AppTypography.titleMedium.copyWith(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '$count ${count == 1 ? 'person has' : 'people have'} not selected '
          'a meal type. Please select a meal for everyone.',
          style: AppTypography.bodyMedium.copyWith(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK, Got It'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final party = widget.provider.myParty!;
    final event = widget.provider.event;
    final mealTypes = event?.mealTypes ?? [];
    final totalPresent = party.presentCount;

    final Map<String, int> mealCounts = {};
    for (final mt in mealTypes) {
      mealCounts[mt.id] = party.persons
          .where((p) => p.isPresent && p.selectedMealTypeId == mt.id)
          .length;
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _isDark,
      builder: (_, isDark, _) {
        return Scaffold(
          backgroundColor:
              isDark ? AppColors.backgroundDark : AppColors.background,
          body: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    // ── App bar ────────────────────────────────────────────
                    _GuestAppBar(
                      eventName: event?.name ?? 'Event',
                      presentCount: totalPresent,
                      totalCount: party.totalCount,
                      isDark: isDark,
                      confirmed: _confirmed,
                      themeNotifier: _isDark,
                      onExit: () => context.go(RouteNames.roleSelect),
                    ),

                    // ── Context banner ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppConstants.pagePaddingH,
                          12,
                          AppConstants.pagePaddingH,
                          0),
                      child: _confirmed
                          ? _ConfirmedBanner(isDark: isDark)
                          : _InstructionBanner(
                              isDark: isDark,
                              hasMealTypes: mealTypes.isNotEmpty),
                    ),

                    // ── Per-person list ────────────────────────────────────
                    Expanded(
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.pagePaddingH,
                          12,
                          AppConstants.pagePaddingH,
                          16,
                        ),
                        itemCount: party.persons.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final person = party.persons[index];
                          return _PersonCard(
                            key: ValueKey(person.id),
                            person: person,
                            isDark: isDark,
                            confirmed: _confirmed,
                            mealTypes: mealTypes,
                            onMealTypeChanged: (mealTypeId) =>
                                widget.provider.setEventMealType(
                                    person.id, mealTypeId),
                            onNameSaved: (name) =>
                                widget.provider.renamePerson(
                                    person.id, name),
                            onAttendanceToggled: () =>
                                widget.provider.toggleAttendance(
                                    person.id),
                          );
                        },
                      ),
                    ),

                    // ── Bottom summary + confirm ────────────────────────────
                    _BottomBar(
                      mealTypes: mealTypes,
                      mealCounts: mealCounts,
                      totalPresent: totalPresent,
                      confirmed: _confirmed,
                      isDark: isDark,
                      confirmCheckCtrl: _confirmCheckCtrl,
                      onConfirm: _confirmSelections,
                    ),
                  ],
                ),
              ),

              // ── Celebration confetti overlay ─────────────────────────────
              if (_confirmed)
                IgnorePointer(
                  child: _ConfettiOverlay(
                    controller: _celebrationCtrl,
                    particles: _particles,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Instruction banners ────────────────────────────────────────────────────────

class _InstructionBanner extends StatelessWidget {
  const _InstructionBanner(
      {required this.isDark, required this.hasMealTypes});
  final bool isDark;
  final bool hasMealTypes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.vacation.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
            color: AppColors.vacation.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant_menu_rounded,
              size: 15, color: AppColors.vacation),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasMealTypes
                  ? 'Select a meal type for each person. Tap Guest names to rename.'
                  : 'Tap Guest names to rename. Confirm attendance when ready.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmedBanner extends StatelessWidget {
  const _ConfirmedBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.present.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
            color: AppColors.present.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 15, color: AppColors.present),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'All set! Your meal selections are confirmed. Enjoy the event! 🎉',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Guest app bar ──────────────────────────────────────────────────────────────

class _GuestAppBar extends StatelessWidget {
  const _GuestAppBar({
    required this.eventName,
    required this.presentCount,
    required this.totalCount,
    required this.isDark,
    required this.confirmed,
    required this.themeNotifier,
    required this.onExit,
  });

  final String eventName;
  final int presentCount;
  final int totalCount;
  final bool isDark;
  final bool confirmed;
  final ValueNotifier<bool> themeNotifier;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Event icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.vacation, Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.celebration_rounded,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),

          // Event name + count
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: AppTypography.titleSmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.people_rounded,
                      size: 12,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$presentCount / $totalCount attending',
                      style: AppTypography.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (confirmed) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.lock_rounded,
                          size: 11, color: AppColors.present),
                      const SizedBox(width: 3),
                      Text(
                        'Confirmed',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.present,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Dark/light toggle
          GestureDetector(
            onTap: () => themeNotifier.value = !themeNotifier.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceVariantDark
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 16,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Exit
          GestureDetector(
            onTap: onExit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceVariantDark
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.logout_rounded,
                size: 16,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Person card ────────────────────────────────────────────────────────────────

class _PersonCard extends StatefulWidget {
  const _PersonCard({
    super.key,
    required this.person,
    required this.isDark,
    required this.confirmed,
    required this.mealTypes,
    required this.onMealTypeChanged,
    required this.onNameSaved,
    required this.onAttendanceToggled,
  });

  final GuestPerson person;
  final bool isDark;
  final bool confirmed;
  final List<EventMealType> mealTypes;
  final ValueChanged<String?> onMealTypeChanged;
  final ValueChanged<String> onNameSaved;
  final VoidCallback onAttendanceToggled;

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard>
    with SingleTickerProviderStateMixin {
  bool _isEditing = false;
  late final TextEditingController _nameCtrl;
  late final FocusNode _nameFocus;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.person.displayName);
    _nameFocus = FocusNode();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _isEditing) _saveName();
    });
  }

  @override
  void didUpdateWidget(_PersonCard old) {
    super.didUpdateWidget(old);
    if (widget.person.displayName != old.person.displayName && !_isEditing) {
      _nameCtrl.text = widget.person.displayName;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _saveName() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _nameCtrl.text = widget.person.displayName;
    } else if (name != widget.person.displayName) {
      widget.onNameSaved(name);
    }
    setState(() => _isEditing = false);
    _nameFocus.unfocus();
  }

  EventMealType? get _selectedMealType {
    final id = widget.person.selectedMealTypeId;
    if (id == null) return null;
    try {
      return widget.mealTypes.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Color get _borderColor {
    final person = widget.person;
    final isDark = widget.isDark;
    if (!person.isPresent) {
      return isDark
          ? AppColors.borderDark.withValues(alpha: 0.3)
          : AppColors.border.withValues(alpha: 0.4);
    }
    final sel = _selectedMealType;
    if (sel != null) return sel.color.withValues(alpha: 0.40);
    if (widget.mealTypes.isNotEmpty) {
      return AppColors.warning.withValues(alpha: 0.45);
    }
    return isDark
        ? AppColors.borderDark.withValues(alpha: 0.5)
        : AppColors.border;
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final isDark = widget.isDark;
    final isAbsent = !person.isPresent;
    final selectedMeal = _selectedMealType;

    return FadeTransition(
      opacity: _fade,
      child: Opacity(
        opacity: isAbsent ? 0.55 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: _borderColor, width: 1.2),
            boxShadow: selectedMeal != null && !widget.confirmed
                ? [
                    BoxShadow(
                      color: selectedMeal.color.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Name row ─────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PersonAvatar(
                    name: person.displayName,
                    isDark: isDark,
                    isPrimary: person.isPrimary,
                    isAdult: person.isAdult,
                    mealColor: selectedMeal?.color,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _isEditing
                            ? _NameEditField(
                                controller: _nameCtrl,
                                focusNode: _nameFocus,
                                isDark: isDark,
                                onSubmitted: (_) => _saveName(),
                              )
                            : GestureDetector(
                                onTap: (!widget.confirmed && !person.isPrimary)
                                    ? () => setState(() {
                                          _isEditing = true;
                                          _nameCtrl.text =
                                              person.displayName;
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            _nameFocus.requestFocus();
                                          });
                                        })
                                    : null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        person.displayName,
                                        style: AppTypography.bodyMedium
                                            .copyWith(
                                          color: isDark
                                              ? AppColors.textPrimaryDark
                                              : AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!widget.confirmed &&
                                        !person.isPrimary) ...[
                                      const SizedBox(width: 5),
                                      Icon(Icons.edit_rounded,
                                          size: 12,
                                          color: isDark
                                              ? AppColors.textTertiaryDark
                                              : AppColors.textTertiary),
                                    ],
                                  ],
                                ),
                              ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _TagChip(
                              label: person.ageLabel,
                              color: person.isAdult
                                  ? AppColors.primary
                                  : AppColors.vacation,
                              isDark: isDark,
                            ),
                            if (person.isPrimary)
                              _TagChip(
                                  label: 'You',
                                  color: AppColors.present,
                                  isDark: isDark),
                            if (selectedMeal != null)
                              _TagChip(
                                label:
                                    '${selectedMeal.emoji} ${selectedMeal.title}',
                                color: selectedMeal.color,
                                isDark: isDark,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!person.isPrimary && !widget.confirmed)
                    _AbsentToggle(
                      isAbsent: isAbsent,
                      isDark: isDark,
                      onToggle: widget.onAttendanceToggled,
                    ),
                ],
              ),

              // ── Meal type selector ────────────────────────────────────────
              if (!isAbsent && widget.mealTypes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _EventMealTypeSelector(
                  mealTypes: widget.mealTypes,
                  selectedMealTypeId: person.selectedMealTypeId,
                  isDark: isDark,
                  confirmed: widget.confirmed,
                  onChanged: widget.onMealTypeChanged,
                ),
              ] else if (isAbsent) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.do_not_disturb_rounded,
                        size: 13,
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      'Absent — no meal required',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Event meal type selector ───────────────────────────────────────────────────

/// Dynamic meal type chips with haptic + scale-pop micro-animation on selection.
class _EventMealTypeSelector extends StatefulWidget {
  const _EventMealTypeSelector({
    required this.mealTypes,
    required this.selectedMealTypeId,
    required this.isDark,
    required this.confirmed,
    required this.onChanged,
  });

  final List<EventMealType> mealTypes;
  final String? selectedMealTypeId;
  final bool isDark;
  final bool confirmed;
  final ValueChanged<String?> onChanged;

  @override
  State<_EventMealTypeSelector> createState() =>
      _EventMealTypeSelectorState();
}

class _EventMealTypeSelectorState extends State<_EventMealTypeSelector>
    with TickerProviderStateMixin {
  final Map<String, AnimationController> _pulseCtls = {};

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_EventMealTypeSelector old) {
    super.didUpdateWidget(old);
    if (old.mealTypes.length != widget.mealTypes.length) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    for (final m in widget.mealTypes) {
      _pulseCtls[m.id] = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        reverseDuration: const Duration(milliseconds: 280),
      );
    }
  }

  void _disposeControllers() {
    for (final ctrl in _pulseCtls.values) {
      ctrl.dispose();
    }
    _pulseCtls.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _onTap(EventMealType m) {
    if (widget.confirmed) return;
    HapticFeedback.lightImpact();
    widget.onChanged(m.id);
    final ctrl = _pulseCtls[m.id];
    if (ctrl != null) {
      ctrl.forward().then((_) => ctrl.reverse());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.mealTypes.map((m) {
        final isSelected = m.id == widget.selectedMealTypeId;
        final ctrl = _pulseCtls[m.id];

        return GestureDetector(
          onTap: () => _onTap(m),
          child: ctrl != null
              ? AnimatedBuilder(
                  animation: ctrl,
                  builder: (_, child) => Transform.scale(
                    scale: 1.0 + ctrl.value * 0.07,
                    child: child,
                  ),
                  child: _MealChip(
                    mealType: m,
                    isSelected: isSelected,
                    isDark: widget.isDark,
                  ),
                )
              : _MealChip(
                  mealType: m,
                  isSelected: isSelected,
                  isDark: widget.isDark,
                ),
        );
      }).toList(),
    );
  }
}

/// Individual meal chip — pure display, no gesture handling.
class _MealChip extends StatelessWidget {
  const _MealChip({
    required this.mealType,
    required this.isSelected,
    required this.isDark,
  });

  final EventMealType mealType;
  final bool isSelected;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final m = mealType;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isSelected
            ? m.color.withValues(alpha: isDark ? 0.24 : 0.14)
            : (isDark
                ? AppColors.surfaceVariantDark
                : AppColors.surfaceVariant),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? m.color.withValues(alpha: 0.60)
              : (isDark
                  ? AppColors.borderDark.withValues(alpha: 0.4)
                  : AppColors.border),
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: m.color.withValues(alpha: 0.20),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(fontSize: isSelected ? 18 : 15),
            child: Text(m.emoji),
          ),
          const SizedBox(width: 6),
          Text(
            m.title,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected
                  ? m.color
                  : (isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 5),
            Icon(Icons.check_circle_rounded, size: 13, color: m.color),
          ],
        ],
      ),
    );
  }
}

// ── Person avatar ──────────────────────────────────────────────────────────────

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.name,
    required this.isDark,
    required this.isPrimary,
    required this.isAdult,
    this.mealColor,
  });

  final String name;
  final bool isDark;
  final bool isPrimary;
  final bool isAdult;
  final Color? mealColor;

  @override
  Widget build(BuildContext context) {
    final baseColor = mealColor ??
        (isPrimary
            ? AppColors.vacation
            : isAdult
                ? AppColors.primary
                : const Color(0xFFEC4899));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: isDark ? 0.20 : 0.12),
        shape: BoxShape.circle,
        border: Border.all(
            color: baseColor.withValues(alpha: 0.40), width: 1.5),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: AppTypography.bodyLarge.copyWith(
            color: baseColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Name edit field ────────────────────────────────────────────────────────────

class _NameEditField extends StatelessWidget {
  const _NameEditField({
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppColors.vacation.withValues(alpha: 0.45), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: onSubmitted,
        style: AppTypography.bodyMedium.copyWith(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: InputBorder.none,
          hintText: 'Enter name…',
          hintStyle: AppTypography.bodySmall.copyWith(
            color: isDark
                ? AppColors.textTertiaryDark
                : AppColors.textTertiary,
          ),
          suffixIcon: GestureDetector(
            onTap: () => onSubmitted(controller.text),
            child: const Icon(Icons.check_rounded,
                size: 16, color: AppColors.present),
          ),
        ),
      ),
    );
  }
}

// ── Absent toggle ──────────────────────────────────────────────────────────────

class _AbsentToggle extends StatelessWidget {
  const _AbsentToggle({
    required this.isAbsent,
    required this.isDark,
    required this.onToggle,
  });

  final bool isAbsent;
  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isAbsent ? 'Mark as present' : 'Mark as absent',
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isAbsent
                ? AppColors.error.withValues(alpha: isDark ? 0.18 : 0.10)
                : (isDark
                    ? AppColors.surfaceVariantDark
                    : AppColors.surfaceVariant),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isAbsent
                  ? AppColors.error.withValues(alpha: 0.35)
                  : (isDark
                      ? AppColors.borderDark.withValues(alpha: 0.35)
                      : AppColors.border),
            ),
          ),
          child: Icon(
            isAbsent ? Icons.person_off_rounded : Icons.person_rounded,
            size: 16,
            color: isAbsent
                ? AppColors.error
                : (isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary),
          ),
        ),
      ),
    );
  }
}

// ── Tag chip ───────────────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.color,
    required this.isDark,
  });

  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.30 : 0.22)),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ── Bottom bar ─────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.mealTypes,
    required this.mealCounts,
    required this.totalPresent,
    required this.confirmed,
    required this.isDark,
    required this.confirmCheckCtrl,
    required this.onConfirm,
  });

  final List<EventMealType> mealTypes;
  final Map<String, int> mealCounts;
  final int totalPresent;
  final bool confirmed;
  final bool isDark;
  final AnimationController confirmCheckCtrl;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(AppConstants.pagePaddingH, 14,
          AppConstants.pagePaddingH, 14 + bottomPad),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Meal counts ────────────────────────────────────────────────
          if (mealTypes.isNotEmpty) ...[
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: mealTypes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final mt = mealTypes[i];
                  final count = mealCounts[mt.id] ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: mt.color
                          .withValues(alpha: isDark ? 0.15 : 0.09),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: mt.color.withValues(alpha: 0.30)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(mt.emoji,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          '$count',
                          style: AppTypography.titleSmall.copyWith(
                            color: mt.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          mt.title,
                          style: AppTypography.labelSmall.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_rounded,
                    size: 16,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '$totalPresent attending',
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── Confirm / Confirmed button ────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: confirmed
                  ? _ConfirmedButton(
                      key: const ValueKey('confirmed'), isDark: isDark)
                  : _ConfirmButton(
                      key: const ValueKey('confirm'), onTap: onConfirm),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confirm / confirmed buttons ────────────────────────────────────────────────

class _ConfirmButton extends StatefulWidget {
  const _ConfirmButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<_ConfirmButton>
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
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
      builder: (_, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.vacation, Color(0xFFEC4899)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.vacation.withValues(alpha: 0.30),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Confirm Selections',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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

class _ConfirmedButton extends StatelessWidget {
  const _ConfirmedButton({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.present.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.present.withValues(alpha: 0.30)),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded,
                size: 16, color: AppColors.present),
            const SizedBox(width: 8),
            Text(
              'Selections Confirmed  🎉',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.present,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confetti animation ─────────────────────────────────────────────────────────

class _ConfettiParticle {
  const _ConfettiParticle({
    required this.x,
    required this.delay,
    required this.color,
    required this.size,
    required this.rotationSpeed,
    required this.horizontalDrift,
  });

  final double x;
  final double delay;
  final Color color;
  final double size;
  final double rotationSpeed;
  final double horizontalDrift;
}

class _ConfettiOverlay extends StatelessWidget {
  const _ConfettiOverlay({
    required this.controller,
    required this.particles,
  });

  final AnimationController controller;
  final List<_ConfettiParticle> particles;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            progress: controller.value,
            particles: particles,
          ),
        );
      },
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({
    required this.progress,
    required this.particles,
  });

  final double progress;
  final List<_ConfettiParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    // Use an indexed loop to avoid O(n²) particles.indexOf() on each frame.
    for (var idx = 0; idx < particles.length; idx++) {
      final p = particles[idx];
      final localProgress =
          ((progress - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
      if (localProgress <= 0) continue;

      final opacity = localProgress < 0.7
          ? 1.0
          : 1.0 - ((localProgress - 0.7) / 0.3);

      final x = (p.x + p.horizontalDrift * localProgress) * size.width;
      final y = -40 + (size.height + 80) * localProgress;
      final rotation = p.rotationSpeed * localProgress * math.pi * 2;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      if (idx.isEven) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero,
                width: p.size,
                height: p.size * 0.55),
            const Radius.circular(2),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

// ── Celebration modal ──────────────────────────────────────────────────────────

/// Premium animated celebration card shown after the guest confirms all
/// meal selections. Auto-dismisses after 4 seconds; tap to close early.
class _CelebrationModal extends StatefulWidget {
  const _CelebrationModal({
    required this.eventName,
    required this.party,
    required this.mealTypes,
    required this.mealCounts,
    required this.isDark,
  });

  final String eventName;
  final EventGuestParty? party;
  final List<EventMealType> mealTypes;
  final Map<String, int> mealCounts;
  final bool isDark;

  @override
  State<_CelebrationModal> createState() => _CelebrationModalState();
}

class _CelebrationModalState extends State<_CelebrationModal>
    with TickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final AnimationController _slideCtrl;
  late final AnimationController _autoCloseCtrl;
  late final Animation<double> _glowAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();

    _autoCloseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..forward();

    _glowAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic),
    );

    _autoCloseCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.pop(context);
      }
    });

    Future.microtask(() => HapticFeedback.heavyImpact());
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _slideCtrl.dispose();
    _autoCloseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surface;
    final party = widget.party;

    return Center(
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        behavior: HitTestBehavior.opaque,
        child: Material(
          color: Colors.transparent,
          child: SlideTransition(
            position: _slideAnim,
            child: FadeTransition(
              opacity: _slideCtrl,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.vacation.withValues(alpha: 0.30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.vacation.withValues(alpha: 0.22),
                      blurRadius: 40,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.5)
                          : Colors.black.withValues(alpha: 0.12),
                      blurRadius: 60,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Pulsing glow icon ──────────────────────────────
                      AnimatedBuilder(
                        animation: _glowAnim,
                        builder: (_, child) => Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.vacation.withValues(
                                    alpha: 0.40 * _glowAnim.value),
                                blurRadius: 28 * _glowAnim.value,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: child,
                        ),
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.vacation,
                                Color(0xFFEC4899),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text('🎉',
                                style: TextStyle(fontSize: 38)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Headline ───────────────────────────────────────
                      Text(
                        'You\'re all set!',
                        style: AppTypography.titleLarge.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Meals confirmed for ${widget.eventName}',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 20),

                      // ── Meal summary chips ─────────────────────────────
                      if (widget.mealTypes.isNotEmpty &&
                          widget.mealCounts.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: widget.mealTypes
                              .where((mt) =>
                                  (widget.mealCounts[mt.id] ?? 0) > 0)
                              .map((mt) {
                            final count = widget.mealCounts[mt.id] ?? 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: mt.color.withValues(
                                    alpha: isDark ? 0.20 : 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: mt.color
                                        .withValues(alpha: 0.40)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(mt.emoji,
                                      style: const TextStyle(fontSize: 14)),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$count × ${mt.title}',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: mt.color,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Attending count ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.present
                              .withValues(alpha: isDark ? 0.12 : 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.present
                                  .withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_rounded,
                                size: 16, color: AppColors.present),
                            const SizedBox(width: 8),
                            Text(
                              '${party?.presentCount ?? 0} attending',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.present,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Auto-close progress ────────────────────────────
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: AnimatedBuilder(
                          animation: _autoCloseCtrl,
                          builder: (_, _) => LinearProgressIndicator(
                            value: 1.0 - _autoCloseCtrl.value,
                            backgroundColor: isDark
                                ? AppColors.borderDark
                                : AppColors.border,
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(
                                    AppColors.vacation),
                            minHeight: 3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap anywhere to close',
                        style: AppTypography.labelSmall.copyWith(
                          color: isDark
                              ? AppColors.textTertiaryDark
                              : AppColors.textTertiary,
                          fontSize: 10,
                        ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
