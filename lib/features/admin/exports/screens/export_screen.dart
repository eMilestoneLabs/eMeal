import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/features/admin/exports/providers/export_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_primary_button.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Export screen — PDF or CSV attendance reports.
/// Group name is resolved dynamically; never hardcoded.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});
  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final ExportProvider _provider;
  final GroupRepository _groupRepo = GroupRepository();

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  List<AttendanceModel> _records = [];
  List<MealModel> _meals = [];
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
        // Use effectiveGroupIds.firstOrNull for multi-group correctness.
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

  Future<void> _loadAndExport() async {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    setState(() => _loadingRecords = true);
    final groupId = _selectedGroupId ?? user.groupId ?? '';
    final orgId = user.organizationId;
    final result = await AttendanceRepository().getAttendanceHistory(
      userId: '', // empty = group-scope query (all members), not admin's own records
      groupId: groupId, organizationId: orgId,
      from: _startDate, to: _endDate,
      params: const PaginationParams(page: 1, limit: 100),
    );
    List<AttendanceModel> records = [];
    if (result case Ok(:final value)) records = value.data;
    // Load the group's meals (with prices + windows) for Price Tag + auto-skip.
    final mealsResult = await MealRepository().getGroupMeals(
      organizationId: orgId,
      groupId: groupId,
    );
    List<MealModel> meals = [];
    if (mealsResult case Ok(:final value)) meals = value;
    setState(() {
      _records = records;
      _meals = meals;
      _loadingRecords = false;
    });
    await _provider.export(
      records: _records,
      meals: _meals,
      groupName: _selectedGroupName,
      pricingEnabled: _pricingEnabled,
      from: _startDate,
      to: _endDate,
      dateRangeLabel: '${_fmt(_startDate)} – ${_fmt(_endDate)}',
    );
    if (_provider.exportSuccess && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export ready — share sheet opened.')));
    }
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
              _FormatTile(label: 'PDF Report', icon: Icons.picture_as_pdf_rounded,
                  selected: _provider.isPdf, color: AppColors.absent,
                  onTap: () => _provider.setFormat('pdf')),
              const SizedBox(width: 12),
              _FormatTile(label: 'Excel (.xlsx)', icon: Icons.table_chart_rounded,
                  selected: !_provider.isPdf, color: AppColors.secondary,
                  onTap: () => _provider.setFormat('xlsx')),
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
            AppPrimaryButton(
              label: _provider.isExporting || _loadingRecords
                  ? 'Exporting…'
                  : 'Export ${_provider.exportFormat.toUpperCase()}',
              icon: _provider.isPdf ? Icons.picture_as_pdf_rounded : Icons.table_chart_rounded,
              isLoading: _provider.isExporting || _loadingRecords,
              onPressed: _provider.isExporting || _loadingRecords ? null : _loadAndExport,
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
