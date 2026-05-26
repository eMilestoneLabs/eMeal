/// [String] extension helpers for the MealAttend app.
extension StringExt on String {
  /// Returns initials from a name string (up to 2 characters).
  String get initials {
    final parts = trim().split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Capitalises the first letter of the string.
  String get capitalised {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Converts "camelCase" or "snake_case" to "Title Case".
  String get titleCase {
    return split(RegExp(r'[_\s]'))
        .where((s) => s.isNotEmpty)
        .map((s) => s.capitalised)
        .join(' ');
  }

  /// True when this string is a valid email address.
  bool get isValidEmail {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(this);
  }

  /// Truncates the string to [maxLength] and appends "…" if truncated.
  String truncate(int maxLength) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}…';
  }
}
