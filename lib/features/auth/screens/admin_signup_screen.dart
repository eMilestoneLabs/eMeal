import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';
import 'package:smart_meal_management/features/auth/widgets/auth_input_field.dart';
import 'package:smart_meal_management/features/auth/widgets/password_strength_indicator.dart';
import 'package:smart_meal_management/features/auth/utils/auth_validators.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

// ── AdminSignupScreen ──────────────────────────────────────────────────────────

/// Signup screen for admin and manager roles.
///
/// Identical layout to student signup but with admin-specific role options.
class AdminSignupScreen extends StatefulWidget {
  const AdminSignupScreen({super.key});

  @override
  State<AdminSignupScreen> createState() => _AdminSignupScreenState();
}

class _AdminSignupScreenState extends State<AdminSignupScreen> {
  final _nameCtrl = TextEditingController();
  final _orgNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _orgNameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _ageFocus = FocusNode();

  // Global role defaults to hostelAdmin (base admin). The functional title is
  // assigned per-group when the admin creates a group (AUTH-033).
  final UserRole _role = UserRole.hostelAdmin;
  String _gender = 'Prefer not to say';
  LoginPreference _loginPref = LoginPreference.email;

  String? _nameError;
  String? _orgNameError;
  String? _mobileError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _ageError;

  bool _isLoading = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _orgNameCtrl, _mobileCtrl, _emailCtrl, _passwordCtrl, _confirmCtrl, _ageCtrl]) { c.dispose(); }
    for (final f in [_nameFocus, _orgNameFocus, _mobileFocus, _emailFocus, _passwordFocus, _confirmFocus, _ageFocus]) { f.dispose(); }
    super.dispose();
  }

  // Admins must be adults (AUTH age range, admin min 18).
  static const _ageMin = 18;

  // Organization name: required, 2–30 chars (Issue 7).
  String? _orgNameLive(String value) =>
      value.trim().isEmpty ? null : _orgNameError2(value);
  String? _orgNameError2(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Enter your organization name';
    if (v.length < 2) return 'Organization name must be at least 2 characters';
    if (v.length > 30) return 'Organization name must be 30 characters or fewer';
    return null;
  }

  // FV-004: keep the primary action disabled until all fields are valid.
  bool get _isFormValid =>
      AuthValidators.name(_nameCtrl.text) == null &&
      _orgNameError2(_orgNameCtrl.text) == null &&
      AuthValidators.mobile(_mobileCtrl.text) == null &&
      AuthValidators.email(_emailCtrl.text) == null &&
      AuthValidators.password(_passwordCtrl.text) == null &&
      AuthValidators.confirmPassword(_confirmCtrl.text, _passwordCtrl.text) == null &&
      AuthValidators.age(_ageCtrl.text, min: _ageMin) == null;

  bool _validate() {
    setState(() {
      _nameError = AuthValidators.name(_nameCtrl.text);
      _orgNameError = _orgNameError2(_orgNameCtrl.text);
      _mobileError = AuthValidators.mobile(_mobileCtrl.text);
      _emailError = AuthValidators.email(_emailCtrl.text);
      _passwordError = AuthValidators.password(_passwordCtrl.text);
      _confirmError =
          AuthValidators.confirmPassword(_confirmCtrl.text, _passwordCtrl.text);
      _ageError = AuthValidators.age(_ageCtrl.text, min: _ageMin);
    });
    return _isFormValid;
  }

  Future<void> _signup() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);

    final auth = AuthProviderScope.of(context);
    final error = await auth.signup(
      name: _nameCtrl.text.trim(),
      role: _role,
      mobile: _mobileCtrl.text.trim(),
      email: _emailCtrl.text.trim().toLowerCase(),
      password: _passwordCtrl.text,
      age: int.parse(_ageCtrl.text),
      gender: _gender,
      loginPreference: _loginPref,
      organizationName: _orgNameCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) { setState(() => _emailError = error); return; }

    final identifier = _loginPref == LoginPreference.email
        ? _emailCtrl.text.trim()
        : _mobileCtrl.text.trim();
    await AuthStorageService.instance.saveLoginPreference(_loginPref);
    await AuthStorageService.instance.saveRememberedIdentifier(identifier);
    if (!mounted) return;

    // AUTH-031/036/041: verify the emailed OTP, then continue to the dashboard
    // / group creation.
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty) {
      context.push(
        RouteNames.otp,
        extra: OtpRouteExtra(
          identifier: email,
          roleContext: 'admin',
          purpose: 'signup',
          isSignup: true,
        ),
      );
    } else {
      context.go(RouteNames.adminDashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: Text('Admin Account', style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('Personal Information'),
              const SizedBox(height: 16),

              AuthInputField(
                label: 'Full Name', controller: _nameCtrl, focusNode: _nameFocus,
                errorText: _nameError, textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next, enabled: !_isLoading,
                autofocus: true, // Issue 1
                maxLength: 30,
                onChanged: (v) => setState(
                    () => _nameError = AuthValidators.live(v, AuthValidators.name)),
                onSubmitted: (_) => _mobileFocus.requestFocus(),
              ),
              const SizedBox(height: 14),

              // AUTH-032/033: no admin-role selection at signup — the functional
              // title is assigned when the admin creates a group. Instead we
              // collect the Organization name (Issue 7) used to create the org.
              AuthInputField(
                label: 'Organization Name', controller: _orgNameCtrl, focusNode: _orgNameFocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                errorText: _orgNameError, enabled: !_isLoading,
                maxLength: 30,
                onChanged: (v) => setState(() => _orgNameError = _orgNameLive(v)),
                onSubmitted: (_) => _emailFocus.requestFocus(),
              ),
              const SizedBox(height: 14),

              Row(children: [
                Expanded(
                  child: AuthInputField(
                    label: 'Age', controller: _ageCtrl, focusNode: _ageFocus,
                    keyboardType: TextInputType.number, textInputAction: TextInputAction.next,
                    errorText: _ageError, enabled: !_isLoading,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 2,
                    onChanged: (v) => setState(() => _ageError =
                        AuthValidators.live(v, (x) => AuthValidators.age(x, min: _ageMin))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _GenderDropdown(
                    value: _gender, enabled: !_isLoading,
                    onChanged: (v) => setState(() => _gender = v ?? 'Prefer not to say'),
                  ),
                ),
              ]),
              const SizedBox(height: 24),

              const _SectionLabel('Contact Details'),
              const SizedBox(height: 16),

              AuthInputField(
                label: 'Mobile Number', controller: _mobileCtrl, focusNode: _mobileFocus,
                keyboardType: TextInputType.phone, textInputAction: TextInputAction.next,
                errorText: _mobileError, enabled: !_isLoading,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 10,
                onChanged: (v) => setState(
                    () => _mobileError = AuthValidators.live(v, AuthValidators.mobile)),
                onSubmitted: (_) => _emailFocus.requestFocus(),
              ),
              const SizedBox(height: 14),

              AuthInputField(
                label: 'Email Address', controller: _emailCtrl, focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next,
                errorText: _emailError, enabled: !_isLoading,
                onChanged: (v) => setState(
                    () => _emailError = AuthValidators.live(v, AuthValidators.email)),
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 24),

              const _SectionLabel('Security'),
              const SizedBox(height: 16),

              PasswordField(
                controller: _passwordCtrl, focusNode: _passwordFocus,
                errorText: _passwordError, enabled: !_isLoading,
                textInputAction: TextInputAction.next,
                onChanged: (v) => setState(() {
                  _passwordError = AuthValidators.live(v, AuthValidators.password);
                  _confirmError = _confirmCtrl.text.isEmpty
                      ? null
                      : AuthValidators.confirmPassword(_confirmCtrl.text, v);
                }),
                onSubmitted: (_) => _confirmFocus.requestFocus(),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _passwordCtrl,
                builder: (_, v, _) => PasswordStrengthIndicator(password: v.text),
              ),
              const SizedBox(height: 14),

              PasswordField(
                label: 'Confirm Password', controller: _confirmCtrl, focusNode: _confirmFocus,
                errorText: _confirmError, enabled: !_isLoading,
                onChanged: (v) => setState(() => _confirmError =
                    AuthValidators.live(v, (x) => AuthValidators.confirmPassword(x, _passwordCtrl.text))),
                onSubmitted: (_) => _signup(),
              ),
              const SizedBox(height: 24),

              const _SectionLabel('Login Preference'),
              const SizedBox(height: 10),
              Row(children: [
                _PrefChip(label: 'Email', selected: _loginPref == LoginPreference.email,
                    color: AppColors.secondary,
                    onTap: () => setState(() => _loginPref = LoginPreference.email)),
                const SizedBox(width: 12),
                _PrefChip(label: 'Mobile Number', selected: _loginPref == LoginPreference.mobile,
                    color: AppColors.secondary,
                    onTap: () => setState(() => _loginPref = LoginPreference.mobile)),
              ]),
              const SizedBox(height: 32),

              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: (_isLoading || !_isFormValid) ? null : _signup,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    disabledBackgroundColor:
                        AppColors.secondary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text('Create Admin Account',
                          style: AppTypography.labelLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 24),

              // ── Already have an account? ─────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: AppTypography.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Text(
                      'Sign in',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Local helpers ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1,
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4))),
    ]);
  }
}

class _GenderDropdown extends StatelessWidget {
  const _GenderDropdown({required this.value, required this.onChanged, this.enabled = true});
  final String value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          onChanged: enabled ? onChanged : null,
          style: AppTypography.bodyLarge.copyWith(color: colorScheme.onSurface),
          dropdownColor: colorScheme.surface,
          items: const [
            DropdownMenuItem(value: 'Male', child: Text('Male')),
            DropdownMenuItem(value: 'Female', child: Text('Female')),
            DropdownMenuItem(value: 'Other', child: Text('Other')),
            DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
          ],
        ),
      ),
    );
  }
}

class _PrefChip extends StatelessWidget {
  const _PrefChip({required this.label, required this.selected, required this.onTap, required this.color});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : colorScheme.outlineVariant,
              width: selected ? 1.5 : 1),
        ),
        child: Text(label, style: AppTypography.labelMedium.copyWith(
          color: selected ? color : colorScheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        )),
      ),
    );
  }
}
