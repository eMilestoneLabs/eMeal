// Issues_Live_Test_16 ISSUE-17 (scalability) — fetchAllPages reads a large
// range in BOUNDED chunks: small ranges keep the old single request, nothing
// is lost or doubled when a mark lands mid-fetch, and any gap is an error.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/core/utils/paged_fetch.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Fake server: stable newest-first order, offset pagination like Prisma
/// skip/take. `rows` is mutable so a test can insert a row mid-fetch.
class _Server {
  _Server(int n) : rows = [for (var i = n; i >= 1; i--) 'r$i'];
  final List<String> rows;
  final calls = <(int, int)>[];
  int inFlight = 0, maxInFlight = 0;
  int? failPage;
  int? capRows; // simulate a server that silently caps a page
  void Function(int page)? onPage;

  Future<Result<PaginatedResponse<String>>> fetch(int page, int limit) async {
    calls.add((page, limit));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    inFlight--;
    onPage?.call(page);
    if (page == failPage) {
      return const Err(NetworkFailure(message: 'offline'));
    }
    final start = (page - 1) * limit;
    var slice = start >= rows.length
        ? <String>[]
        : rows.sublist(start, (start + limit).clamp(0, rows.length));
    if (capRows != null && slice.length > capRows!) {
      slice = slice.sublist(0, capRows!);
    }
    return Ok(PaginatedResponse(
        data: slice, total: rows.length, page: page, limit: limit));
  }
}

Future<Result<List<String>>> _all(_Server s) => fetchAllPages<String>(
      fetchPage: s.fetch,
      idOf: (x) => x,
      firstPageSize: 100,
      chunkSize: 1000,
      parallelism: 3,
      truncatedMessage: 'truncated',
    );

void main() {
  test('a range that fits one page costs exactly the old single request', () async {
    final s = _Server(93);
    final r = await _all(s);
    expect((r as Ok<List<String>>).value.length, 93);
    expect(s.calls, [(1, 100)]);
  });

  test('9,300 rows: bounded 1000-row chunks, every row once, server order kept', () async {
    final s = _Server(9300);
    final r = await _all(s);
    final rows = (r as Ok<List<String>>).value;
    expect(rows.length, 9300);
    expect(rows.toSet().length, 9300);
    expect(rows.first, 'r9300');
    expect(rows.last, 'r1');
    expect(s.calls.skip(1).every((c) => c.$2 == 1000), isTrue); // never one giant page
    expect(s.maxInFlight, lessThanOrEqualTo(3));
  });

  test('an exact multiple of the chunk size still terminates correctly', () async {
    final s = _Server(3000);
    final rows = ((await _all(s)) as Ok<List<String>>).value;
    expect(rows.length, 3000);
  });

  test('a mark written MID-FETCH never loses or doubles a row (no false error)', () async {
    final s = _Server(2000);
    // Chunk page 1 is served, THEN a new record appears at the top: page 2
    // shifts by one (its first row repeats) and the original last row spills
    // onto page 3.
    var inserted = false;
    var chunkPage1Served = false;
    s.onPage = (page) {
      if (s.calls.length > 1 && page == 1) chunkPage1Served = true;
      if (page == 2 && chunkPage1Served && !inserted) {
        s.rows.insert(0, 'r_new');
        inserted = true;
      }
    };
    final r = await _all(s);
    expect(inserted, isTrue, reason: 'the scenario must really insert mid-read');
    final rows = (r as Ok<List<String>>).value; // NOT a false error
    for (var i = 1; i <= 2000; i++) {
      expect(rows.contains('r$i'), isTrue, reason: 'r$i lost');
    }
    expect(rows.toSet().length, rows.length); // no duplicates
  });

  test('a row DELETED mid-fetch (a real gap) fails loudly', () async {
    final s = _Server(2000);
    var deleted = false;
    s.onPage = (page) {
      if (s.calls.length > 1 && page == 2 && !deleted) {
        s.rows.removeAt(0); // everything shifts up: one unread row is skipped
        deleted = true;
      }
    };
    expect(await _all(s), isA<Err<List<String>>>());
    expect(deleted, isTrue);
  });

  test('a failed chunk fails the whole read (never a partial report)', () async {
    final s = _Server(5000)..failPage = 3;
    expect(await _all(s), isA<Err<List<String>>>());
  });

  test('a server that returns fewer rows than it reports is an error', () async {
    final s = _Server(2500)..capRows = 500;
    final r = await _all(s);
    expect(r, isA<Err<List<String>>>());
    expect((r as Err).failure.message, 'truncated');
  });
}
