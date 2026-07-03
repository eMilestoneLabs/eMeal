/// FR-NAME-001 (ISSUE-3): safe member-name rendering.
///
/// All member-facing names resolve from the canonical `User.name` server-side;
/// this helper is the client-side guard — a null/empty/whitespace name renders
/// the safe placeholder "Member", never "null", a blank, or a raw user id.
library;

/// Returns [name] when it has visible content, otherwise the safe placeholder.
String displayMemberName(String? name, {String placeholder = 'Member'}) {
  if (name == null) return placeholder;
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return placeholder;
  return trimmed;
}
