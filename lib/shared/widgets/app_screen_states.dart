import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';

/// Pass 13 (SRS Module 28) — the canonical screen-state kit.
///
/// Every data screen implements five states (ES-001 / FR-UI-021):
/// Loading, Skeleton, Empty, Error(retry), Offline. This file provides the
/// shared pieces so screens stay consistent:
///
///   • [EmptyCopy] — the canonical empty-state strings (ES-002);
///   • [AppErrorState] — actionable message + retry that PRESERVES the
///     caller's filters/input (ES-003, ERR-007); auto-detects offline
///     failures and renders the Offline variant (connection errors);
///   • [AppSkeletonList] — layout-stable placeholder rows (ES-004);
///   • [FreshnessBadge] — "Updated X ago" chip for stale-while-revalidate
///     screens (FR-OFF-006), shown only once data is meaningfully stale.

/// ES-002 — canonical empty copy. Screens must use these strings (not ad-hoc
/// variants) so the same situation always reads the same everywhere.
abstract final class EmptyCopy {
  static const noGroups = 'No groups yet.';
  static const noMembers = 'No members found.';
  static const noMeals = 'No meals configured.';
  static const noWeeklyMenu = 'Weekly menu is not available.';
  static const noAttendance = 'No attendance records found.';
  static const noNotices = 'No notices yet.';
  static const noEvents = 'No events yet.';
  static const noGuests = 'No guests booked.';
  static const noExportHistory = 'No exports yet.';
  static const noBillingData = 'No billing data for this range.';
  static const noVacationRequests = 'No vacation requests yet.';
  static const noAdjustments = 'No adjustments yet.';
}

/// ES-003 / ERR-007 — error state with a retry affordance. The [onRetry]
/// callback re-runs the load with the screen's CURRENT filters/input (the
/// screen keeps its state; this widget never resets anything).
///
/// Pass a [failure] and the widget auto-renders the Offline variant for
/// connection-level failures (a [NetworkFailure] without an HTTP status).
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.failure,
    this.message,
    this.onRetry,
    this.compact = false,
  });

  final Failure? failure;
  final String? message;
  final VoidCallback? onRetry;
  final bool compact;

  bool get _isOffline =>
      failure is NetworkFailure && (failure as NetworkFailure).statusCode == null;

  @override
  Widget build(BuildContext context) {
    final offline = _isOffline;
    return AppEmptyState(
      compact: compact,
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      iconColor: offline ? AppColors.textTertiary : AppColors.error,
      title: offline ? 'You\'re offline' : 'Something went wrong',
      subtitle: offline
          ? 'Check your connection — we\'ll pick up right where you left off.'
          : (message ?? failure?.message ?? 'Please try again.'),
      action: onRetry == null
          ? null
          : FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
    );
  }
}

/// FR-OFF-012 — scoped, inline error for ONE failed widget/section while the
/// rest of the screen renders normally (partial data beats a blank screen).
class AppSectionError extends StatelessWidget {
  const AppSectionError({
    super.key,
    required this.label,
    this.onRetry,
  });

  final String label;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.error)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// ES-004 — layout-stable skeleton rows: same heights/radii as the real list
/// tiles so content never jumps when data lands.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({
    super.key,
    this.rows = 4,
    this.rowHeight = 72,
    this.spacing = 10,
  });

  final int rows;
  final double rowHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant;
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          _PulseBox(height: rowHeight, color: base),
          if (i != rows - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}

class _PulseBox extends StatefulWidget {
  const _PulseBox({required this.height, required this.color});
  final double height;
  final Color color;

  @override
  State<_PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<_PulseBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
    upperBound: 1.0,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// FR-OFF-006 — "Updated X ago" chip for cache-first screens. Renders nothing
/// while data is fresh (younger than [staleAfter]) so the UI stays clean; the
/// badge only appears when the user should know they're looking at old data.
class FreshnessBadge extends StatelessWidget {
  const FreshnessBadge({
    super.key,
    required this.lastUpdated,
    this.staleAfter = const Duration(minutes: 5),
  });

  final DateTime? lastUpdated;
  final Duration staleAfter;

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final ts = lastUpdated;
    if (ts == null) return const SizedBox.shrink();
    final age = DateTime.now().difference(ts);
    if (age < staleAfter) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_rounded,
              size: 12, color: AppColors.warning),
          const SizedBox(width: 4),
          Text(
            'Updated ${_ago(age)}',
            style: AppTypography.labelSmall
                .copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
