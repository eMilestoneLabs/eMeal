import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/notice_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Premium priority colours (Issue 2) — shared with the notice feed card so the
/// chip in the composer matches what members will see. Spec: low=grey,
/// normal=blue, high=orange, urgent=red — legible in light and dark themes.
Color noticePriorityColor(String priority) {
  switch (priority) {
    case 'urgent':
      return AppColors.error;
    case 'high':
      return AppColors.warning;
    case 'low':
      return AppColors.textTertiary;
    default:
      return AppColors.info;
  }
}

/// Admin composer for a new notice (Phase B). Pops `true` on success so the
/// feed refreshes. Scope defaults to the admin's current group; can be switched
/// to organisation-wide.
class NoticeComposerScreen extends StatefulWidget {
  const NoticeComposerScreen({
    super.key,
    required this.organizationId,
    required this.groupId,
  });

  final String organizationId;
  final String? groupId;

  @override
  State<NoticeComposerScreen> createState() => _NoticeComposerScreenState();
}

class _NoticeComposerScreenState extends State<NoticeComposerScreen> {
  final _repo = NoticeRepository();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  String _priority = 'normal';
  bool _pinned = false;
  DateTime? _expiresAt;
  bool _saving = false;
  String? _error;

  // Issue 2: targeting. 'org' = entire organisation; 'groups' = specific
  // groups. Specific-group delivery reuses the existing single-groupId contract
  // by posting one notice per selected group — no schema / contract change.
  String _scope = 'org';
  List<GroupModel> _groups = [];
  final Set<String> _selectedGroupIds = {};
  bool _loadingGroups = true;

  @override
  void initState() {
    super.initState();
    // With a current-group context, default to targeting that group; otherwise
    // organisation-wide.
    if (widget.groupId != null) {
      _scope = 'groups';
      _selectedGroupIds.add(widget.groupId!);
    }
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final res = await GroupRepository()
        .getOrganisationGroups(organizationId: widget.organizationId);
    if (!mounted) return;
    setState(() {
      if (res case Ok(:final value)) _groups = value.data;
      _loadingGroups = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _expiresAt =
          DateTime(picked.year, picked.month, picked.day, 23, 59));
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'Title and message are required.');
      return;
    }
    if (_scope == 'groups' && _selectedGroupIds.isEmpty) {
      setState(() => _error =
          'Select at least one group, or choose Entire organisation.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    // Org-wide = one notice with no group. Specific groups = one notice per
    // selected group (reuses the single-groupId contract; fully additive).
    String? firstError;
    if (_scope == 'org') {
      final res = await _repo.createNotice(
        title: title,
        body: body,
        groupId: null,
        priority: _priority,
        pinned: _pinned,
        expiresAt: _expiresAt,
      );
      if (res case Err(:final failure)) firstError = failure.message;
    } else {
      for (final gid in _selectedGroupIds) {
        final res = await _repo.createNotice(
          title: title,
          body: body,
          groupId: gid,
          priority: _priority,
          pinned: _pinned,
          expiresAt: _expiresAt,
        );
        if (res case Err(:final failure)) {
          firstError = failure.message;
          break;
        }
      }
    }
    if (!mounted) return;
    if (firstError == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = firstError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Post notice', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          _label('Title'),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            maxLength: 160,
            decoration: _dec('What is this about?'),
          ),
          const SizedBox(height: 8),
          _label('Message'),
          const SizedBox(height: 6),
          TextField(
            controller: _bodyCtrl,
            maxLines: 6,
            maxLength: 4000,
            decoration: _dec('Write the announcement...'),
          ),
          const SizedBox(height: 8),
          _label('Priority'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['low', 'normal', 'high', 'urgent'].map((p) {
              final sel = _priority == p;
              final c = noticePriorityColor(p);
              return GestureDetector(
                onTap: () => setState(() => _priority = p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? c : c.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? c : c.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sel) ...[
                        const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        p[0].toUpperCase() + p.substring(1),
                        style: AppTypography.labelMedium.copyWith(
                          color: sel ? Colors.white : c,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Pin to top', style: AppTypography.labelLarge),
            value: _pinned,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _pinned = v),
          ),
          _label('Send to'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ScopeOption(
                  label: 'Entire organisation',
                  icon: Icons.apartment_rounded,
                  selected: _scope == 'org',
                  onTap: () => setState(() => _scope = 'org'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ScopeOption(
                  label: 'Specific groups',
                  icon: Icons.groups_rounded,
                  selected: _scope == 'groups',
                  onTap: () => setState(() => _scope = 'groups'),
                ),
              ),
            ],
          ),
          if (_scope == 'org')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Visible to every group in your organisation.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
          if (_scope == 'groups') ...[
            const SizedBox(height: 6),
            if (_loadingGroups)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_groups.isEmpty)
              Text(
                'No groups yet — create a group first.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textTertiary),
              )
            else
              Column(
                children: _groups.map((g) {
                  final checked = _selectedGroupIds.contains(g.id);
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.primary,
                    title: Text(g.name, style: AppTypography.bodyMedium),
                    value: checked,
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _selectedGroupIds.add(g.id);
                      } else {
                        _selectedGroupIds.remove(g.id);
                      }
                    }),
                  );
                }).toList(),
              ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_busy_rounded),
            title: Text('Expiry (optional)', style: AppTypography.labelLarge),
            subtitle: Text(
              _expiresAt == null
                  ? 'Never expires'
                  : 'Hidden after ${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary),
            ),
            trailing: _expiresAt == null
                ? TextButton(onPressed: _pickExpiry, child: const Text('Set'))
                : TextButton(
                    onPressed: () => setState(() => _expiresAt = null),
                    child: const Text('Clear')),
            onTap: _pickExpiry,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.campaign_rounded),
              label: Text(_saving ? 'Posting...' : 'Post notice'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700));

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}

/// Issue 2: a premium segmented option for the notice targeting selector.
class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.primary;
    return Material(
      color: selected
          ? c.withValues(alpha: 0.12)
          : (isDark ? AppColors.surfaceDark : AppColors.surface),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? c
                  : (isDark ? AppColors.borderDark : AppColors.border)
                      .withValues(alpha: 0.6),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? c : AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: selected
                        ? c
                        : (isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
