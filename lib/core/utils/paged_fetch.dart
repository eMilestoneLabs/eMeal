import 'dart:math' as math;

import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Live-Test-16 ISSUE-17 (scalability) — reads EVERY row of a paginated
/// endpoint in BOUNDED chunks, so a large range never becomes one huge
/// response (a 500-member month is ~46k rows ≈ 33 MB as a single JSON body,
/// stalling a server worker and risking OOM on low-end phones).
///
///  • First request is exactly the old one ([firstPageSize] rows): a range
///    that fits costs the same single request as before.
///  • Larger ranges: [chunkSize]-row pages, [parallelism] in flight at most,
///    until a SHORT page marks the end. Relies on the endpoint's stable order.
///  • Rows are de-duplicated by [idOf] (a mark written mid-fetch shifts later
///    pages by one row — never lost, never doubled). The result is the range
///    as of the FIRST request (a row created mid-read may or may not appear).
///  • Any failed page, or fewer unique rows than existed when the read
///    started, is an Err — a report is never built from a truncated list.
///
/// PURE (the page fetcher is injected) — unit-tested without a network.
Future<Result<List<T>>> fetchAllPages<T>({
  required Future<Result<PaginatedResponse<T>>> Function(int page, int limit)
      fetchPage,
  required String Function(T item) idOf,
  required int firstPageSize,
  required int chunkSize,
  required int parallelism,
  required String truncatedMessage,
}) async {
  final int firstTotal;
  switch (await fetchPage(1, firstPageSize)) {
    case Err(:final failure):
      return Err(failure);
    case Ok(:final value):
      if (value.total <= value.data.length) return Ok(value.data);
      firstTotal = value.total;
  }

  final lanes = math.max(1, parallelism);
  // Bounded: the pages the first total needs, plus slack for rows written
  // while the fetch runs — never an unbounded loop.
  final maxPages = (firstTotal + chunkSize - 1) ~/ chunkSize + lanes + 2;
  final seen = <String>{};
  final rows = <T>[];
  var page = 1;
  var reachedEnd = false;
  while (!reachedEnd && page <= maxPages) {
    final wave = [
      for (var p = page; p < page + lanes && p <= maxPages; p++)
        fetchPage(p, chunkSize),
    ];
    page += wave.length;
    final results = await Future.wait(wave);
    for (final r in results) {
      switch (r) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          for (final item in value.data) {
            if (seen.add(idOf(item))) rows.add(item);
          }
          if (value.data.length < chunkSize) reachedEnd = true;
      }
    }
  }
  // Against the FIRST total: a mark written mid-read raises the live total
  // but must not fail the report; a row that existed at the start and is
  // missing now (skipped) always does.
  if (!reachedEnd || rows.length < firstTotal) {
    return Err(UnexpectedFailure(message: truncatedMessage));
  }
  return Ok(rows);
}
