import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';
import 'package:smart_meal_management/features/auth/widgets/auth_input_field.dart';
import 'package:smart_meal_management/features/auth/widgets/password_strength_indicator.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

// ── StudentSignupScreen ────────────────────────────────────────────────────────

/// Signup screen for student, member, and guest roles.
///
/// All fields are validated inline — no dialog errors.
/// On success: navigates to student dashboard (or group-join if no group).
class StudentSignupScreen extends StatefulWidget {
  const StudentSignupScreen({super.key});

  @override
  State<StudentSignupScreen> createState() => _StudentSignupScreenState();
}

class _StudentSignupScreenState extends State<StudentSignupScreen> {
  // Controllers
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();

  // Focus nodes
  final _nameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _ageFocus = FocusNode();

  // Dropdown state
  UserRole _role = UserRole.student;
  String _gender = 'Prefer not to say';
  LoginPreference _loginPref = LoginPreference.email;

  // Errors
  String? _nameError;
  String? _mobileError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _ageError;

  bool _isLoading = false;

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _mobileCtrl, _emailCtrl, _passwordCtrl, _confirmCtrl, _ageCtrl
    ]) { c.dispose(); }
    for (final f in [
      _nameFocus, _mobileFocus, _emailFocus, _passwordFocus, _confirmFocus, _ageFocus
    ]) { f.dispose(); }
    super.dispose();
  }

  bool _validate() {
    bool valid = true;
    setState(() {
      _nameError = _mobileError = _emailError =
          _passwordError = _confirmError = _ageError = null;

      if (_nameCtrl.text.trim().length < 2) {
        _nameError = 'Enter your full name';
        valid = false;
      }
      final phone = _mobileCtrl.text.trim();
      if (phone.isEmpty || !RegExp(r'^\d{10}$').hasMatch(phone)) {
        _mobileError = 'Enter a valid 10-digit mobile number';
        valid = false;
      }
      final email = _emailCtrl.text.trim();
      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
        _emailError = 'Enter a valid email address';
        valid = false;
      }
      if (_passwordCtrl.text.length < 6) {
        _passwordError = 'Password must be at least 6 characters';
        valid = false;
      }
      if (_confirmCtrl.text != _passwordCtrl.text) {
        _confirmError = 'Passwords do not match';
        valid = false;
      }
      final age = int.tryParse(_ageCtrl.text);
      if (age == null || age < 5 || age > 100) {
        _ageError = 'Enter a valid age (5–100)';
        valid = false;
      }
    });
    return valid;
  }

  Future<void> _signup() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);

    final auth = AuthProviderScope.of(context);
    final identifier = _loginPref == LoginPreference.email
        ? _emailCtrl.text.trim()
        : _mobileCtrl.text.trim();

    final error = await auth.signup(
      name: _nameCtrl.text.trim(),
      role: _role,
      mobile: _mobileCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      age: int.parse(_ageCtrl.text),
      gender: _gender,
      loginPreference: _loginPref,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      setState(() => _emailError = error);
      return;
    }

    await AuthStorageService.instance.saveLoginPreference(_loginPref);
    await AuthStorageService.instance.saveRememberedIdentifier(identifier);
    if (!mounted) return;
    context.go(RouteNames.studentDashboard);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Create Account',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section: Personal info
              const _SectionHeader(label: 'Personal Information'),
              const SizedBox(height: 16),

              AuthInputField(
                label: 'Full Name',
                controller: _nameCtrl,
                focusNode: _nameFocus,
                errorText: _nameError,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
                onChanged: (_) => setState(() => _nameError = null),
                onSubmitted: (_) => _mobileFocus.requestFocus(),
              ),
              const SizedBox(height: 14),

              // Role dropdown
              _DropdownField<UserRole>(
                label: 'Role',
                value: _role,
                enabled: !_isLoading,
                items: const [
                  DropdownMenuItem(
                      value: UserRole.student, child: Text('Student')),
                  DropdownMenuItem(
                      value: UserRole.member, child: Text('Member')),
                  DropdownMenuItem(
                      value: UserRole.guest, child: Text('Guest')),
                ],
                onChanged: (v) => setState(() => _role = v ?? UserRole.student),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: AuthInputField(
                      label: 'Age',
                      controller: _ageCtrl,
                      focusNode: _ageFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      errorText: _ageError,
                      enabled: !_isLoading,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 3,
                      onChanged: (_) => setState(() => _ageError = null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DropdownField<String>(
                      label: 'Gender',
                      value: _gender,
                      enabled: !_isLoading,
                      items: const [
                        DropdownMenuItem(
                            value: 'Male', child: Text('Male')),
                        DropdownMenuItem(
                            value: 'Female', child: Text('Female')),
                        DropdownMenuItem(
                            value: 'Other', child: Text('Other')),
                        DropdownMenuItem(
                            value: 'Prefer not to say',
                            child: Text('Prefer not to say')),
                      ],
                      onChanged: (v) =>
                          setState(() => _gender = v ?? 'Prefer not to say'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Section: Contact
              const _SectionHeader(label: 'Contact Details'),
              const SizedBox(height: 16),

              AuthInputField(
                label: 'Mobile Number',
                controller: _mobileCtrl,
                focusNode: _mobileFocus,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                errorText: _mobileError,
                enabled: !_isLoading,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                onChanged: (_) => setState(() => _mobileError = null),
                onSubmitted: (_) => _emailFocus.requestFocus(),
              ),
              const SizedBox(height: 14),

              AuthInputField(
                label: 'Email Address',
                controller: _emailCtrl,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                errorText: _emailError,
                enabled: !_isLoading,
                onChanged: (_) => setState(() => _emailError = null),
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 24),

              // Section: Security
              const _SectionHeader(label: 'Security'),
              const SizedBox(height: 16),

              PasswordField(
                controller: _passwordCtrl,
                focusNode: _passwordFocus,
                errorText: _passwordError,
                enabled: !_isLoading,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  setState(() => _passwordError = null);
                },
                onSubmitted: (_) => _confirmFocus.requestFocus(),
              ),

              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _passwordCtrl,
                builder: (_, value, _) => PasswordStrengthIndicator(
                  password: value.text,
                ),
              ),
              const SizedBox(height: 14),

              PasswordField(
                label: 'Confirm Password',
                controller: _confirmCtrl,
                focusNode: _confirmFocus,
                errorText: _confirmError,
                enabled: !_isLoading,
                onChanged: (_) => setState(() => _confirmError = null),
                onSubmitted: (_) => _signup(),
              ),
              const SizedBox(height: 24),

              // Section: Login preference
              const _SectionHeader(label: 'Login Preference'),
              const SizedBox(height: 8),
              Text(
                'How would you like to sign in next time?',
                style: AppTypography.bodySmall.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _PreferenceChip(
                    label: 'Email',
                    selected: _loginPref == LoginPreference.email,
                    onTap: () =>
                        setState(() => _loginPref = LoginPreference.email),
                  ),
                  const SizedBox(width: 12),
                  _PreferenceChip(
                    label: 'Mobile Number',
                    selected: _loginPref == LoginPreference.mobile,
                    onTap: () =>
                        setState(() => _loginPref = LoginPreference.mobile),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Submit
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isLoading ? null : _signup,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          'Create Account',
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Text(
                      'Sign in',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primary,
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

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: enabled ? onChanged : null,
          isExpanded: true,
          style: AppTypography.bodyLarge.copyWith(
            color: colorScheme.onSurface,
          ),
          dropdownColor: colorScheme.surface,
          hint: Text(label,
              style: AppTypography.bodyMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
              )),
        ),
      ),
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  const _PreferenceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color:
                selected ? AppColors.primary : colorScheme.onSurfaceVariant,
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
