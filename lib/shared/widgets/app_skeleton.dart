import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';

/// Premium Skeleton Loading System — the single source of truth for every
/// loading placeholder in the app.
///
/// Design rules (Global UI Improvement batch):
///   • Layout-stable: skeletons mirror the final layout (heights, radii,
///     spacing) so content never jumps when data lands.
///   • One animation controller per skeleton scope ([AppShimmer]) — a single
///     ShaderMask sweep, cheap on low-end devices.
///   • Honors `MediaQuery.disableAnimations` (accessibility / battery saver):
///     renders a calm static placeholder instead of animating.
///   • Light + dark aware via [Theme.brightness].
///   • Every composite fades in on mount so the loader itself never pops.
///
/// Composites (use these at call sites — one-liners):
///   [AppListSkeleton]      list/feed screens (solid rows or avatar rows)
///   [AppDashboardSkeleton] hero + stat grid + content cards
///   [AppDetailSkeleton]    header card + detail rows
///   [AppTableSkeleton]     header + data rows (sheets/reports/billing)
///   [AppFormSkeleton]      label + field pairs
///   [AppSheetSkeleton]     shrink-wrapped rows for bottom sheets
///   [AppChartSkeleton]     bar-chart placeholder card
///   [AppChipRowSkeleton]   horizontal selector chips (group pickers)
///   [AppProfileSkeleton]   centered avatar + identity lines + tiles
///
/// Primitives ([SkeletonBox], [SkeletonLine], [SkeletonCircle]) are exported
/// for bespoke skeletons; wrap them in an [AppShimmer].

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer scope
// ─────────────────────────────────────────────────────────────────────────────

/// Applies one soft shimmer sweep to every skeleton bone below it.
///
/// Implementation: a repeating [ShaderMask] linear-gradient translated across
/// the subtree with `BlendMode.srcATop`, so bones only need to be opaque
/// shapes on a transparent background. A single [AnimationController] powers
/// the whole scope regardless of how many bones it contains.
class AppShimmer extends StatefulWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  /// Sweep duration — slow and calm by design (no fast flashing).
  static const Duration period = Duration(milliseconds: 1600);

  /// Entrance fade so the skeleton itself never pops in.
  static const Duration entranceFade = Duration(milliseconds: 220);

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppShimmer.period,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant;
    final highlight =
        isDark ? AppColors.borderStrongDark : AppColors.surface;

    // Accessibility / battery saver: static placeholder, no animation.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppShimmer.entranceFade,
      curve: Curves.easeOut,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) {
            if (reduceMotion) {
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) => LinearGradient(
                  colors: [base, base],
                ).createShader(bounds),
                child: child,
              );
            }
            // Slide the highlight band from left of the box to its right.
            final t = _controller.value;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [base, highlight, base],
                stops: const [0.35, 0.5, 0.65],
                transform: _SlideGradientTransform(t * 3 - 1.5),
              ).createShader(bounds),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  const _SlideGradientTransform(this.percent);
  final double percent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * percent, 0, 0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Primitives
// ─────────────────────────────────────────────────────────────────────────────

/// Rounded rectangle bone. Colour is irrelevant (the shimmer gradient paints
/// over it) — it only needs to be opaque.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 12,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Text-line bone. [widthFactor] sizes it relative to the available width.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.widthFactor = 1,
    this.height = 12,
  });

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height, radius: height / 2),
    );
  }
}

/// Circular bone (avatars, icons).
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Composites
// ─────────────────────────────────────────────────────────────────────────────

/// Non-scrollable host for full-body skeletons: never overflows regardless of
/// row count or screen height, and never competes with the incoming
/// scrollable for gestures.
class _SkeletonHost extends StatelessWidget {
  const _SkeletonHost({required this.padding, required this.children});

  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        children: children,
      ),
    );
  }
}

