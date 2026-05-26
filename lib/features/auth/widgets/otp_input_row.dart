import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

// ── OtpInputRow ────────────────────────────────────────────────────────────────

/// A row of 6 individual digit boxes for OTP entry.
///
/// Features:
/// - Auto-advances focus to next box on digit entry
/// - Auto-retreats to previous box on backspace
/// - Calls [onCompleted] when all 6 digits are entered
/// - Animated border on focus + filled state
/// - Paste support: pasting a 6-digit string fills all boxes
class OtpInputRow extends StatefulWidget {
  const OtpInputRow({
    super.key,
    required this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.length = 6,
  });

  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final int length;

  @override
  State<OtpInputRow> createState() => _OtpInputRowState();
}

class _OtpInputRowState extends State<OtpInputRow> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
    // Auto-focus first box
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    super.dispose();
  }

  String get _currentOtp =>
      _controllers.map((c) => c.text).join();

  void _onDigitEntered(int index, String value) {
    if (value.length > 1) {
      // Handle paste — fill all boxes from pasted value
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < widget.length && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      if (digits.length >= widget.length) {
        _focusNodes[widget.length - 1].requestFocus();
        _notifyCompleted();
      } else {
        _focusNodes[digits.length].requestFocus();
      }
      setState(() {});
      return;
    }

    if (value.isNotEmpty) {
      // Single digit entered — advance
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _notifyCompleted();
      }
    }
    setState(() {});
    widget.onChanged?.call(_currentOtp);
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      setState(() {});
    }
  }

  void _notifyCompleted() {
    final otp = _currentOtp;
    if (otp.length == widget.length) {
      widget.onCompleted(otp);
    }
  }

  /// Clears all boxes and focuses first. Call from parent on error.
  void clear() {
    for (final c in _controllers) { c.clear(); }
    _focusNodes[0].requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (i) {
        final isLast = i == widget.length - 1;
        return Row(
          children: [
            _OtpBox(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              enabled: widget.enabled,
              onChanged: (v) => _onDigitEntered(i, v),
              onKeyEvent: (e) => _onKeyEvent(i, e),
            ),
            if (!isLast) const SizedBox(width: 10),
          ],
        );
      }),
    );
  }
}

// ── Single OTP box ─────────────────────────────────────────────────────────────

class _OtpBox extends StatefulWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onKeyEvent,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<KeyEvent> onKeyEvent;
  final bool enabled;

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      if (mounted) setState(() => _hasFocus = widget.focusNode.hasFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filled = widget.controller.text.isNotEmpty;

    return KeyboardListener(
      focusNode: FocusNode(skipTraversal: true),
      onKeyEvent: widget.onKeyEvent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 46,
        height: 56,
        decoration: BoxDecoration(
          color: filled
              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hasFocus
                ? colorScheme.primary
                : filled
                    ? colorScheme.primary.withValues(alpha: 0.4)
                    : colorScheme.outlineVariant,
            width: _hasFocus ? 2 : 1.2,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: widget.onChanged,
          style: AppTypography.titleLarge.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            counterText: '',
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
