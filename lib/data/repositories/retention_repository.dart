import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// SRS Module 03 RPT-009/010/011 + RET-001..015 — Data Archives.
///
/// Before the rolling 3-month retention purge, the server generates a
/// complete Excel + PDF archive of the removed data and stores it in MinIO.
/// This repository lists those archives for the admin's
/// Reports → Data Archives section; the files themselves are plain object
/// URLs opened/downloaded externally.
class RetentionRepository {
  RetentionRepository();

  /// GET /retention/archives?groupId= — newest first (admin/manager only).
  Future<Result<List<GroupArchiveModel>>> listArchives({
    String? groupId,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/retention/archives',
      queryParameters: {
        if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(
          (value['data'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(GroupArchiveModel.fromJson)
              .toList(),
        ),
    };
  }
}

/// One pre-purge retention archive (the admin's permanent copy — RET-010).
class GroupArchiveModel {
  const GroupArchiveModel({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.periodStart,
    required this.periodEnd,
    required this.excelUrl,
    this.pdfUrl,
    this.recordCounts = const {},
    required this.generatedAt,
    this.purgedAt,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String periodStart; // yyyy-MM-dd (inclusive)
  final String periodEnd; // yyyy-MM-dd (inclusive)
  final String excelUrl;
  final String? pdfUrl;
  final Map<String, int> recordCounts;
  final DateTime generatedAt;
  final DateTime? purgedAt;

  factory GroupArchiveModel.fromJson(Map<String, dynamic> json) {
    final counts = <String, int>{};
    final raw = json['recordCounts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) counts['$k'] = v.toInt();
      });
    }
    return GroupArchiveModel(
      id: json['id'] as String? ?? '',
      groupId: json['groupId'] as String? ?? '',
      groupName: json['groupName'] as String? ?? '',
      periodStart: json['periodStart'] as String? ?? '',
      periodEnd: json['periodEnd'] as String? ?? '',
      excelUrl: json['excelUrl'] as String? ?? '',
      pdfUrl: json['pdfUrl'] as String?,
      recordCounts: counts,
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      purgedAt: json['purgedAt'] != null
          ? DateTime.tryParse(json['purgedAt'] as String)
          : null,
    );
  }

  /// Total archived rows across all datasets (for the card subtitle).
  int get totalRecords =>
      recordCounts.values.fold(0, (sum, v) => sum + v);
}