/// List/feed placeholder.
///
/// [withAvatar] true → structured rows (circle + two text lines), matching
/// member/notice tiles. false → solid rounded blocks matching card rows.
/// [expand] false → shrink-wrapped Column for embedding inside an existing
/// scrollable (no nested ListView).
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({
    super.key,
    this.rows = 5,
    this.rowHeight = 76,
    this.spacing = 12,
    this.withAvatar = false,
    this.expand = true,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
    this.headerHeight,
  });

  final int rows;
  final double rowHeight;
  final double spacing;
  final bool withAvatar;
  final bool expand;
  final EdgeInsetsGeometry padding;

  /// Optional leading block (e.g. summary card) above the rows.
  final double? headerHeight;

  Widget _row() {
    if (!withAvatar) {
      return SkeletonBox(height: rowHeight, radius: 16);
    }
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          SkeletonCircle(size: rowHeight * 0.58 < 32 ? 32 : 44),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonLine(widthFactor: 0.55, height: 13),
                SizedBox(height: 8),
                SkeletonLine(widthFactor: 0.35, height: 11),
              ],
            ),
          ),
          const SkeletonBox(width: 56, height: 24, radius: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (headerHeight != null) ...[
        SkeletonBox(height: headerHeight!, radius: 20),
        SizedBox(height: spacing + 6),
      ],
      for (var i = 0; i < rows; i++) ...[
        _row(),
        if (i != rows - 1) SizedBox(height: spacing),
      ],
    ];
    if (!expand) {
      return AppShimmer(
        child: Padding(
          padding: padding,
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
    }
    return _SkeletonHost(padding: padding, children: children);
  }
}

/// Dashboard placeholder: hero/greeting card, 2×2 stat grid, section title,
/// then content cards — mirrors both the student and admin dashboards.
class AppDashboardSkeleton extends StatelessWidget {
  const AppDashboardSkeleton({
    super.key,
    this.heroHeight = 150,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
  });

  final double heroHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return _SkeletonHost(
      padding: padding,
      children: [
        SkeletonBox(height: heroHeight, radius: 24),
        const SizedBox(height: 22),
        const SkeletonLine(widthFactor: 0.32, height: 15),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 92, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 92, radius: 18)),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 92, radius: 18)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 92, radius: 18)),
          ],
        ),
        const SizedBox(height: 22),
        const SkeletonLine(widthFactor: 0.4, height: 15),
        const SizedBox(height: 14),
        const SkeletonBox(height: 120, radius: 20),
        const SizedBox(height: 12),
        const SkeletonBox(height: 120, radius: 20),
      ],
    );
  }
}

/// Detail-screen placeholder: large header card followed by info rows.
class AppDetailSkeleton extends StatelessWidget {
  const AppDetailSkeleton({
    super.key,
    this.headerHeight = 140,
    this.rows = 5,
    this.rowHeight = 64,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
  });

