import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Displays an image from local [bytes] (a just-picked image or a base64 data
/// URI already decoded) when available, otherwise from a network [url] with
/// on-disk caching — the image is fetched once and then served from cache on
/// every later build (replaces `Image.network`, which re-downloads each time).
///
/// Shows [placeholder] while the network image loads, on error, and when there
/// is neither bytes nor a usable http(s) url. Purely additive: callers that only
/// ever pass [bytes] keep identical behaviour to a bare `Image.memory`.
class CachedPhoto extends StatelessWidget {
  const CachedPhoto({
    super.key,
    this.bytes,
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.placeholder,
    this.useThumbnail = false,
  });

  /// Local image bytes (highest priority — admin's own session / base64).
  final Uint8List? bytes;

  /// Network image URL (used when [bytes] is null). Only http(s) is loaded.
  final String? url;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// Decode width hint to cap memory use (maps to memCacheWidth for network).
  final int? cacheWidth;

  /// Shown while loading, on error, or when there is no image.
  final Widget? placeholder;

  /// When true and [url] is a stored image, load the ~320px thumbnail variant
  /// (≈15 KB) for fast list/grid rendering, falling back to the full image if
  /// the thumbnail does not exist (e.g. older uploads).
  final bool useThumbnail;

  bool get _hasNetwork =>
      url != null &&
      (url!.startsWith('http://') || url!.startsWith('https://'));

  /// Derives the thumbnail URL by the backend's naming convention
  /// (`<name>.<ext>` -> `<name>_thumb.jpg`).
  String _thumbUrl(String u) => u.replaceFirst(RegExp(r'\.\w+$'), '_thumb.jpg');

  Widget _networkImage(String imageUrl, {Widget Function()? onError}) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      // Snap the image in instead of the default 500ms fade.
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 120),
      // Loading state: caller's placeholder, else a shimmer skeleton sized to
      // the image footprint (never a blank box). Error keeps the caller's
      // placeholder/fallback semantics unchanged — loading ≠ error UI.
      placeholder: (_, _) =>
          placeholder ?? _ImageSkeleton(width: width, height: height),
      errorWidget: (_, _, _) =>
          onError != null ? onError() : (placeholder ?? const SizedBox.shrink()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(
        bytes!,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
      );
    }
    if (_hasNetwork) {
      final original = url!;
      if (useThumbnail) {
        // Thumb first; on miss (404 / older upload) fall back to the original.
        return _networkImage(_thumbUrl(original),
            onError: () => _networkImage(original));
      }
      return _networkImage(original);
    }
    return placeholder ?? const SizedBox.shrink();
  }
}

/// Default loading placeholder for [CachedPhoto]: a soft shimmer block that
/// fills the image footprint (clipped by whatever shape the caller applies —
/// avatar circle, card radius, banner). Fades out when the image fades in.
class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        width: width,
        height: height,
        color: AppColors.surfaceVariant,
      ),
    );
  }
}
