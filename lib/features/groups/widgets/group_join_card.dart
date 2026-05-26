import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Code-entry card component for joining a group.
///
/// Contains a 6-character text field with uppercase formatting, a Join button,
/// and optional error display.
class GroupJoinCard extends StatefulWidget {
  const GroupJoinCard({
    super.key,
    required this.onJoin,
    this.isLoading = false,
    this.errorText,
    this.controller,
  });

  /// Called with the trimmed uppercase 6-char code when Join is pressed.
  final ValueChanged<String> onJoin;
  final bool isLoading;
  final String? errorText;
  final TextEditingController? controller;

  @override
  State<GroupJoinCard> createState() => _GroupJoinCardState();
}

class _GroupJoinCardState extends State<GroupJoinCard> {
  late final TextEditingController _ctrl;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ctrl = TextEditingController();
      _ownsController = true;
    } else {
      _ctrl = widget.controller!;
    }
    _ctrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_rebuild);
    if (_ownsController) _ctrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _ctrl.text.trim().length == 6 && !widget.isLoading;

  void _submit() {
    if (!_canSubmit) return;
    widget.onJoin(_ctrl.text.trim().toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.errorText != null
              ? colorScheme.error.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter Join Code',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Ask your admin for the 6-character group code.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // Code input
          TextField(
            controller: _ctrl,
            enabled: !widget.isLoading,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            keyboardType: TextInputType.text,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              _UpperCaseFormatter(),
            ],
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'XXXXXX',
              hintStyle: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w400,
                letterSpacing: 8,
                color: colorScheme.onSurface.withValues(alpha: 0.25),
              ),
              errorText: widget.errorText,
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),

          // Join button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: widget.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Join Group',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forces all input to uppercase.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
