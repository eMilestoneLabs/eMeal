import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/auth/utils/auth_validators.dart';
import 'package:smart_meal_management/features/auth/widgets/password_strength_indicator.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';

/// Reset password — step 2.
///
/// User enters the Email OTP they received and their new password, then:
///   POST /auth/reset-password  { identifier, otp, newPassword }
///   → returns 200 with new JWT session on success
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.identifier,
    this.roleContext = 'student',
  });

  /// The email passed from [ForgotPasswordScreen].
  final String identifier;

  /// Workspace to return to after a successful reset ('student' | 'admin' | 'event').
  final String roleContext;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _success = false;
  String? _error;

  // Resend cooldown (AUTH-039) — the code was just sent by ForgotPasswordScreen,
  // so resend is gated behind a short countdown to prevent abuse.
  static const _resendCooldown = 30;
  int _resendLeft = _resendCooldown;
  bool _isResending = false;
  Timer? _timer;
  bool get _canResend => _resendLeft == 0 && !_isResending;

  // FV-004 + Issue 4: enable "Reset Password" only when the 6-digit code is
  // present AND the new password passes the strong-password policy (not weak)
  // AND confirm matches. Weak passwords are rejected.
  bool get _canSubmit =>
      _otpCtrl.text.trim().length >= 6 &&
      AuthValidators.password(_passwordCtrl.text) == null &&
      _confirmCtrl.text == _passwordCtrl.text;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _resendLeft = _resendCooldown;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendLeft > 0) {
          _resendLeft--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _resend() async {
    if (!_canResend) return;
    setState(() {
      _isResending = true;
      _error = null;
    });
    final errorMsg = await AuthProviderScope.of(context).requestOtp(
      identifier: widget.identifier,
      purpose: 'reset',
    );
    if (!mounted) return;
    setState(() => _isResending = false);
    if (errorMsg != null) {
      setState(() => _error = errorMsg);
      return;
    }
    _startCountdown();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reset code resent to ${widget.identifier}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // AuthRepository.resetPassword → POST /auth/reset-password.
    final auth = AuthProviderScope.of(context);
    final errorMsg = await auth.resetPassword(
      identifier: widget.identifier,
      otp: _otpCtrl.text.trim(),
      newPassword: _passwordCtrl.text,
    );

    if (!mounted) return;

    if (errorMsg != null) {
      setState(() {
        _error = errorMsg;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _success = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    if (_success) {
      return _SuccessView(isDark: isDark, roleContext: widget.roleContext);
    }

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
                    Icons.key_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(height: AppConstants.space20),
                Text(
                  'Reset Password',
                  style: AppTypography.headlineSmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppConstants.space8),
                RichText(
                  text: TextSpan(
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      height: 1.6,
                    ),
                    children: [
                      const TextSpan(text: 'Code sent to '),
                      TextSpan(
                        text: widget.identifier,
                        style: AppTypography.bodyMedium.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: '. Enter it below with your new password.'),
                    ],
                  ),
                ),

                const SizedBox(height: AppConstants.space32),

                // ── OTP field ─────────────────────────────────────────────
                _FieldLabel(label: 'Reset Code', isDark: isDark),
                const SizedBox(height: AppConstants.space8),
                TextFormField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() => _error = null),
                  decoration: _inputDecoration(
                    isDark: isDark,
                    hint: '6-digit code',
                    icon: Icons.pin_rounded,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 6) {
                      return 'Enter the 6-digit code sent to your email';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppConstants.space8),
                // Guided UX (Option B): the request is anti-enumerating, so if the
                // email has no account no code arrives — tell the user how to recover
                // without revealing whether the account exists.
                Text(
                  "Didn't get a code? Make sure you entered the email you "
                  'registered with, then resend.',
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),

                // ── Resend code ───────────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: _isResending
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          onPressed: _canResend ? _resend : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _resendLeft > 0
                                ? 'Resend code in ${_resendLeft}s'
                                : 'Resend code',
                            style: AppTypography.labelSmall.copyWith(
                              color: _canResend
                                  ? AppColors.primary
                                  : (isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: AppConstants.space12),

                // ── New password ──────────────────────────────────────────
                _FieldLabel(label: 'New Password', isDark: isDark),
                const SizedBox(height: AppConstants.space8),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: _inputDecoration(
                    isDark: isDark,
                    hint: 'Min. 8 characters',
                    icon: Icons.lock_outline_rounded,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => AuthValidators.password(v ?? ''),
                ),

                // Issue 4: live strength meter on the new password.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _passwordCtrl,
                  builder: (_, value, _) =>
                      PasswordStrengthIndicator(password: value.text),
                ),

                const SizedBox(height: AppConstants.space20),

                // ── Confirm password ──────────────────────────────────────
                _FieldLabel(label: 'Confirm Password', isDark: isDark),
                const SizedBox(height: AppConstants.space8),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: _inputDecoration(
                    isDark: isDark,
                    hint: 'Re-enter new password',
                    icon: Icons.lock_outline_rounded,
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v != _passwordCtrl.text) {
                      return 'Passwords do not match';
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

                // ── Submit ────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: AppConstants.buttonHeight,
                  child: FilledButton(
                    onPressed: (_isLoading || !_canSubmit) ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.buttonRadius),
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
                            'Reset Password',
                            style: AppTypography.labelLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
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

  InputDecoration _inputDecoration({
    required bool isDark,
    required String hint,
    required IconData icon,
  }) =>
      InputDecoration(
        hintText: hint,
        counterText: '',
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceVariant,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      );
}

// ── Field label ────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.isDark});
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      );
}

// ── Success view ───────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.isDark, required this.roleContext});
  final bool isDark;
  final String roleContext;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.space32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.present.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 44,
                  color: AppColors.present,
                ),
              ),
              const SizedBox(height: AppConstants.space24),
              Text(
                'Password Reset!',
                style: AppTypography.headlineSmall.copyWith(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppConstants.space12),
              Text(
                'Your password has been reset successfully. '
                'You can now log in with your new password.',
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.space40),
              SizedBox(
                width: double.infinity,
                height: AppConstants.buttonHeight,
                child: FilledButton(
                  // Issue 1: return to the SAME workspace login (admin vs student).
                  onPressed: () => context.go(
                    RouteNames.login,
                    extra: AuthRouteExtra(roleContext: roleContext),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.buttonRadius),
                    ),
                  ),
                  child: Text(
                    'Back to Login',
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
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
