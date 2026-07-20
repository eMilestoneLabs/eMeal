import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/shared/widgets/cached_photo.dart';

/// ISSUE-003: the ONE avatar widget used everywhere a user identity appears
/// (profile, More, member lists, attendance rosters, dashboards, billing).
///
/// Rendering priority — always consistent, always fast:
///   1. [bytes]   — locally picked image (own profile, instant, no network)
///   2. [avatarUrl] — served through [CachedPhoto] with the ~320px thumbnail
///      variant + on-disk cache, so lists render instantly after first fetch
///   3. Initials fallback (same look as the previous per-screen fallbacks)
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.bytes,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
    this.onTap,
  });

  /// Display name — used for the initials fallback.
  final String name;

  /// Network avatar URL (MinIO). Null/non-http → initials fallback.
  final String? avatarUrl;

  /// Local bytes (own session's freshly picked image) — highest priority.
  final Uint8List? bytes;

  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final VoidCallback? onTap;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
  }

  bool get _hasImage =>
      bytes != null ||
      (avatarUrl != null &&
          (avatarUrl!.startsWith('http://') ||
              avatarUrl!.startsWith('https://')));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark
            ? AppColors.primary.withValues(alpha: 0.25)
            : AppColors.primaryContainer);
    final fg = foregroundColor ??
        (isDark ? AppColors.primaryLight : AppColors.primary);
    final size = radius * 2;

    final fallback = Center(
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: radius * (_initials.length == 2 ? 0.72 : 0.9),
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );

    final child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: _hasImage
          ? CachedPhoto(
              bytes: bytes,
              url: avatarUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Decode at ~2x the on-screen size — crisp on high-DPI, tiny in
              // memory (a 40px avatar decodes ≤ 160px instead of full-res).
              cacheWidth: (size * 4).round(),
              useThumbnail: true,
              placeholder: fallback,
            )
          : fallback,
    );

    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }
}
