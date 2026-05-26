import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// State manager for the export screen.
class ExportProvider extends ChangeNotifier {
  ExportProvider({ExportService? exportService})
      : _service = exportService ?? ExportService.instance;

  final ExportService _service;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isExporting = false;
  String? _error;
  String _exportFormat = 'pdf'; // 'pdf' or 'csv'
  bool _exportSuccess = false;

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isExporting => _isExporting;
  String? get error => _error;
  String get exportFormat => _exportFormat;
  bool get exportSuccess => _exportSuccess;
  bool get isPdf => _exportFormat == 'pdf';

  // ── Actions ────────────────────────────────────────────────────────────────

  void setFormat(String format) {
    assert(format == 'pdf' || format == 'csv', 'Format must be pdf or csv');
    if (_exportFormat == format) return;
    _exportFormat = format;
    notifyListeners();
  }

  Future<void> export({
    required List<AttendanceModel> records,
    required String groupName,
    String? dateRangeLabel,
  }) async {
    if (_isExporting) return;
    _isExporting = true;
    _error = null;
    _exportSuccess = false;
    notifyListeners();

    try {
      if (_exportFormat == 'pdf') {
        await _service.exportPdf(
          records: records,
          groupName: groupName,
          dateRangeLabel: dateRangeLabel,
        );
      } else {
        await _service.exportCsv(
          records: records,
          groupName: groupName,
          dateRangeLabel: dateRangeLabel,
        );
      }
      _exportSuccess = true;
    } catch (e) {
      _error = 'Export failed: $e';
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearSuccess() {
    _exportSuccess = false;
    notifyListeners();
  }
}
