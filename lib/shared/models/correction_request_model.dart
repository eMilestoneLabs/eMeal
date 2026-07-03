/// Module 33 — Attendance Correction Request (FR-ACR-*).
///
/// Mirrors the backend CorrectionRequestSerializer contract:
/// attendanceDate is date-only (YYYY-MM-DD); timestamps are ISO-8601 or null.
/// requestType: claim_present | correct_to_absent | correct_to_skip |
///              fix_preference | dispute_charge
/// status:      pending | approved | rejected | expired | cancelled
/// sourceChannel: member (member-raised) | admin_prompt (admin-proposed
///                increase awaiting the member's confirm/decline).
class CorrectionRequestModel {
  const CorrectionRequestModel({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.mealId,
    required this.attendanceDate,
    required this.requestType,
    required this.status,
    required this.sourceChannel,
    this.userName,
    this.mealName,
    this.requestedStatus,
    this.requestedPreference,
    this.reason,
    this.evidenceUrl,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.resultRecordId,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String groupId;
  final String userId;
  final String? userName;
  final String mealId;
  final String? mealName;
  final DateTime attendanceDate;
  final String requestType;
  final String? requestedStatus;
  final String? requestedPreference;
  final String? reason;
  final String? evidenceUrl;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String sourceChannel;
  final String? resultRecordId;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';
  bool get isCancelled => status == 'cancelled';

  /// True when this is an admin-proposed increase the member must decide on.
  bool get isMemberConfirmation => sourceChannel == 'admin_prompt';

  /// Short human label for the request type.
  String get typeLabel => switch (requestType) {
        'claim_present' => 'Mark me Present',
        'correct_to_absent' => 'Correct to Absent',
        'correct_to_skip' => 'Correct to Skip',
        'fix_preference' => 'Fix preference',
        'dispute_charge' => 'Dispute charge',
        _ => requestType,
      };

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    final s = v.toString();
    return DateTime.tryParse(s.length == 10 ? '${s}T00:00:00' : s) ??
        DateTime.now();
  }

  static DateTime? _parseNullable(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory CorrectionRequestModel.fromJson(Map<String, dynamic> j) {
    return CorrectionRequestModel(
      id: (j['id'] ?? '').toString(),
      groupId: (j['groupId'] ?? '').toString(),
      userId: (j['userId'] ?? '').toString(),
      userName: j['userName']?.toString(),
      mealId: (j['mealId'] ?? '').toString(),
      mealName: j['mealName']?.toString(),
      attendanceDate: _parseDate(j['attendanceDate']),
      requestType: (j['requestType'] ?? '').toString(),
      requestedStatus: j['requestedStatus']?.toString(),
      requestedPreference: j['requestedPreference']?.toString(),
      reason: j['reason']?.toString(),
      evidenceUrl: j['evidenceUrl']?.toString(),
      status: (j['status'] ?? 'pending').toString(),
      reviewedBy: j['reviewedBy']?.toString(),
      reviewedAt: _parseNullable(j['reviewedAt']),
      reviewNote: j['reviewNote']?.toString(),
      sourceChannel: (j['sourceChannel'] ?? 'member').toString(),
      resultRecordId: j['resultRecordId']?.toString(),
      createdAt: _parseNullable(j['createdAt']),
      expiresAt: _parseNullable(j['expiresAt']),
    );
  }
}
