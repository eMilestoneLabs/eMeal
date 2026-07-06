import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// FR-EXP-040/041 (ISSUE-14) — view-only report preview.
///
/// Shown BEFORE any download/share: the Summary section comes first (default),
/// detailed line-items second. The bottom bar shares the report as PDF /
/// Excel / CSV — the same figures the preview shows (single source of truth:
/// BillingService rows/summaries computed once by the caller).
class ExportPreviewScreen extends StatelessWidget {
  const ExportPreviewScreen({
    super.key,
    required this.rows,
    required this.summaries,
    required this.groupName,
    required this.pricingEnabled,
    required this.dateRangeLabel,
    required this.onExport,
    required this.isExporting,
    this.financialsByUser = const {},
  });

  final List<BillingRow> rows;
  final List<BillingSummary> summaries;
  final String groupName;
  final bool pricingEnabled;
  final String dateRangeLabel;

  /// Guests + adjustments per member — the preview headlines the same
  /// host-inclusive NET bill the exported files (and billing screens) show.
  final Map<String, MemberExportFinancials> financialsByUser;

  /// Triggers the actual export ('pdf' | 'xlsx' | 'csv').
  final Future<void> Function(String format) onExport;

  /// Rebuild-driving flag from the export provider (disables buttons).
  final ValueListenable<bool> isExporting;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Report Preview', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ── Report metadata (FR-EXP-043) ─────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ExportService.brandLine,
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.primary)),
                const SizedBox(height: 4),
                Text('Group: $groupName',
                    style: AppTypography.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  'Period: $dateRangeLabel · Timezone: ${ExportService.tzLabel()}',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.space16),

          // ── 1. Summary (FIRST — FR-EXP-041) ──────────────────────────────
          Text('Billing Summary',
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppConstants.space8),
          if (summaries.isEmpty)
            Text('No attendance in this period.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary))
          else
            ...summaries.map((s) => _summaryCard(s, isDark)),

          const SizedBox(height: AppConstants.space16),

          // ── 2. Detailed records (secondary) ──────────────────────────────
          Text('Detailed Records (${rows.length})',
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppConstants.space8),
          ...rows.take(200).map((r) => _detailRow(r, isDark)),
          if (rows.length > 200)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '… ${rows.length - 200} more rows — the full list is included '
                'in the exported file.',
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
        ],
      ),

      // ── Export actions (download happens only AFTER the preview) ─────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ValueListenableBuilder<bool>(
            valueListenable: isExporting,
            builder: (context, exporting, _) => Row(
              children: [
                _exportBtn(context, 'PDF', Icons.picture_as_pdf_rounded,
                    AppColors.absent, exporting, () => onExport('pdf')),
                const SizedBox(width: 10),
                _exportBtn(context, 'Excel', Icons.table_chart_rounded,
                    AppColors.secondary, exporting, () => onExport('xlsx')),
                const SizedBox(width: 10),
                _exportBtn(context, 'CSV', Icons.description_rounded,
                    AppColors.info, exporting, () => onExport('csv')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _exportBtn(BuildContext context, String label, IconData icon,
      Color color, bool exporting, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: exporting ? null : onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _summaryCard(BillingSummary s, bool isDark) {
    final consumed = s.consumedByMeal.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');
    final fin = financialsByUser[s.userId];
    final hasFin = fin != null && fin.hasAny;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.userName,
                    style: AppTypography.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
              if (pricingEnabled)
                Text(
                    hasFin
                        ? MemberExportFinancials.net(
                            '₹', fin.netFor(s.totalBill))
                        : '₹${s.totalBill}',
                    style: AppTypography.titleSmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Present ${s.present} · Skipped ${s.skipped} · Absent ${s.absent} '
            '· Total ${s.totalMeals}',
            style: AppTypography.labelSmall
                .copyWith(color: AppColors.textSecondary),
          ),
          // Host-inclusive money components — matches file exports exactly.
          if (pricingEnabled && hasFin) ...[
            const SizedBox(height: 2),
            Text(
              'Meals ₹${s.totalBill}'
              '${fin.guestAmount != 0 ? ' · Guests (${fin.guestCount}) +₹${fin.guestAmount}' : ''}'
              '${fin.adjustmentsTotal != 0 ? ' · Adj ${fin.adjustmentsTotal > 0 ? '+' : '−'}₹${fin.adjustmentsTotal.abs()}' : ''}',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (consumed.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(consumed,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(BillingRow r, bool isDark) {
    final c = switch (r.status) {
      AttendanceStatus.present => AppColors.present,
      AttendanceStatus.absent => AppColors.absent,
      AttendanceStatus.skipped => AppColors.warning,
      AttendanceStatus.onVacation => AppColors.vacation,
      AttendanceStatus.pending => AppColors.textTertiary,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(r.userName,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium),
          ),
          Expanded(
            flex: 2,
            child: Text(r.mealName,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${r.date.day.toString().padLeft(2, '0')}/${r.date.month.toString().padLeft(2, '0')}',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_statusLabel(r.status),
                style: AppTypography.labelSmall
                    .copyWith(color: c, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(AttendanceStatus s) => switch (s) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.absent => 'Absent',
        AttendanceStatus.skipped => 'Skipped',
        AttendanceStatus.pending => 'Pending',
        AttendanceStatus.onVacation => 'Vacation',
      };
}
