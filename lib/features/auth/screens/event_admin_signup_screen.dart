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
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

// ── EventAdminSignupScreen ─────────────────────────────────────────────────────

/// Signup screen for the event admin role.
///
/// Two sections:
///   1. Personal — name, mobile, email, password
///   2. Event — event name, type, date picker, expected guest count,
///              auto-delete toggle (default: off — optional feature)
class EventAdminSignupScreen extends StatefulWidget {
  const EventAdminSignupScreen({super.key});

  @override
  State<EventAdminSignupScreen> createState() => _EventAdminSignupScreenState();
}

class _EventAdminSignupScreenState extends State<EventAdminSignupScreen> {
  // Personal
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  // Event
  final _eventNameCtrl = TextEditingController();
  final _guestCountCtrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _eventNameFocus = FocusNode();
  final _guestCountFocus = FocusNode();

  EventType _eventType = EventType.corporate;
  DateTime? _eventDate;
  bool _autoDelete = false;
  bool _isLoading = false;

  // Errors
  String? _nameError;
  String? _mobileError;
  String? _emailError;
  String? _passwordError;
  String? _eventNameError;
  String? _guestCountError;
  String? _eventDateError;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _mobileCtrl, _emailCtrl, _passwordCtrl, _eventNameCtrl, _guestCountCtrl]) { c.dispose(); }
    for (final f in [_nameFocus, _mobileFocus, _emailFocus, _passwordFocus, _eventNameFocus, _guestCountFocus]) { f.dispose(); }
    super.dispose();
  }

  bool get _guestCountValid {
    final n = int.tryParse(_guestCountCtrl.text);
    return n != null && n >= 1;
  }

  // FV-004: keep "Create" disabled until all mandatory fields are valid.
  bool get _isFormValid =>
      AuthValidators.name(_nameCtrl.text) == null &&
      AuthValidators.mobile(_mobileCtrl.text) == null &&
      AuthValidators.email(_emailCtrl.text) == null &&
      AuthValidators.password(_passwordCtrl.text) == null &&
      _eventNameCtrl.text.trim().length >= 2 &&
      _guestCountValid &&
      _eventDate != null;

  bool _validate() {
    setState(() {
      _nameError = AuthValidators.name(_nameCtrl.text);
      _mobileError = AuthValidators.mobile(_mobileCtrl.text);
      _emailError = AuthValidators.email(_emailCtrl.text);
      _passwordError = AuthValidators.password(_passwordCtrl.text);
      _eventNameError =
          _eventNameCtrl.text.trim().length >= 2 ? null : 'Enter a valid event name';
      _guestCountError = _guestCountValid ? null : 'Enter expected guest count';
      _eventDateError = _eventDate == null ? 'Select the event date' : null;
    });
    return _isFormValid;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _eventDate = picked;
        _eventDateError = null;
      });
    }
  }

  String get _formattedDate {
    if (_eventDate == null) return 'Select event date';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${_eventDate!.day} ${months[_eventDate!.month - 1]} ${_eventDate!.year}';
  }

  Future<void> _signup() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);

    final auth = AuthProviderScope.of(context);
    final error = await auth.signup(
      name: _nameCtrl.text.trim(),
      role: UserRole.eventAdmin,
      mobile: _mobileCtrl.text.trim(),
      email: _emailCtrl.text.trim().toLowerCase(),
      password: _passwordCtrl.text,
      loginPreference: LoginPreference.email,
      eventName: _eventNameCtrl.text.trim(),
      eventType: _eventType,
      eventDate: _eventDate!,
      expectedGuestCount: int.parse(_guestCountCtrl.text),
      autoDeleteEvent: _autoDelete,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) { setState(() => _emailError = error); return; }

    await AuthStorageService.instance.saveLoginPreference(LoginPreference.email);
    await AuthStorageService.instance.saveRememberedIdentifier(_emailCtrl.text.trim());
    if (!mounted) return;

    // AUTH-031/036/041: verify the emailed OTP, then continue to the event dashboard.
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty) {
      context.push(
        RouteNames.otp,
        extra: OtpRouteExtra(
          identifier: email,
          roleContext: 'event',
          purpose: 'signup',
          isSignup: true,
        ),
      );
    } else {
      context.go(RouteNames.eventAdminDashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const accentColor = AppColors.vacation;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: Text('Create Event Account', style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Personal section ─────────────────────────────────────────
              const _SectionLabel('Your Information', color: accentColor),
              const SizedBox(height: 16),

              AuthInputField(
                label: 'Full Name', controller: _nameCtrl, focusNode: _nameFocus,
                errorText: _nameError, textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next, enabled: !_isLoading,
                maxLength: 30,
                onChanged: (v) => setState(
                    () => _nameError = AuthValidators.live(v, AuthValidators.name)),
                onSubmitted: (_) => _mobileFocus.requestFocus(),
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 14),
              PasswordField(
                controller: _passwordCtrl, focusNode: _passwordFocus,
                errorText: _passwordError, enabled: !_isLoading,
                onChanged: (v) => setState(
                    () => _passwordError = AuthValidators.live(v, AuthValidators.password)),
                onSubmitted: (_) => _eventNameFocus.requestFocus(),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _passwordCtrl,
                builder: (_, v, _) => PasswordStrengthIndicator(password: v.text),
              ),
              const SizedBox(height: 28),

              // ── Event section ─────────────────────────────────────────────
              const _SectionLabel('Event Details', color: accentColor),
              const SizedBox(height: 16),

              AuthInputField(
                label: 'Event Name', controller: _eventNameCtrl, focusNode: _eventNameFocus,
                textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next,
                errorText: _eventNameError, enabled: !_isLoading,
                maxLength: 60,
                onChanged: (v) => setState(() => _eventNameError =
                    v.trim().isEmpty || v.trim().length >= 2 ? null : 'Enter a valid event name'),
                onSubmitted: (_) => _guestCountFocus.requestFocus(),
              ),
              const SizedBox(height: 14),

              // Event type dropdown
              _EventTypeDropdown(
                value: _eventType, enabled: !_isLoading,
                onChanged: (v) => setState(() => _eventType = v ?? EventType.corporate),
              ),
              const SizedBox(height: 14),

              // Date picker
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _isLoading ? null : _pickDate,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _eventDateError != null
                              ? colorScheme.error
                              : colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_rounded, size: 18,
                            color: _eventDate != null ? accentColor : colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Text(
                          _formattedDate,
                          style: AppTypography.bodyLarge.copyWith(
                            color: _eventDate != null
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ]),
                    ),
                  ),
                  if (_eventDateError != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 6),
                      child: Text(_eventDateError!,
                          style: AppTypography.labelSmall.copyWith(color: colorScheme.error)),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              AuthInputField(
                label: 'Expected Guest Count', controller: _guestCountCtrl, focusNode: _guestCountFocus,
                keyboardType: TextInputType.number, textInputAction: TextInputAction.done,
                errorText: _guestCountError, enabled: !_isLoading,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 6,
                onChanged: (_) => setState(() =>
                    _guestCountError = _guestCountCtrl.text.isEmpty || _guestCountValid
                        ? null
                        : 'Enter expected guest count'),
                onSubmitted: (_) => _signup(),
              ),
              const SizedBox(height: 16),

              // Auto-delete toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _autoDelete
                        ? accentColor.withValues(alpha: 0.35)
                        : colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Auto-delete event data',
                                  style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Text('Optional',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    )),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _autoDelete
                                ? 'Event data will be deleted after event date + 7 days'
                                : 'Event data will be kept until you manually delete it',
                            style: AppTypography.bodySmall.copyWith(
                                color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: _autoDelete,
                      onChanged: _isLoading ? null : (v) => setState(() => _autoDelete = v),
                      activeThumbColor: accentColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: (_isLoading || !_isFormValid) ? null : _signup,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    disabledBackgroundColor: accentColor.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text('Create Event Account',
                          style: AppTypography.labelLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
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
  const _SectionLabel(this.label, {required this.color});
  final String label;
  final Color color;

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

class _EventTypeDropdown extends StatelessWidget {
  const _EventTypeDropdown({required this.value, required this.onChanged, this.enabled = true});
  final EventType value;
  final ValueChanged<EventType?> onChanged;
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
        child: DropdownButton<EventType>(
          value: value, isExpanded: true,
          onChanged: enabled ? onChanged : null,
          style: AppTypography.bodyLarge.copyWith(color: colorScheme.onSurface),
          dropdownColor: colorScheme.surface,
          items: EventType.values.map((t) => DropdownMenuItem(
            value: t,
            child: Text('${t.emoji}  ${t.label}'),
          )).toList(),
        ),
      ),
    );
  }
}
