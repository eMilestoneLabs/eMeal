import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

// ── DeleteAccountSection ───────────────────────────────────────────────────────

/// Pass 14 (FR-DEL-011) — self-service account deletion entry point, shared by
/// the student and admin profile screens.
///
/// Renders a subdued danger link below Sign Out. Tapping it opens a
/// confirmation dialog that requires typing DELETE (and the current password
/// when the account has one) before calling `DELETE /users/me`. The backend
/// revokes every session, soft-removes memberships and anonymizes PII;
/// attendance/billing history needed for group records is retained per policy
/// — the dialog copy says so explicitly.
class DeleteAccountSection extends StatelessWidget {
  const DeleteAccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => _confirmAndDelete(context),
        icon: const Icon(Icons.delete_forever_outlined, size: 18),
        label: const Text('Delete Account'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.error.withValues(alpha: 0.8),
          textStyle: AppTypography.labelMedium,
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final auth = AuthProviderScope.of(context);
    final router = GoRouter.of(context);
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => _DeleteAccountDialog(auth: auth),
    );
    if (deleted == true) {
      // Session is already cleared by AuthProvider.deleteAccount.
      router.go(RouteNames.roleSelect);
    }
  }
}

// ── Confirmation dialog ────────────────────────────────────────────────────────

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.auth});

  final AuthProvider auth;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirmController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _deleting = false;
  bool _obscure = true;
  String? _error;

  bool get _confirmed => _confirmController.text.trim() == 'DELETE';

  @override
  void dispose() {
    _confirmController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    final error = await widget.auth.deleteAccount(
      password: _passwordController.text.isEmpty
          ? null
          : _passwordController.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _deleting = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.error, size: 24),
          const SizedBox(width: AppConstants.space8),
          Expanded(
            child: Text(
              'Delete Account?',
              style: AppTypography.titleMedium.copyWith(color: textColor),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently deletes your account and signs you out of '
              'every device. Your name, email, phone and photo are erased. '
              'Attendance and billing history required for your group\'s '
              'records is retained per policy, without your personal details.',
              style: AppTypography.bodySmall.copyWith(color: subColor),
            ),
            const SizedBox(height: AppConstants.space16),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              enabled: !_deleting,
              style: AppTypography.bodyMedium.copyWith(color: textColor),
              decoration: InputDecoration(
                labelText: 'Current password',
                helperText: 'Leave blank if you sign in with OTP only',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.space12),
            TextField(
              controller: _confirmController,
              enabled: !_deleting,
              onChanged: (_) => setState(() {}),
              style: AppTypography.bodyMedium.copyWith(color: textColor),
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppConstants.space12),
              Text(
                _error!,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _deleting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirmed && !_deleting ? _delete : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          child: _deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Delete Forever'),
        ),
      ],
    );
  }
}
