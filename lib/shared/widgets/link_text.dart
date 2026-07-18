import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// LinkText — renders [text] with every URL automatically turned into a
/// tappable hyperlink (Live-Test-10 ISSUE-002).
///
/// Detects `https://…`, `http://…` and `www.…` tokens; `www.` links open with
/// an implied `https://`. Trailing punctuation (`.,;:!?)]…`) is excluded from
/// the tap target so links at the end of a sentence still resolve. Invalid or
/// unopenable links fail silently (best-effort, never a crash).
///
/// Purely additive: with no URLs present the output is identical to a plain
/// [Text] with the same [style]. Link colour defaults to the theme primary so
/// it stays legible in BOTH light and dark mode.
class LinkText extends StatefulWidget {
  const LinkText(
    this.text, {
    super.key,
    this.style,
    this.linkColor,
  });

  final String text;
  final TextStyle? style;

  /// Overrides the link colour (defaults to the theme's primary colour).
  final Color? linkColor;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  /// URL tokens: explicit scheme or a bare `www.` host.
  static final RegExp _urlPattern = RegExp(
    r'(https?:\/\/[^\s<>]+|www\.[^\s<>]+)',
    caseSensitive: false,
  );

  /// Punctuation that commonly trails a URL in prose but is not part of it.
  static final RegExp _trailingPunctuation = RegExp(r'[.,;:!?)\]}>' "'" r'"]+$');

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  static Future<void> _open(String rawUrl) async {
    final normalized =
        rawUrl.startsWith('www.') ? 'https://$rawUrl' : rawUrl;
    final uri = Uri.tryParse(normalized);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort — an unopenable link is not a crash.
    }
  }

  List<InlineSpan> _buildSpans(TextStyle? base, Color linkColor) {
    // Recognizers are rebuilt each build; dispose the previous generation so
    // nothing leaks across setState/theme changes.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final spans = <InlineSpan>[];
    final linkStyle = (base ?? const TextStyle()).copyWith(
      color: linkColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );

    var cursor = 0;
    for (final match in _urlPattern.allMatches(widget.text)) {
      var url = match.group(0)!;
      // Peel trailing punctuation off the link (it stays as plain text).
      final trail = _trailingPunctuation.firstMatch(url)?.group(0) ?? '';
      if (trail.isNotEmpty) url = url.substring(0, url.length - trail.length);
      if (url.isEmpty || (url.startsWith('www.') && url.length <= 4)) {
        continue;
      }
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: url, style: linkStyle, recognizer: recognizer));
      if (trail.isNotEmpty) spans.add(TextSpan(text: trail));
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final linkColor = widget.linkColor ?? Theme.of(context).colorScheme.primary;
    if (!_urlPattern.hasMatch(widget.text)) {
      return Text(widget.text, style: widget.style);
    }
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: _buildSpans(widget.style, linkColor),
      ),
    );
  }
}
