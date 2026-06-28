import 'package:flutter/foundation.dart';

/// Notice board item (Phase B) — mirrors the backend NoticeSerializer contract
/// (src/features/notices/serializers/notice.serializer.ts).
@immutable
class NoticeModel {
  const NoticeModel({
    required this.id,
    required this.organizationId,
    required this.groupId,
    required this.createdBy,
    required this.title,
    required this.body,
    required this.priority,
    required this.pinned,
    required this.isActive,
    required this.isRead,
    required this.readCount,
    required this.publishedAt,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String organizationId;

  /// null = organization-wide notice.
  final String? groupId;
  final String createdBy;
  final String title;
  final String body;

  /// low | normal | high | urgent.
  final String priority;
  final bool pinned;
  final bool isActive;

  /// Whether the requesting user has read this notice.
  final bool isRead;

  /// Admin-facing: how many members have read it.
  final int readCount;
  final DateTime publishedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOrgWide => groupId == null;

  static DateTime _parse(dynamic v) =>
      v == null ? DateTime.now() : DateTime.parse(v.toString()).toLocal();

  static DateTime? _parseN(dynamic v) =>
      v == null ? null : DateTime.parse(v.toString()).toLocal();

  factory NoticeModel.fromJson(Map<String, dynamic> j) => NoticeModel(
        id: (j['id'] ?? '').toString(),
        organizationId: (j['organizationId'] ?? '').toString(),
        groupId: j['groupId']?.toString(),
        createdBy: (j['createdBy'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        priority: (j['priority'] ?? 'normal').toString(),
        pinned: j['pinned'] == true,
        isActive: j['isActive'] != false,
        isRead: j['isRead'] == true,
        readCount: j['readCount'] is int
            ? j['readCount'] as int
            : int.tryParse('${j['readCount'] ?? 0}') ?? 0,
        publishedAt: _parse(j['publishedAt']),
        expiresAt: _parseN(j['expiresAt']),
        createdAt: _parse(j['createdAt']),
        updatedAt: _parse(j['updatedAt']),
      );

  /// Serializes back to the backend/JSON shape so the feed can be cached
  /// locally (round-trips exactly through [NoticeModel.fromJson]).
  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'groupId': groupId,
        'createdBy': createdBy,
        'title': title,
        'body': body,
        'priority': priority,
        'pinned': pinned,
        'isActive': isActive,
        'isRead': isRead,
        'readCount': readCount,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  NoticeModel copyWith({bool? isRead}) => NoticeModel(
        id: id,
        organizationId: organizationId,
        groupId: groupId,
        createdBy: createdBy,
        title: title,
        body: body,
        priority: priority,
        pinned: pinned,
        isActive: isActive,
        isRead: isRead ?? this.isRead,
        readCount: readCount,
        publishedAt: publishedAt,
        expiresAt: expiresAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
