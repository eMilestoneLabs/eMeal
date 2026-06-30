import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Forgot password — step 1.
///
/// User enters their registered email or mobile number. The app triggers
/// an OTP/reset-link via the backend (mock: always succeeds).
///
/// On success → navigate to [ResetPasswordScreen] carrying the identifier.
///
/// Backend wiring point:
///   POST /v1/auth/forgot-password  { identifier }
///   → returns 200 with message confirming OTP sent
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // AUTH-017: Forgot Password is Email-OTP only. purpose:'reset' routes to
    // the backend /auth/forgot-password endpoint (email-only, non-enumerating).
    final errorMsg = await AuthProviderScope.of(context).requestOtp(
      identifier: _identifierCtrl.text.trim(),
      purpose: 'reset',
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (errorMsg != null) {
      setState(() => _error = errorMsg);
    } else {
      context.push(
        RouteNames.resetPassword,
        extra: _identifierCtrl.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    // FV-004: enable "Send Reset Code" only for a valid email (AUTH-017).
    final canSubmit =
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_identifierCtrl.text.trim());

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.space24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ────────────────────────────────────────────────
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(height: AppConstants.space20),
                Text(
                  'Forgot Password?',
                  style: AppTypography.headlineSmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppConstants.space8),
                Text(
                  'Enter your registered email address. '
                  'We\'ll send you a one-time code to reset your password. '
                  '(Mobile OTP recovery is coming soon.)',
                  style: AppTypography.bodyMedium.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: AppConstants.space32),

                // ── Input ─────────────────────────────────────────────────
                Text(
                  'Email',
                  style: AppTypography.labelMedium.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppConstants.space8),
                TextFormField(
                  controller: _identifierCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: const Icon(
                      Icons.alternate_email_rounded,
                      size: 18,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.surfaceDark
                        : AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.borderDark : AppColors.border,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) {
                      return 'Please enter your email address';
                    }
                    // AUTH-017: recovery is Email-OTP only in this release.
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),

                // ── Error ─────────────────────────────────────────────────
                if (_error != null) ...[
                  const SizedBox(height: AppConstants.space16),
                  Container(
                    padding: const EdgeInsets.all(AppConstants.space12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(AppConstants.cardRadius),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 16, color: AppColors.error),
                        const SizedBox(width: AppConstants.space8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppConstants.space32),

                // ── Submit button ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: AppConstants.buttonHeight,
                  child: FilledButton(
                    onPressed: (_isLoading || !canSubmit) ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            AppConstants.buttonRadius),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Send Reset Code',
                            style: AppTypography.labelLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: AppConstants.space20),

                // ── Back to login ─────────────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      'Back to Login',
                      style: AppTypography.labelMedium.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
