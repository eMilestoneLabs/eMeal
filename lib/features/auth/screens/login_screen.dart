import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';

import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';
import 'package:smart_meal_management/features/auth/widgets/auth_input_field.dart';

// ── LoginScreen ────────────────────────────────────────────────────────────────

/// Premium responsive login screen.
///
/// Architecture:
///   • `resizeToAvoidBottomInset: false` — background stays fixed when keyboard opens
///   • `SingleChildScrollView` + `ConstrainedBox` — proper keyboard-safe scrolling
///   • `MediaQuery.viewInsetsOf` — dynamic bottom padding for keyboard
///   • Animated floating blobs — subtle ambient motion on the gradient background
///   • Glass form card — `BackdropFilter` at card level; fields are clean inside
///   • Back button — `context.canPop()` fallback to `/role-select`
///
/// Role theming: student=indigo, admin=emerald, event=violet/pink.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.roleContext});

  /// One of: `'student'`, `'admin'`, `'event'`
  final String roleContext;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  // ── Form state ─────────────────────────────────────────────────────────────
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl   = TextEditingController();
  final _identifierFocus = FocusNode();
  final _passwordFocus   = FocusNode();

  String? _identifierError;
  String? _passwordError;
  String? _globalError;
  bool _isLoading = false;

  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final AnimationController _blobCtrl;

  late final Animation<double> _backFade;
  late final Animation<double> _brandFade;
  late final Animation<Offset> _brandSlide;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;
  late final Animation<double> _blobFloat; // 0→1, repeating

  // ── Init ───────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 860),
    );
    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    _backFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.00, 0.45, curve: Curves.easeOut),
    );
    _brandFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.08, 0.62, curve: Curves.easeOut),
    );
    _brandSlide = Tween<Offset>(
      begin: const Offset(0, -0.022),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.08, 0.65, curve: Curves.easeOut),
    ));
    _formFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.32, 0.95, curve: Curves.easeOut),
    );
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.042),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.38, 1.0, curve: Curves.easeOut),
    ));
    _blobFloat = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut),
    );

    _entryCtrl.forward();
    _restorePreference();
  }

  Future<void> _restorePreference() async {
    final remembered =
        await AuthStorageService.instance.loadRememberedIdentifier();
    if (!mounted || remembered == null) return;
    _identifierCtrl.text = remembered;
    setState(() {});
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _blobCtrl.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _identifierFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ── Role theming ───────────────────────────────────────────────────────────

  Color get _accentColor => switch (widget.roleContext) {
        'admin' => AppColors.secondary,
        'event' => AppColors.vacation,
        _ => AppColors.primary,
      };

  List<Color> get _gradient => switch (widget.roleContext) {
        'admin' => const [Color(0xFF059669), Color(0xFF0EA5E9)],
        'event' => const [AppColors.vacation, AppColors.gradientPurple],
        _ => const [AppColors.primary, AppColors.gradientEnd],
      };

  String get _roleLabel => switch (widget.roleContext) {
        'admin' => 'Admin / Manager',
        'event' => 'Event Admin',
        _ => 'Student / Member',
      };

  IconData get _roleIcon => switch (widget.roleContext) {
        'admin' => Icons.dashboard_customize_rounded,
        'event' => Icons.celebration_rounded,
        _ => Icons.school_rounded,
      };

  // ── Navigation ─────────────────────────────────────────────────────────────

  /// Safe back — pops if stack exists, otherwise goes to role-select.
  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.roleSelect);
    }
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  bool _validate() {
    bool valid = true;
    setState(() {
      _identifierError = _passwordError = _globalError = null;
      final id = _identifierCtrl.text.trim();
      if (id.isEmpty) {
        _identifierError = 'Enter your email or mobile number';
        valid = false;
      } else if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(id) &&
          !RegExp(r'^\+?[\d\s\-]{10,13}$')
              .hasMatch(id.replaceAll(' ', ''))) {
        _identifierError = 'Enter a valid email or 10-digit mobile';
        valid = false;
      }
      if (_passwordCtrl.text.isEmpty) {
        _passwordError = 'Enter your password';
        valid = false;
      }
    });
    return valid;
  }

  TextInputType get _identifierKeyboardType {
    final text = _identifierCtrl.text;
    if (text.isEmpty) return TextInputType.emailAddress;
    return RegExp(r'^\d').hasMatch(text)
        ? TextInputType.phone
        : TextInputType.emailAddress;
  }

  // ── Auth actions ───────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);

    final auth = AuthProviderScope.of(context);
    final identifier = _identifierCtrl.text.trim();

    final error = await auth.login(
      identifier: identifier,
      password: _passwordCtrl.text,
      roleContext: widget.roleContext,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      setState(() => _globalError = error);
      return;
    }

    await AuthStorageService.instance
        .saveRememberedIdentifier(identifier);
    if (!mounted) return;

    final user = auth.currentUser;
    if (user == null) return;
    if (user.role.isAdminGroup) {
      context.go(RouteNames.adminDashboard);
    } else if (user.role.isEventGroup) {
      context.go(RouteNames.eventAdminDashboard);
    } else {
      context.go(RouteNames.studentDashboard);
    }
  }

  void _goOtp() {
    final id = _identifierCtrl.text.trim();
    if (id.isEmpty) {
      setState(() =>
          _identifierError = 'Enter your email to receive an OTP');
      return;
    }
    // AUTH-015/016/SEC-008: OTP login is Email-only in this release. Mobile OTP
    // is "Coming Soon", so a non-email identifier is gated here with a clear
    // message instead of a backend rejection.
    final isEmail = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(id);
    if (!isEmail) {
      setState(() => _identifierError =
          'Mobile OTP is coming soon. Use email OTP or sign in with your password.');
      return;
    }
    context.push(
      RouteNames.otp,
      extra: OtpRouteExtra(
        identifier: id,
        roleContext: widget.roleContext,
        purpose: 'login',
      ),
    );
  }

  void _goSignup() {
    switch (widget.roleContext) {
      case 'admin':
        context.push(RouteNames.adminSignup);
      case 'event':
        context.push(RouteNames.eventSignup);
      default:
        context.push(RouteNames.studentSignup);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    // Part 2 §4 / FV-004: Sign In stays disabled until both fields are filled.
    final canSubmit = _identifierCtrl.text.trim().isNotEmpty &&
        _passwordCtrl.text.isNotEmpty;

    return Scaffold(
      // Keep background fixed — keyboard handled via viewInsetsOf
      resizeToAvoidBottomInset: false,
      backgroundColor:
          isDark ? AppColors.backgroundDark : _gradient[0],
      body: Stack(
        children: [
          // ── Animated full-screen background (fixed) ────────────────────
          // RepaintBoundary isolates blob repaints from the foreground layer,
          // preventing the entire scaffold from being re-rasterized each frame.
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _blobFloat,
                builder: (_, _) => _LoginBackground(
                  gradient: _gradient,
                  isDark: isDark,
                  blobValue: _blobFloat.value,
                ),
              ),
            ),
          ),

          // ── Scrollable foreground ──────────────────────────────────────
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  left: 22,
                  right: 22,
                  bottom: bottomInset > 0 ? bottomInset + 16 : 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        // Back button
                        FadeTransition(
                          opacity: _backFade,
                          child: _BackRow(onBack: _handleBack),
                        ),

                        const SizedBox(height: 18),

                        // Brand hero (icon, role badge, title)
                        FadeTransition(
                          opacity: _brandFade,
                          child: SlideTransition(
                            position: _brandSlide,
                            child: _BrandHero(
                              icon: _roleIcon,
                              roleLabel: _roleLabel,
                              accentColor: _accentColor,
                              gradient: _gradient,
                            ),
                          ),
                        ),

                        const SizedBox(height: 26),

                        // Glass form card
                        FadeTransition(
                          opacity: _formFade,
                          child: SlideTransition(
                            position: _formSlide,
                            child: _GlassCard(
                              isDark: isDark,
                              accentColor: _accentColor,
                              child: _LoginFormFields(
                                identifierCtrl: _identifierCtrl,
                                passwordCtrl: _passwordCtrl,
                                identifierFocus: _identifierFocus,
                                passwordFocus: _passwordFocus,
                                identifierError: _identifierError,
                                passwordError: _passwordError,
                                globalError: _globalError,
                                isLoading: _isLoading,
                                canSubmit: canSubmit,
                                accentColor: _accentColor,
                                gradient: _gradient,
                                identifierKeyboardType:
                                    _identifierKeyboardType,
                                isDark: isDark,
                                colorScheme: colorScheme,
                                onIdentifierChanged: (_) => setState(
                                    () => _identifierError = null),
                                onPasswordChanged: (_) => setState(
                                    () => _passwordError = null),
                                onIdentifierSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                                onPasswordSubmitted: (_) => _login(),
                                onLogin: _login,
                                onOtp: _goOtp,
                                onForgotPassword: () => context.push(
                                  RouteNames.forgotPassword,
                                  extra: widget.roleContext,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Create account footer
                        FadeTransition(
                          opacity: _formFade,
                          child: _SignupFooter(
                            isDark: isDark,
                            accentColor: _accentColor,
                            isLoading: _isLoading,
                            onSignup: _goSignup,
                          ),
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated background ───────────────────────────────────────────────────────

class _LoginBackground extends StatelessWidget {
  const _LoginBackground({
    required this.gradient,
    required this.isDark,
    required this.blobValue,
  });

  final List<Color> gradient;
  final bool isDark;
  final double blobValue; // 0..1

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Stack(
      children: [
        // Base gradient (full screen)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),

        // ── Top-right large orb — floats slowly ──────────────────────────
        Positioned(
          top: -75 + 26 * blobValue,
          right: -85 + 18 * (1 - blobValue),
          child: Container(
            width: 310,
            height: 310,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white
                      .withValues(alpha: 0.24 + 0.07 * blobValue),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── Bottom-left orb — floats opposite ────────────────────────────
        Positioned(
          bottom: -65 + 22 * (1 - blobValue),
          left: -75 + 18 * blobValue,
          child: Container(
            width: 270,
            height: 270,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(
                      alpha: 0.17 + 0.07 * (1 - blobValue)),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── Mid-screen accent orb ─────────────────────────────────────────
        Positioned(
          top: size.height * 0.32 + 18 * blobValue,
          right: size.width * 0.15 + 10 * (1 - blobValue),
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(
                      alpha: 0.09 + 0.04 * blobValue),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // ── Diagonal shimmer stripe ───────────────────────────────────────
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.04),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Back row ───────────────────────────────────────────────────────────────

class _BackRow extends StatelessWidget {
  const _BackRow({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Brand hero ─────────────────────────────────────────────────────────────

class _BrandHero extends StatelessWidget {
  const _BrandHero({
    required this.icon,
    required this.roleLabel,
    required this.accentColor,
    required this.gradient,
  });

  final IconData icon;
  final String roleLabel;
  final Color accentColor;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.30),
            ),
          ),
          child: Icon(icon, size: 30, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
          child: Text(
            roleLabel,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Welcome back',
          style: AppTypography.headlineMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in to continue',
          style: AppTypography.bodyMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.80),
          ),
        ),
      ],
    );
  }
}

// ── Glass card wrapper ─────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.isDark,
    required this.accentColor,
    required this.child,
  });

  final bool isDark;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.09)
                : Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.80),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Login form fields ──────────────────────────────────────────────────────

class _LoginFormFields extends StatelessWidget {
  const _LoginFormFields({
    required this.identifierCtrl,
    required this.passwordCtrl,
    required this.identifierFocus,
    required this.passwordFocus,
    required this.identifierError,
    required this.passwordError,
    required this.globalError,
    required this.isLoading,
    required this.canSubmit,
    required this.accentColor,
    required this.gradient,
    required this.identifierKeyboardType,
    required this.isDark,
    required this.colorScheme,
    required this.onIdentifierChanged,
    required this.onPasswordChanged,
    required this.onIdentifierSubmitted,
    required this.onPasswordSubmitted,
    required this.onLogin,
    required this.onOtp,
    required this.onForgotPassword,
  });

  final TextEditingController identifierCtrl;
  final TextEditingController passwordCtrl;
  final FocusNode identifierFocus;
  final FocusNode passwordFocus;
  final String? identifierError;
  final String? passwordError;
  final String? globalError;
  final bool isLoading;
  final bool canSubmit;
  final Color accentColor;
  final List<Color> gradient;
  final TextInputType identifierKeyboardType;
  final bool isDark;
  final ColorScheme colorScheme;
  final ValueChanged<String> onIdentifierChanged;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onIdentifierSubmitted;
  final ValueChanged<String> onPasswordSubmitted;
  final VoidCallback onLogin;
  final VoidCallback onOtp;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.88)
        : colorScheme.onSurface;
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : colorScheme.onSurface.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Sign in',
            style: AppTypography.titleLarge.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Email or mobile number',
            style: AppTypography.bodySmall.copyWith(color: subtitleColor),
          ),
          const SizedBox(height: 20),
          AuthInputField(
            label: 'Email or Mobile',
            controller: identifierCtrl,
            focusNode: identifierFocus,
            keyboardType: identifierKeyboardType,
            textInputAction: TextInputAction.next,
            errorText: identifierError,
            onChanged: onIdentifierChanged,
            onSubmitted: onIdentifierSubmitted,
          ),
          const SizedBox(height: 14),
          AuthInputField(
            label: 'Password',
            controller: passwordCtrl,
            focusNode: passwordFocus,
            obscureText: true,
            textInputAction: TextInputAction.done,
            errorText: passwordError,
            onChanged: onPasswordChanged,
            onSubmitted: onPasswordSubmitted,
          ),
          // Forgot password link
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : onForgotPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot password?',
                style: AppTypography.labelSmall.copyWith(
                  color: subtitleColor,
                  decoration: TextDecoration.underline,
                  decorationColor: subtitleColor,
                ),
              ),
            ),
          ),
          if (globalError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      globalError!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _GradientButton(
            gradient: gradient,
            label: 'Sign In',
            onPressed: (isLoading || !canSubmit) ? null : onLogin,
            isLoading: isLoading,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: isLoading ? null : onOtp,
            style: TextButton.styleFrom(
              foregroundColor: accentColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: accentColor.withValues(alpha: 0.35),
                ),
              ),
            ),
            child: Text(
              'Sign in with OTP',
              style: AppTypography.bodyMedium.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gradient CTA button ────────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.gradient,
    required this.label,
    required this.onPressed,
    required this.isLoading,
  });

  final List<Color> gradient;
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // Premium disabled state (Issue 3): a frosted pill with a visible border and
    // a dimmed label — clearly a button, clearly inactive, in both themes.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? LinearGradient(colors: gradient) : null,
        color: enabled ? null : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: enabled
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: gradient.last.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white
                            .withValues(alpha: enabled ? 1.0 : 0.6),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Signup footer ──────────────────────────────────────────────────────────

// ── Signup footer ──────────────────────────────────────────────────────────

class _SignupFooter extends StatelessWidget {
  const _SignupFooter({
    required this.isDark,
    required this.accentColor,
    required this.isLoading,
    required this.onSignup,
  });

  final bool isDark;
  final Color accentColor;
  final bool isLoading;
  final VoidCallback onSignup;

  @override
  Widget build(BuildContext context) {
    // Background in light mode is always the role gradient (indigo/emerald/violet),
    // so white text is required for contrast — exactly like _BrandHero and _BackRow.
    // In dark mode, use the standard secondary text tokens.
    final textColor = isDark
        ? AppColors.textSecondaryDark
        : Colors.white.withValues(alpha: 0.80);
    final linkColor = isDark ? accentColor : Colors.white;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: AppTypography.bodySmall.copyWith(color: textColor),
        ),
        GestureDetector(
          onTap: isLoading ? null : onSignup,
          child: Text(
            'Sign up',
            style: AppTypography.bodySmall.copyWith(
              color: linkColor,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: linkColor,
            ),
          ),
        ),
      ],
    );
  }
}
