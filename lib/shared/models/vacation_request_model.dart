/// Issue 3 — vacation approval workflow request.
///
/// Mirrors the backend VacationRequest serializer contract:
/// startDate / endDate are date-only (YYYY-MM-DD); review timestamps are
/// ISO-8601 or null; status is one of pending | approved | rejected | cancelled.
class VacationRequestModel {
  const VacationRequestModel({
    required this.id,
    required this.organizationId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.groupId,
    this.userName,
    this.reason,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String organizationId;
  final String? groupId;
  final String userId;
  final String? userName;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    final s = v.toString();
    // date-only 'YYYY-MM-DD' or full ISO
    return DateTime.tryParse(s.length == 10 ? '${s}T00:00:00' : s) ??
        DateTime.now();
  }

  static DateTime? _parseNullable(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory VacationRequestModel.fromJson(Map<String, dynamic> j) {
    return VacationRequestModel(
      id: (j['id'] ?? '').toString(),
      organizationId: (j['organizationId'] ?? '').toString(),
      groupId: j['groupId']?.toString(),
      userId: (j['userId'] ?? '').toString(),
      userName: j['userName']?.toString(),
      startDate: _parseDate(j['startDate']),
      endDate: _parseDate(j['endDate']),
      reason: j['reason']?.toString(),
      status: (j['status'] ?? 'pending').toString(),
      reviewedBy: j['reviewedBy']?.toString(),
      reviewedAt: _parseNullable(j['reviewedAt']),
      reviewNote: j['reviewNote']?.toString(),
      createdAt: _parseNullable(j['createdAt']),
      updatedAt: _parseNullable(j['updatedAt']),
    );
  }
}
