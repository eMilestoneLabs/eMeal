import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

// ── AuthInputField ─────────────────────────────────────────────────────────────

/// Premium animated input field used across all auth screens.
///
/// Features:
/// - Animated border color on focus (primary color glow)
/// - Floating label that slides up on focus/fill
/// - Suffix icon slot (show/hide password, clear, etc.)
/// - Inline error message with smooth appearance
/// - Disabled state styling
/// - Keyboard type + input formatter support
class AuthInputField extends StatefulWidget {
  const AuthInputField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.focusNode,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.enabled = true,
    this.errorText,
    this.suffixIcon,
    this.prefixIcon,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.maxLength,
    this.autofocus = false,
    this.autocorrect = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final bool enabled;
  final String? errorText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final bool autofocus;
  final bool autocorrect;
  final TextCapitalization textCapitalization;

  @override
  State<AuthInputField> createState() => _AuthInputFieldState();
}

class _AuthInputFieldState extends State<AuthInputField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _borderController;
  late final FocusNode _focus;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _focus.addListener(_onFocusChange);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _onFocusChange() {
    setState(() => _hasFocus = _focus.hasFocus);
    if (_focus.hasFocus) {
      _borderController.forward();
    } else {
      _borderController.reverse();
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    _borderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    final accentColor = colorScheme.primary;
    final borderColor = hasError
        ? colorScheme.error
        : _hasFocus
            ? accentColor
            : (isDark
                ? AppColors.glassBorderDark.withValues(alpha: 0.45)
                : colorScheme.outlineVariant);

    return AnimatedBuilder(
      animation: _borderController,
      builder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Field container with glow ────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              // Clean surface that sits well inside a parent glass card
              color: widget.enabled
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.09)
                      : colorScheme.surface)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: _hasFocus && !hasError ? 1.8 : 1.2,
              ),
              // Glow that fades in on focus
              boxShadow: [
                if (_hasFocus && !hasError)
                  BoxShadow(
                    color: accentColor.withValues(
                        alpha: 0.10 + 0.08 * _borderController.value),
                    blurRadius: 16,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: isDark ? 0.22 * _borderController.value : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              obscureText: widget.obscureText,
              enabled: widget.enabled,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              inputFormatters: widget.inputFormatters,
              maxLength: widget.maxLength,
              autocorrect: widget.autocorrect,
              textCapitalization: widget.textCapitalization,
              style: AppTypography.bodyLarge.copyWith(
                color: widget.enabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                labelStyle: AppTypography.bodyMedium.copyWith(
                  color: hasError
                      ? colorScheme.error
                      : _hasFocus
                          ? accentColor
                          : colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.80),
                ),
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color:
                      colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        child: widget.prefixIcon,
                      )
                    : null,
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                suffixIcon: widget.suffixIcon,
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                counterText: '',
                filled: false,
              ),
            ),
          ),

          // ── Error message ────────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: hasError
                ? Padding(
                    padding: const EdgeInsets.only(left: 4, top: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 13,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.errorText!,
                            style: AppTypography.labelSmall.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── PasswordField ──────────────────────────────────────────────────────────────

/// [AuthInputField] configured for password entry with show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    this.label = 'Password',
    this.controller,
    this.focusNode,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
    this.enabled = true,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final bool enabled;
  final bool autofocus;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return AuthInputField(
      label: widget.label,
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      errorText: widget.errorText,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      suffixIcon: PasswordVisibilityButton(
        obscured: _obscure,
        enabled: widget.enabled,
        onToggle: () => setState(() => _obscure = !_obscure),
      ),
    );
  }
}

// ── PasswordVisibilityButton ───────────────────────────────────────────────────

/// Live-Test-14 ISSUE-002(i): the industry-standard show/hide-password control,
/// as ONE shared widget so every password field in the app looks and behaves
/// identically (login, both signups, event-admin signup, reset, delete-account).
///
/// It replaced a bare `GestureDetector(child: Icon(...))`, which had three real
/// problems: the tap target was the glyph only (~20 px — below the 44 px
/// accessibility floor and genuinely hard to hit), there was no press feedback
/// or tooltip, and the flat icon read as decoration rather than a button. This
/// is a proper 40 px circular ink-splash button with a tinted primary surface
/// while revealed, a cross-faded + subtly scaled icon swap, and semantics so
/// screen readers announce it.
class PasswordVisibilityButton extends StatelessWidget {
  const PasswordVisibilityButton({
    super.key,
    required this.obscured,
    required this.onToggle,
    this.enabled = true,
  });

  /// True while the password is masked (the eye offers "show").
  final bool obscured;
  final VoidCallback onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Revealed state is visually "active" — a tinted primary chip — so the user
    // can always tell at a glance whether their password is on screen.
    final iconColor = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
        : obscured
            ? colorScheme.onSurfaceVariant
            : colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      // Tooltip already publishes its message as the semantics label and InkWell
      // already marks itself as a button, so no extra Semantics wrapper — one
      // would make a screen reader announce the control twice.
      child: Tooltip(
        message: obscured ? 'Show password' : 'Hide password',
        child: Material(
          color: obscured || !enabled
              ? Colors.transparent
              : colorScheme.primary.withValues(alpha: 0.10),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onToggle : null,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.80, end: 1)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                  child: Icon(
                    obscured
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    // Keyed so AnimatedSwitcher treats the swap as a new
                    // child (same widget type, different glyph).
                    key: ValueKey<bool>(obscured),
                    size: 20,
                    color: iconColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
