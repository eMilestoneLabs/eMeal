import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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

  bool get _hasNetwork =>
      url != null &&
      (url!.startsWith('http://') || url!.startsWith('https://'));

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
      return CachedNetworkImage(
        imageUrl: url!,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: cacheWidth,
        placeholder:
            placeholder == null ? null : (_, _) => placeholder!,
        errorWidget: (_, _, _) => placeholder ?? const SizedBox.shrink(),
      );
    }
    return placeholder ?? const SizedBox.shrink();
  }
}
