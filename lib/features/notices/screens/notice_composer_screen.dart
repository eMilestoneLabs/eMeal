import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/notice_repository.dart';
import 'package:smart_meal_management/shared/models/result.dart';

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
  bool _orgWide = false;
  DateTime? _expiresAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // No group context -> force organisation-wide.
    _orgWide = widget.groupId == null;
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
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await _repo.createNotice(
      title: title,
      body: body,
      groupId: _orgWide ? null : widget.groupId,
      priority: _priority,
      pinned: _pinned,
      expiresAt: _expiresAt,
    );
    if (!mounted) return;
    switch (res) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() {
          _saving = false;
          _error = failure.message;
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
            children: ['low', 'normal', 'high', 'urgent'].map((p) {
              final sel = _priority == p;
              return ChoiceChip(
                label: Text(p[0].toUpperCase() + p.substring(1)),
                selected: sel,
                onSelected: (_) => setState(() => _priority = p),
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Organisation-wide', style: AppTypography.labelLarge),
            subtitle: Text(
              _orgWide
                  ? 'Visible to every group in your organisation'
                  : 'Visible only to your current group',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary),
            ),
            value: _orgWide,
            activeThumbColor: AppColors.primary,
            onChanged: widget.groupId == null
                ? null
                : (v) => setState(() => _orgWide = v),
          ),
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
