/// Delivery diagnostics for the push channel (FR-NOTX-018 / ISSUE-16).
///
/// Mirrors `GET /notifications/diagnostics` — lets an admin see whether push
/// is configured, how many members have a registered device, and how the most
/// recent send went, so "notifications are on but nothing arrives" is
/// observable instead of silent.
class NotificationDiagnostics {
  const NotificationDiagnostics({
    required this.pushConfigured,
    required this.registeredDevices,
    required this.membersWithoutDevice,
    required this.totalMembers,
    this.lastSend,
  });

  /// Whether the FCM channel is configured server-side (vs log-only mode).
  final bool pushConfigured;
  final int registeredDevices;
  final int membersWithoutDevice;
  final int totalMembers;

  /// Outcome of the most recent push send, if one happened in the last 7 days.
  final LastSendResult? lastSend;

  factory NotificationDiagnostics.fromJson(Map<String, dynamic> json) {
    final rawLast = json['lastSend'];
    return NotificationDiagnostics(
      pushConfigured: json['pushConfigured'] == true,
      registeredDevices: (json['registeredDevices'] as num?)?.toInt() ?? 0,
      membersWithoutDevice:
          (json['membersWithoutDevice'] as num?)?.toInt() ?? 0,
      totalMembers: (json['totalMembers'] as num?)?.toInt() ?? 0,
      lastSend: rawLast is Map<String, dynamic>
          ? LastSendResult.fromJson(rawLast)
          : null,
    );
  }
}

/// The recorded outcome of the most recent push send (worker-written).
class LastSendResult {
  const LastSendResult({
    required this.at,
    required this.title,
    required this.successful,
    required this.failed,
    required this.total,
  });

  final DateTime? at;
  final String title;
  final int successful;
  final int failed;
  final int total;

  factory LastSendResult.fromJson(Map<String, dynamic> json) {
    return LastSendResult(
      at: DateTime.tryParse(json['at'] as String? ?? ''),
      title: json['title'] as String? ?? '',
      successful: (json['successful'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}
