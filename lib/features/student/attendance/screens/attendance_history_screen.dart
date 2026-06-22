import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Student attendance history — premium timeline with monthly summary + streak.
///
/// Layout:
/// ```
/// ─── Summary card (present rate + streak + stat pills) ───
/// ─── Timeline list (color-coded tiles, paginated) ────────
/// ```
class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final _repo = AttendanceRepository();
  final _scrollController = ScrollController();

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _initialized = false;
  String? _error;
  List<AttendanceModel> _records = [];
  int _currentPage = 1;
  bool _hasMore = true;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guard prevents reload on every InheritedWidget change (e.g., auth state
    // updates from vacation toggle in settings while this screen is visible).
    if (_initialized) return;
    _initialized = true;
    _loadHistory(reset: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _records = [];
        _hasMore = true;
        _error = null;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    final groupId = user?.effectiveGroupIds.firstOrNull;
    if (user == null || groupId == null) return;

    final result = await _repo.getAttendanceHistory(
      userId: user.id,
      groupId: groupId,
      organizationId: user.organizationId,
      from: _startDate,
      to: _endDate,
      params: PaginationParams(page: _currentPage),
    );

    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        setState(() {
          _records = reset ? value.data : [..._records, ...value.data];
          _hasMore = value.hasMore;
          _currentPage++;
          _isLoading = false;
          _isLoadingMore = false;
        });
      case Err(:final failure):
        setState(() {
          _error = failure.message;
          _isLoading = false;
          _isLoadingMore = false;
        });
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
              ),
        ),
        child: child!,
      ),
    );
    if (range != null && mounted) {
      setState(() {
        _startDate = range.start;
        _endDate = range.end;
      });
      await _loadHistory(reset: true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Derived stats ────────────────────────────────────────────────────────────

  int get _presentCount =>
      _records.where((r) => r.status == AttendanceStatus.present).length;
  int get _absentCount =>
      _records.where((r) => r.status == AttendanceStatus.absent).length;
  int get _skippedCount =>
      _records.where((r) => r.status == AttendanceStatus.skipped).length;

  double get _attendanceRate {
    final total = _presentCount + _absentCount + _skippedCount;
    if (total == 0) return 0;
    return _presentCount / total;
  }

  int get _currentStreak {
    if (_records.isEmpty) return 0;
    final sorted = [..._records]
      ..sort((a, b) => b.date.compareTo(a.date));

    int streak = 0;
    DateTime? lastDate;
    for (final r in sorted) {
      if (r.status != AttendanceStatus.present) break;
      if (lastDate != null) {
        final diff = lastDate.difference(r.date).inDays;
        if (diff > 1) break;
      }
      streak++;
      lastDate = r.date;
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: _HistoryAppBar(
        isDark: isDark,
        startDate: _startDate,
        endDate: _endDate,
        onDateRange: _pickDateRange,
      ),
      body: _isLoading
          ? const _LoadingView()
          : _error != null
              ? _ErrorView(
                  message: _error!,
                  isDark: isDark,
                  onRetry: () => _loadHistory(reset: true),
                )
              : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // ── Summary card ─────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.space16,
                          AppConstants.space16,
                          AppConstants.space16,
                          0,
                        ),
                        child: _SummaryCard(
                          presentCount: _presentCount,
                          absentCount: _absentCount,
                          skippedCount: _skippedCount,
                          attendanceRate: _attendanceRate,
                          streak: _currentStreak,
                          isDark: isDark,
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppConstants.space20),
                    ),

                    // ── Records header ────────────────────────────────────
                    if (_records.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.space16,
                          ),
                          child: Text(
                            'Records',
                            style: AppTypography.titleSmall.copyWith(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),

                    if (_records.isNotEmpty)
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppConstants.space12),
                      ),

                    // ── Record list ───────────────────────────────────────
                    if (_records.isEmpty && !_isLoading)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyView(isDark: isDark),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.space16,
                        ),
                        sliver: SliverList.separated(
                          itemCount:
                              _records.length + (_isLoadingMore ? 1 : 0),
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppConstants.space8),
                          itemBuilder: (context, i) {
                            if (i == _records.length) {
                              return const Padding(
                                padding:
                                    EdgeInsets.all(AppConstants.space16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                            return _HistoryTile(
                              record: _records[i],
                              isDark: isDark,
                            );
                          },
                        ),
                      ),

                    // ── End-of-list indicator ─────────────────────────────
                    if (!_hasMore && _records.isNotEmpty && !_isLoadingMore)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppConstants.space20,
                            horizontal: AppConstants.space16,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: isDark
                                      ? AppColors.borderDark.withValues(alpha: 0.4)
                                      : AppColors.border.withValues(alpha: 0.5),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppConstants.space12),
                                child: Text(
                                  'All records loaded',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textTertiary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: isDark
                                      ? AppColors.borderDark.withValues(alpha: 0.4)
                                      : AppColors.border.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppConstants.space40),
                    ),
                  ],
                ),
    );
  }
}

// ── App bar ────────────────────────────────────────────────────────────────────

