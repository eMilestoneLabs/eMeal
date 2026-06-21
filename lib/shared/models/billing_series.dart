import 'package:flutter/foundation.dart';

int _asInt(dynamic v) => v is int
    ? v
    : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);

/// One time-bucket point for the Member Billing analytics charts.
@immutable
class BillingSeriesPoint {
  const BillingSeriesPoint({
    required this.label,
    required this.revenue,
    required this.presentMeals,
  });

  final String label; // e.g. 2026-06-01 (day/week) or 2026-06 (month)
  final int revenue;
  final int presentMeals;

  factory BillingSeriesPoint.fromJson(Map<String, dynamic> j) =>
      BillingSeriesPoint(
        label: j['label']?.toString() ?? '',
        revenue: _asInt(j['revenue']),
        presentMeals: _asInt(j['presentMeals']),
      );
}

/// Bucketed billing time-series from GET /attendance/billing-series.
@immutable
class BillingSeries {
  const BillingSeries({required this.bucket, required this.points});
  final String bucket; // day | week | month
  final List<BillingSeriesPoint> points;

  static const BillingSeries empty = BillingSeries(bucket: 'day', points: []);

  factory BillingSeries.fromJson(Map<String, dynamic> j) => BillingSeries(
        bucket: j['bucket']?.toString() ?? 'day',
        points: ((j['series'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => BillingSeriesPoint.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}
