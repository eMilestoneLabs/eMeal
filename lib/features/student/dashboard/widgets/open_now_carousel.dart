import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/features/student/dashboard/widgets/next_meal_card.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

/// Feature 3 — "Open Now" carousel.
///
/// Horizontal pager over the priority-ordered [meals] (the provider orders
/// pending-open first, then marked-open, then a single upcoming fallback).
///
/// Behaviour (spec):
///  • Auto-scrolls through the cards when every open meal is already marked.
///  • PAUSES auto-scroll and parks on the first pending (unmarked) open meal —
///    [pendingIndex] — to force attention to the action the student still owes.
///  • Manual left / right arrows always work and pause auto-scroll on tap.
///
/// Reuses [NextMealCard] for each page so the visuals stay identical to the
/// original single hero card — this is purely additive.
class OpenNowCarousel extends StatefulWidget {
  const OpenNowCarousel({
    super.key,
    required this.meals,
    required this.pendingIndex,
    required this.statusOf,
    required this.isWindowOpen,
    required this.isWindowPast,
    required this.onMarkPresent,
    required this.onSkip,
    required this.onMarkAttendance,
    this.onTapMeal,
  });

  final List<MealModel> meals;

  /// Index of the first pending (unmarked) open meal, or -1 when all are marked.
  final int pendingIndex;

  final AttendanceStatus? Function(MealModel meal) statusOf;
  final bool Function(MealModel meal) isWindowOpen;
  final bool Function(MealModel meal) isWindowPast;
  final void Function(MealModel meal) onMarkPresent;
  final void Function(MealModel meal) onSkip;
  final void Function(MealModel meal) onMarkAttendance;

  /// Issue 3: tap a card to open that meal's detail screen.
  final void Function(MealModel meal)? onTapMeal;

  @override
  State<OpenNowCarousel> createState() => _OpenNowCarouselState();
}

class _OpenNowCarouselState extends State<OpenNowCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _page = 0;

  bool get _hasPending => widget.pendingIndex >= 0;

  @override
  void initState() {
    super.initState();
    _page = _hasPending ? widget.pendingIndex : 0;
    _controller = PageController(initialPage: _page);
    _maybeStartAutoScroll();
  }

  @override
  void didUpdateWidget(covariant OpenNowCarousel old) {
    super.didUpdateWidget(old);
    // Re-evaluate when the list or pending state changes (e.g. the student
    // just marked the pending meal, so auto-scroll may now resume).
    if (old.meals.length != widget.meals.length ||
        old.pendingIndex != widget.pendingIndex) {
      _clampPage();
      _maybeStartAutoScroll();
    }
  }

  void _clampPage() {
    if (_page >= widget.meals.length) {
      _page = widget.meals.isEmpty ? 0 : widget.meals.length - 1;
      if (_controller.hasClients) _controller.jumpToPage(_page);
    }
  }

  void _maybeStartAutoScroll() {
    _timer?.cancel();
    // Park on pending (force attention) or skip when there is nothing to cycle.
    if (_hasPending || widget.meals.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.meals.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseAutoScroll() => _timer?.cancel();

  void _go(int delta) {
    _pauseAutoScroll();
    final next = (_page + delta).clamp(0, widget.meals.length - 1);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Issue 3: size the pager to the tallest card the current meals need, so a
  /// fully-marked day shows a short card instead of the old fixed 208px block.
  double _cardHeight() {
    var anyButtons = false;
    var anyMenu = false;
    for (final m in widget.meals) {
      final st = widget.statusOf(m);
      final marked = st != null && st != AttendanceStatus.pending;
      if (!marked && widget.isWindowOpen(m)) anyButtons = true;
      if (m.menuItems.any((e) => e.trim().isNotEmpty)) anyMenu = true;
    }
    var h = 120.0; // icon row + chip + name + window + padding
    if (anyMenu) h += 28;
    if (anyButtons) h += 54;
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final meals = widget.meals;
    if (meals.isEmpty) return const SizedBox.shrink();
    final showArrows = meals.length > 1;

    return Column(
      children: [
        SizedBox(
          height: _cardHeight(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: meals.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final meal = meals[i];
                  return Align(
                    alignment: Alignment.topCenter,
                    child: NextMealCard(
                      meal: meal,
                      status: widget.statusOf(meal),
                      isWindowOpen: widget.isWindowOpen(meal),
                      isWindowPast: widget.isWindowPast(meal),
                      onMarkPresent: () => widget.onMarkPresent(meal),
                      onSkip: () => widget.onSkip(meal),
                      onMarkAttendance: () => widget.onMarkAttendance(meal),
                      onTap: widget.onTapMeal == null
                          ? null
                          : () => widget.onTapMeal!(meal),
                    ),
                  );
                },
              ),
              // Arrows sit flush INSIDE the card column (was -4, which let them
              // overhang the 20px margin and made the carousel read as wider
              // than the hero card above). Now nothing bleeds past the column.
              if (showArrows && _page > 0)
                Positioned(
                  left: 0,
                  child: _Arrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _go(-1),
                  ),
                ),
              if (showArrows && _page < meals.length - 1)
                Positioned(
                  right: 0,
                  child: _Arrow(
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _go(1),
                  ),
                ),
            ],
          ),
        ),
        if (showArrows) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(meals.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.secondary
                      : AppColors.secondary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: (isDark ? AppColors.surfaceDark : AppColors.surface)
          .withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 22, color: AppColors.secondary),
        ),
      ),
    );
  }
}