class _HistoryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HistoryAppBar({
    required this.isDark,
    required this.startDate,
    required this.endDate,
    required this.onDateRange,
  });

  final bool isDark;
  final DateTime startDate;
  final DateTime endDate;
  final VoidCallback onDateRange;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Text(
        'Attendance History',
        style: AppTypography.titleLarge.copyWith(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        GestureDetector(
          onTap: onDateRange,
          child: Container(
            margin: const EdgeInsets.only(right: AppConstants.space16),
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.date_range_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_fmt(startDate)} – ${_fmt(endDate)}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

// ── Summary card ───────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.presentCount,
    required this.absentCount,
    required this.skippedCount,
    required this.attendanceRate,
    required this.streak,
    required this.isDark,
  });

  final int presentCount;
  final int absentCount;
  final int skippedCount;
  final double attendanceRate;
  final int streak;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final pct = (attendanceRate * 100).toStringAsFixed(0);
    final rateColor = attendanceRate >= 0.80
        ? AppColors.present
        : attendanceRate >= 0.60
            ? AppColors.skipped
            : AppColors.absent;

    return Container(
      padding: const EdgeInsets.all(AppConstants.space20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.surfaceDark,
                  AppColors.surfaceVariantDark.withValues(alpha: 0.6),
                ]
              : [
                  AppColors.surface,
                  AppColors.primaryContainer.withValues(alpha: 0.3),
                ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ───────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Monthly Summary',
                style: AppTypography.titleSmall.copyWith(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // Streak badge
              if (streak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.space12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.skipped.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.skipped.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(
                        '$streak-day streak',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.skipped,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.space16),

          // ── Stat pills ───────────────────────────────────────────────
          Row(
            children: [
              _StatPill(
                label: 'Present',
                value: presentCount,
                color: AppColors.present,
              ),
              const SizedBox(width: AppConstants.space8),
              _StatPill(
                label: 'Absent',
                value: absentCount,
                color: AppColors.absent,
              ),
              const SizedBox(width: AppConstants.space8),
              _StatPill(
                label: 'Skipped',
                value: skippedCount,
                color: AppColors.skipped,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space16),

          // ── Rate bar ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: attendanceRate,
                        minHeight: 7,
                        backgroundColor: isDark
                            ? AppColors.borderDark
                            : AppColors.surfaceVariant,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(rateColor),
                      ),
                    ),
                    const SizedBox(height: AppConstants.space6),
                    Text(
                      '$pct% attendance rate',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.space16),
              // Large rate display
              Text(
                '$pct%',
                style: AppTypography.numericMedium.copyWith(
                  color: rateColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.space12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: AppTypography.numericSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── History tile ───────────────────────────────────────────────────────────────

/// Color-coded card for a single attendance record.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.record,
    required this.isDark,
  });

  final AttendanceModel record;
  final bool isDark;

  Color get _statusColor {
    switch (record.status) {
      case AttendanceStatus.present:
        return AppColors.present;
      case AttendanceStatus.absent:
        return AppColors.absent;
      case AttendanceStatus.skipped:
        return AppColors.skipped;
      case AttendanceStatus.onVacation:
        return AppColors.vacation;
      case AttendanceStatus.pending:
        return AppColors.warning;
    }
  }

  String get _statusLabel {
    switch (record.status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.skipped:
        return 'Skipped';
      case AttendanceStatus.onVacation:
        return 'Vacation';
      case AttendanceStatus.pending:
        return 'Pending';
    }
  }

  IconData get _statusIcon {
    switch (record.status) {
      case AttendanceStatus.present:
        return Icons.check_circle_rounded;
      case AttendanceStatus.absent:
        return Icons.cancel_rounded;
      case AttendanceStatus.skipped:
        return Icons.remove_circle_rounded;
      case AttendanceStatus.onVacation:
        return Icons.beach_access_rounded;
      case AttendanceStatus.pending:
        return Icons.pending_rounded;
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  String _formatTime(DateTime d) =>
      TimeFormat.tod12(TimeOfDay.fromDateTime(d));

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
        // Left accent bar via boxShadow trick is not reliable; use decoration
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left color accent strip
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppConstants.cardRadius),
                  bottomLeft: Radius.circular(AppConstants.cardRadius),
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.space12,
                  vertical: AppConstants.space12,
                ),
                child: Row(
                  children: [
                    // Status icon
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_statusIcon, size: 18, color: color),
                    ),
                    const SizedBox(width: AppConstants.space12),

                    // Meal name + date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.mealName ?? record.mealId,
                            style: AppTypography.titleSmall.copyWith(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(record.date),
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Status + time
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _statusLabel,
                            style: AppTypography.labelSmall.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (record.markedAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatTime(record.markedAt!),
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── State views ────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: AppColors.primary,
        strokeWidth: 2.5,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.isDark,
    required this.onRetry,
  });

  final String message;
  final bool isDark;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 30,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppConstants.space16),
            Text(
              'Could not load history',
              style: AppTypography.titleSmall.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppConstants.space20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppConstants.space20),
            Text(
              'No records found',
              style: AppTypography.titleMedium.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'No attendance records in the\nselected date range.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
