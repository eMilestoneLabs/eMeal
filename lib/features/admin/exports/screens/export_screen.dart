import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/features/admin/exports/providers/export_provider.dart';
import 'package:smart_meal_management/features/admin/exports/screens/export_preview_screen.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_primary_button.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Export screen — PDF / Excel / CSV attendance reports.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final ExportProvider _provider;
  final GroupRepository _groupRepo = GroupRepository();

  // Issue 3: default export range is the CURRENT CALENDAR MONTH (1st → today),
  // not a rolling 30-day window. Admin can still pick any custom range.
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  /// Drives the preview screen's export buttons (FR-EXP-040).
  final ValueNotifier<bool> _exporting = ValueNotifier<bool>(false);
  bool _loadingRecords = false;
  List<GroupModel> _groups = [];
  String? _selectedGroupId;
  bool _loadingGroups = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _provider = ExportProvider();
    _provider.addListener(_rebuild);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadGroups();
    }
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    _exporting.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    final orgId = user.organizationId;
    final result = await _groupRepo.getOrganisationGroups(organizationId: orgId);
    if (!mounted) return;
    setState(() {
      _loadingGroups = false;
      if (result case Ok(:final value)) {
        _groups = value.data;
        final uid = auth.currentUser?.effectiveGroupIds.firstOrNull;
        final match = _groups.any((g) => g.id == uid);
        _selectedGroupId = match ? uid : (_groups.isNotEmpty ? _groups.first.id : null);
      }
    });
  }

  String get _selectedGroupName {
    if (_selectedGroupId == null) return 'All Groups';
    try { return _groups.firstWhere((g) => g.id == _selectedGroupId).name; }
    catch (_) { return 'Group'; }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(context: context,
        initialDate: _startDate,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: _endDate);
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(context: context,
        initialDate: _endDate, firstDate: _startDate, lastDate: DateTime.now());
    if (picked != null) setState(() => _endDate = picked);
  }

  bool get _pricingEnabled {
    if (_selectedGroupId == null) return false;
    try {
      return _groups
          .firstWhere((g) => g.id == _selectedGroupId)
          .mealConfig
          .mealPricingEnabled;
    } catch (_) {
      return false;
    }
  }

  /// FR-EXP-040 (ISSUE-14): loads the report data and opens the VIEW-ONLY
  /// preview (summary first). Download/share happens only from the preview.
  Future<void> _previewReport() async {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    setState(() => _loadingRecords = true);
    final groupId = _selectedGroupId ?? user.groupId ?? '';
    final orgId = user.organizationId;
    final result = await AttendanceRepository().getAttendanceHistory(
      userId: '',
      groupId: groupId, organizationId: orgId,
      from: _startDate, to: _endDate,
      params: const PaginationParams(page: 1, limit: 100),
    );
    List<AttendanceModel> records = [];
    if (result case Ok(:final value)) records = value.data;
    final mealsResult = await MealRepository().getGroupMeals(
      organizationId: orgId,
      groupId: groupId,
    );
    List<MealModel> meals = [];
    if (mealsResult case Ok(:final value)) meals = value;
    // Issue 4: members currently on vacation are excluded from billing/auto-skip
    // in the export so the report matches the on-screen figures and surfaces
    // vacation rather than counting them absent/skipped.
    final membersResult = await _groupRepo.getGroupMembers(
      organizationId: orgId,
      groupId: groupId,
    );
    Set<String> vacationUserIds = const {};
    if (membersResult case Ok(:final value)) {
      vacationUserIds = value.data
          .where((u) => u.isVacationMode)
          .map((u) => u.id)
          .toSet();
    }
    if (!mounted) return;
    setState(() => _loadingRecords = false);

    // Compute the EXACT rows/summaries the export files will contain, so the
    // preview and the downloaded report can never disagree.
    final rows = BillingService.buildRows(
      records: records,
      meals: meals,
      from: _startDate,
      to: _endDate,
      vacationUserIds: vacationUserIds,
    );
    final summaries = BillingService.summarize(rows);
    final rangeLabel = '${_fmt(_startDate)} – ${_fmt(_endDate)}';
    final groupName = _selectedGroupName;
    final pricingEnabled = _pricingEnabled;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExportPreviewScreen(
          rows: rows,
          summaries: summaries,
          groupName: groupName,
          pricingEnabled: pricingEnabled,
          dateRangeLabel: rangeLabel,
          isExporting: _exporting,
          onExport: (format) => _export(
            format: format,
            records: records,
            meals: meals,
            groupName: groupName,
            pricingEnabled: pricingEnabled,
            rangeLabel: rangeLabel,
            vacationUserIds: vacationUserIds,
          ),
        ),
      ),
    );
  }

  /// Shares the report in [format] from the preview (FR-EXP-040 step 2).
  Future<void> _export({
    required String format,
    required List<AttendanceModel> records,
    required List<MealModel> meals,
    required String groupName,
    required bool pricingEnabled,
    required String rangeLabel,
    required Set<String> vacationUserIds,
  }) async {
    _provider.setFormat(format);
    _exporting.value = true;
    try {
      await _provider.export(
        records: records,
        meals: meals,
        groupName: groupName,
        pricingEnabled: pricingEnabled,
        from: _startDate,
        to: _endDate,
        dateRangeLabel: rangeLabel,
        vacationUserIds: vacationUserIds,
      );
    } finally {
      _exporting.value = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_provider.exportSuccess
            ? 'Export ready — share sheet opened.'
            : (_provider.error ?? 'Export failed')),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('Export Attendance', style: AppTypography.titleLarge),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.pagePaddingH,
          vertical: AppConstants.pagePaddingV,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadingGroups) const LinearProgressIndicator()
            else if (_groups.isNotEmpty) ...[
              Text('Group', style: AppTypography.titleSmall),
              const SizedBox(height: AppConstants.space12),
              _ExportGroupDropdown(groups: _groups, selectedGroupId: _selectedGroupId,
                  onChanged: (id) => setState(() => _selectedGroupId = id)),
              const SizedBox(height: AppConstants.space24),
            ],
            Text('Export Format', style: AppTypography.titleSmall),
            const SizedBox(height: AppConstants.space12),
            Row(children: [
              _FormatTile(label: 'PDF', icon: Icons.picture_as_pdf_rounded,
                  selected: _provider.exportFormat == 'pdf', color: AppColors.absent,
                  onTap: () => _provider.setFormat('pdf')),
              const SizedBox(width: 12),
              _FormatTile(label: 'Excel', icon: Icons.table_chart_rounded,
                  selected: _provider.exportFormat == 'xlsx', color: AppColors.secondary,
                  onTap: () => _provider.setFormat('xlsx')),
              const SizedBox(width: 12),
              _FormatTile(label: 'CSV', icon: Icons.description_rounded,
                  selected: _provider.exportFormat == 'csv', color: AppColors.info,
                  onTap: () => _provider.setFormat('csv')),
            ]),
            const SizedBox(height: AppConstants.space24),
            Text('Date Range', style: AppTypography.titleSmall),
            const SizedBox(height: AppConstants.space12),
            Row(children: [
              Expanded(child: _DateTile(label: 'From', date: _startDate, onTap: _pickStartDate)),
              const SizedBox(width: 12),
              Expanded(child: _DateTile(label: 'To', date: _endDate, onTap: _pickEndDate)),
            ]),
            const Spacer(),
            if (_provider.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_provider.error!,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.absent),
                    textAlign: TextAlign.center),
              ),
            // FR-EXP-040 (ISSUE-14): a view-only preview always comes before
            // download/share; the summary is presented first on the preview.
            AppPrimaryButton(
              label: _loadingRecords ? 'Preparing preview…' : 'Preview Report',
              icon: Icons.visibility_rounded,
              isLoading: _provider.isExporting || _loadingRecords,
              onPressed: _provider.isExporting || _loadingRecords
                  ? null
                  : _previewReport,
            ),
            const SizedBox(height: AppConstants.space24),
          ],
        ),
      ),
    );
  }
}

class _ExportGroupDropdown extends StatelessWidget {
  const _ExportGroupDropdown({required this.groups, required this.selectedGroupId, required this.onChanged});
  final List<GroupModel> groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedGroupId, isExpanded: true,
          style: AppTypography.bodyMedium.copyWith(color: Theme.of(context).colorScheme.onSurface),
          items: groups.map((g) => DropdownMenuItem(value: g.id,
              child: Text(g.name, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.label, required this.icon, required this.selected,
      required this.color, required this.onTap});
  final String label; final IconData icon; final bool selected;
  final Color color; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(onTap: onTap,
        child: AnimatedContainer(duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.1) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: selected ? color : AppColors.border, width: selected ? 1.5 : 1),
          ),
          child: Column(children: [
            Icon(icon, color: selected ? color : AppColors.textSecondary, size: 28),
            const SizedBox(height: 8),
            Text(label, style: AppTypography.labelMedium.copyWith(
                color: selected ? color : AppColors.textSecondary), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.date, required this.onTap});
  final String label; final DateTime date; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fmt = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return GestureDetector(onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(fmt, style: AppTypography.labelMedium.copyWith(color: AppColors.textPrimary)),
          ]),
        ]),
      ),
    );
  }
}
