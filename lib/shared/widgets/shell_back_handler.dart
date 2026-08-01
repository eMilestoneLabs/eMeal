import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';

/// Whether [location] is a shell's HOME tab, for [ShellBackHandler.isHome].
///
/// Live-Test-16 ISSUE-2 — this MUST be derived from the router location and
/// compared EXACTLY. Both shells' `_indexFromLocation` fall through to
/// `return 0` for any path that is not a tab, so `/student/settings` and
/// `/student/billing` report bottom-nav index 0; a back policy keyed off that
/// index would read "we are on Home" on those screens and close the app —
/// precisely the bug being fixed. A `startsWith` test would be wrong for the
/// same reason (it would swallow any future `/…/dashboard/<sub>` route).
///
/// The query string is stripped: a deep-link may legitimately carry intents
/// (e.g. `?open=corrections`) and must still resolve to its own route.
bool isShellHomeLocation(String location, String homeRoute) =>
    location.split('?').first == homeRoute;

/// Live-Test-16 ISSUE-2 — the app's single Android back policy for the role
/// shells (student + admin).
///
/// ## The problem this exists to solve
///
/// Both shells switch tabs with `context.go(...)`, which REPLACES the shell's
/// page instead of pushing one. A tab route is therefore always a one-page
/// navigator. On Android back, `GoRouterDelegate.popRoute()` asks
/// `_findCurrentNavigator()` for a navigator to pop; because the shell
/// navigator cannot pop it falls back to the ROOT navigator, whose `maybePop`
/// finds nothing and returns `false` — and the framework answers a `false`
/// with `SystemNavigator.pop()`. The app closed instead of going back.
///
/// ## Why a [PopScope] here is the whole fix
///
/// `_findCurrentNavigator()` descends INTO the shell navigator whenever that
/// navigator `canPop()`. So this handler is consulted **only** when there is
/// genuinely nothing left to pop — every pushed screen keeps popping normally
/// and never reaches this code. A modal sheet or dialog is likewise unaffected:
/// it makes the shell's route non-current, which stops the descent at the root
/// navigator, so the sheet pops first (this is what keeps the correction
/// sheet's and notepad's own [PopScope]s working).
///
/// `canPop: false` makes the route report `doNotPop`, which `maybePop` answers
/// with `true` — so `popRoute()` returns `true` and the framework does NOT
/// fire `SystemNavigator.pop()`. Exiting therefore becomes an explicit,
/// deliberate act of this widget rather than a silent framework default.
///
/// ## Behaviour
///
/// * Not on the home tab → go to home, via the shell's OWN tab handler.
/// * On the home tab → first back shows a hint, a second back inside
///   [AppConstants.backExitConfirmWindow] exits.
///
/// Zero cost: no timer, no listener, no polling, no rebuild — [canPop] is a
/// constant and the state read happens lazily inside the callback.
class ShellBackHandler extends StatefulWidget {
  const ShellBackHandler({
    super.key,
    required this.isHome,
    required this.onGoHome,
    required this.child,
  });

  /// Whether the shell is currently showing its HOME tab.
  ///
  /// Deliberately a callback, evaluated at back-press time: it must be derived
  /// from the current LOCATION, never from the bottom-nav index. Both shells'
  /// `_indexFromLocation` fall through to `return 0` for any path that is not
  /// a tab (`/student/settings`, `/student/billing`, …), so an index-based
  /// test would read "we are on Home" on those screens and exit the app —
  /// the exact bug this class exists to fix.
  final bool Function() isHome;

  /// Navigates to the shell's home tab.
  ///
  /// MUST delegate to the shell's own tab-tap handler so that back-to-Home is
  /// identical to tap-to-Home. The student shell's handler also refreshes the
  /// dashboard on index 0 (so an attendance mark made on another tab shows up
  /// immediately); bypassing it with a bare `context.go` would have made back
  /// land on a stale Home.
  final VoidCallback onGoHome;

  final Widget child;

  @override
  State<ShellBackHandler> createState() => _ShellBackHandlerState();
}

class _ShellBackHandlerState extends State<ShellBackHandler> {
  static const _exitHint = 'Press back again to exit';

  /// Frame timestamp of the last unconfirmed back press on the home tab.
  ///
  /// Deliberately the engine's MONOTONIC frame clock, not `DateTime.now()`:
  /// the device wall clock is untrusted (Guidebook §8) and can step backwards
  /// on an NTP correction or a manual timezone change, which would make
  /// `now.difference(last)` negative — i.e. inside the window — and exit the
  /// app on a SINGLE back press. A monotonic source cannot go backwards.
  /// It is also deliberately NOT a Timer: nothing to schedule, nothing to
  /// cancel, nothing to dispose.
  ///
  /// INVARIANT — the hint SnackBar's duration MUST stay bound to
  /// [AppConstants.backExitConfirmWindow] (see [_handleBack]). The frame clock
  /// only advances while frames are produced; the visible SnackBar is what
  /// guarantees frames span the whole confirm window. Shortening the SnackBar
  /// below the window would let the clock freeze mid-window and under-report
  /// elapsed time, permitting an exit that should have been a fresh hint.
  Duration? _lastBackAt;

  void _handleBack() {
    if (!mounted) return;

    if (!widget.isHome()) {
      // Leaving a non-home destination: drop any pending exit confirmation so
      // a stale timestamp cannot turn the next home back-press into an
      // immediate exit.
      _lastBackAt = null;
      widget.onGoHome();
      return;
    }

    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final last = _lastBackAt;
    if (last != null && now - last <= AppConstants.backExitConfirmWindow) {
      SystemNavigator.pop();
      return;
    }

    _lastBackAt = now;
    // `maybeOf`, not `of`: `of` THROWS when no messenger is in scope. A back
    // press is a platform callback that can land at any moment, including
    // while the tree is being swapped (logout, role switch). A missing
    // messenger must cost the user a hint, never a crash — the confirmation
    // itself is already armed above, so a second back still exits correctly.
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(_exitHint),
          // Bound to the confirm window on purpose — see the INVARIANT on
          // [_lastBackAt]. Do not shorten this independently.
          duration: AppConstants.backExitConfirmWindow,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: widget.child,
    );
  }
}