  final double headerHeight;
  final int rows;
  final double rowHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return _SkeletonHost(
      padding: padding,
      children: [
        SkeletonBox(height: headerHeight, radius: 24),
        const SizedBox(height: 20),
        const SkeletonLine(widthFactor: 0.35, height: 14),
        const SizedBox(height: 14),
        for (var i = 0; i < rows; i++) ...[
          SkeletonBox(height: rowHeight, radius: 16),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Table placeholder for attendance sheets, reports and billing tables:
/// a header band then uniform data rows.
class AppTableSkeleton extends StatelessWidget {
  const AppTableSkeleton({
    super.key,
    this.rows = 8,
    this.rowHeight = 52,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
  });

  final int rows;
  final double rowHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return _SkeletonHost(
      padding: padding,
      children: [
        const SkeletonBox(height: 40, radius: 12),
        const SizedBox(height: 10),
        for (var i = 0; i < rows; i++) ...[
          Row(
            children: [
              const SkeletonCircle(size: 32),
              const SizedBox(width: 12),
              const Expanded(
                  flex: 3, child: SkeletonLine(widthFactor: 0.9, height: 12)),
              const SizedBox(width: 12),
              Expanded(
                  flex: 2,
                  child: SkeletonBox(height: rowHeight * 0.45, radius: 10)),
            ],
          ),
          SizedBox(height: rowHeight * 0.45),
        ],
      ],
    );
  }
}

/// Form placeholder: label + field pairs (settings/config editors).
class AppFormSkeleton extends StatelessWidget {
  const AppFormSkeleton({
    super.key,
    this.fields = 4,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
  });

  final int fields;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return _SkeletonHost(
      padding: padding,
      children: [
        for (var i = 0; i < fields; i++) ...[
          const SkeletonLine(widthFactor: 0.3, height: 12),
          const SizedBox(height: 8),
          const SkeletonBox(height: 52, radius: 14),
          const SizedBox(height: 18),
        ],
        const SizedBox(height: 8),
        const SkeletonBox(height: 52, radius: 16),
      ],
    );
  }
}

/// Shrink-wrapped skeleton for bottom sheets and inline sections — safe inside
/// existing scrollables/columns (no nested ListView, no full-height claim).
class AppSheetSkeleton extends StatelessWidget {
  const AppSheetSkeleton({
    super.key,
    this.rows = 3,
    this.rowHeight = 64,
    this.withAvatar = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  });

  final int rows;
  final double rowHeight;
  final bool withAvatar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppListSkeleton(
      rows: rows,
      rowHeight: rowHeight,
      withAvatar: withAvatar,
      expand: false,
      padding: padding,
    );
  }
}

/// Chart placeholder: card-footprint block containing rising/falling bars and
/// a baseline — reads as "a chart is coming", not a blank box.
class AppChartSkeleton extends StatelessWidget {
  const AppChartSkeleton({
    super.key,
    this.height = 180,
    this.padding = EdgeInsets.zero,
  });

  final double height;
  final EdgeInsetsGeometry padding;

  static const List<double> _bars = [0.45, 0.7, 0.35, 0.85, 0.55, 0.95, 0.65];

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Padding(
        padding: padding,
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonLine(widthFactor: 0.3, height: 13),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final f in _bars) ...[
                      Expanded(
                        child: FractionallySizedBox(
                          heightFactor: f,
                          child: const SkeletonBox(
                              height: double.infinity, radius: 6),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const SkeletonBox(height: 3, radius: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal chip-row placeholder (group selectors, filter bars).
class AppChipRowSkeleton extends StatelessWidget {
  const AppChipRowSkeleton({
    super.key,
    this.chips = 3,
    this.height = 36,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  });

  final int chips;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Padding(
        padding: padding,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < chips; i++) ...[
                SkeletonBox(
                    width: 88 + (i % 2) * 24.0,
                    height: height,
                    radius: height / 2),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Profile placeholder: centered avatar, identity lines, then setting tiles.
class AppProfileSkeleton extends StatelessWidget {
  const AppProfileSkeleton({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 24),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return _SkeletonHost(
      padding: padding,
      children: const [
        Center(child: SkeletonCircle(size: 96)),
        SizedBox(height: 16),
        Center(child: SkeletonBox(width: 160, height: 16, radius: 8)),
        SizedBox(height: 8),
        Center(child: SkeletonBox(width: 110, height: 12, radius: 6)),
        SizedBox(height: 28),
        SkeletonBox(height: 56, radius: 16),
        SizedBox(height: 10),
        SkeletonBox(height: 56, radius: 16),
        SizedBox(height: 10),
        SkeletonBox(height: 56, radius: 16),
        SizedBox(height: 10),
        SkeletonBox(height: 56, radius: 16),
      ],
    );
  }
}

/// Fade cross-switcher between a skeleton and the loaded content, so screens
/// never hard-cut from placeholder to data.
class AppSkeletonSwitcher extends StatelessWidget {
  const AppSkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: loading
          ? KeyedSubtree(key: const ValueKey('skeleton'), child: skeleton)
          : KeyedSubtree(key: const ValueKey('content'), child: child),
    );
  }
}
