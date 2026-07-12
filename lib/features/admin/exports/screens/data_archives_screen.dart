import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/retention_repository.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_screen_states.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';
import 'package:url_launcher/url_launcher.dart';

/// Reports → Data Archives — SRS Module 03 RPT-010 step 4 / RET-010.
///
/// Lists every pre-purge retention archive (Excel + PDF in MinIO). These
/// files are the admin's PERMANENT copy of data removed from the live server
/// by the rolling 3-month retention policy; they stay downloadable here at
/// any time (download is never a purge precondition).
class DataArchivesScreen extends StatefulWidget {
  const DataArchivesScreen({super.key, this.groupId});

  /// Optional group filter (null = all groups the admin can see).
  final String? groupId;

  @override
  State<DataArchivesScreen> createState() => _DataArchivesScreenState();
}

class _DataArchivesScreenState extends State<DataArchivesScreen> {
  final RetentionRepository _repo = RetentionRepository();

  bool _loading = true;
  String? _error;
  List<GroupArchiveModel> _archives = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repo.listArchives(groupId: widget.groupId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _archives = value;
        case Err(:final failure):
          _error = failure.message;
      }
    });
  }

  /// Opens the archive file externally — the browser/download manager saves
  /// it to the device, which the admin then permanently owns (RET-010).
  Future<void> _download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the archive file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('Data Archives', style: AppTypography.titleLarge),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(colorScheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const AppListSkeleton(rows: 4, rowHeight: 132);
    }
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _load);
    }
    if (_archives.isEmpty) {
      return _EmptyArchives(onRefresh: _load);
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.pagePaddingH,
        vertical: AppConstants.pagePaddingV,
      ),
      itemCount: _archives.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) return _RetentionInfoBanner(colorScheme: colorScheme);
        final archive = _archives[index - 1];
        return _ArchiveCard(
          archive: archive,
          colorScheme: colorScheme,
          onDownloadExcel: () => _download(archive.excelUrl),
          onDownloadPdf: archive.pdfUrl != null
              ? () => _download(archive.pdfUrl!)
              : null,
        );
      },
    );
  }
}

/// Explains WHY archives exist (RPT-009: server optimization, not data loss).
class _RetentionInfoBanner extends StatelessWidget {
  const _RetentionInfoBanner({required this.colorScheme});
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.inventory_2_rounded,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Data older than 3 months is automatically archived to Excel + '
              'PDF before being removed from the live server. These files '
              'are your permanent copy — download them any time.',
              style: AppTypography.bodySmall
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({
    required this.archive,
    required this.colorScheme,
    required this.onDownloadExcel,
    this.onDownloadPdf,
  });

  final GroupArchiveModel archive;
  final ColorScheme colorScheme;
  final VoidCallback onDownloadExcel;
  final VoidCallback? onDownloadPdf;

  static const Map<String, String> _countLabels = {
    'attendance': 'Attendance',
    'guests': 'Guests',
    'corrections': 'Corrections',
    'vacations': 'Vacations',
    'ledgerEntries': 'Adjustments',
    'billingPeriods': 'Billing periods',
  };

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.archive_rounded,
                    size: 20, color: AppColors.secondary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      archive.groupName,
                      style: AppTypography.titleSmall
                          .copyWith(color: colorScheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtDate(archive.periodStart)} – '
                      '${_fmtDate(archive.periodEnd)}'
                      ' · ${archive.totalRecords} records',
                      style: AppTypography.labelSmall
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (archive.recordCounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in archive.recordCounts.entries)
                  if (entry.value > 0)
                    _CountChip(
                      label: _countLabels[entry.key] ?? entry.key,
                      count: entry.value,
                      colorScheme: colorScheme,
                    ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDownloadExcel,
                  icon: const Icon(Icons.table_chart_rounded, size: 18),
                  label: const Text('Excel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDownloadPdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.colorScheme,
  });
  final String label;
  final int count;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label · $count',
        style: AppTypography.labelSmall
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _EmptyArchives extends StatelessWidget {
  const _EmptyArchives({required this.onRefresh});
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // ListView so pull-to-refresh works on the empty state too.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.inventory_2_outlined,
            size: 56, color: colorScheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Center(
          child: Text('No archives yet',
              style: AppTypography.titleMedium
                  .copyWith(color: colorScheme.onSurface)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Archives appear here automatically once a group\'s data '
            'passes the 3-month retention point. Nothing is ever removed '
            'from the server before its archive is generated.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
