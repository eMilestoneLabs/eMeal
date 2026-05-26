import 'package:equatable/equatable.dart';

/// Generic wrapper for paginated NestJS API list responses.
///
/// The NestJS backend returns all paginated lists in this shape:
/// ```json
/// {
///   "data": [...],
///   "total": 87,
///   "page": 1,
///   "limit": 20
/// }
/// ```
///
/// Usage in a repository:
/// ```dart
/// final response = await dio.get(
///   ApiEndpoints.attendance.history,
///   queryParameters: params.toQueryParams(),
/// );
/// return PaginatedResponse.fromJson(
///   response.data as Map<String, dynamic>,
///   AttendanceModel.fromJson,
/// );
/// ```
///
/// Usage in a provider (infinite scroll / load more):
/// ```dart
/// if (_response.hasMore) {
///   _params = _params.nextPage;
///   final next = await _repo.fetchHistory(_params);
///   _response = _response.append(next);
/// }
/// ```
class PaginatedResponse<T> extends Equatable {
  const PaginatedResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
  });

  // ── Fields ─────────────────────────────────────────────────────────────────

  /// The items on the current page.
  final List<T> data;

  /// Total number of records matching the query (across all pages).
  final int total;

  /// The current page number (1-indexed).
  final int page;

  /// Maximum number of items per page.
  final int limit;

  // ── Derived ────────────────────────────────────────────────────────────────

  /// True when more pages exist after the current one.
  bool get hasMore => (page * limit) < total;

  /// True when this is the first page.
  bool get isFirstPage => page == 1;

  /// Total number of pages for this result set.
  int get totalPages => total == 0 ? 1 : ((total + limit - 1) ~/ limit);

  /// True when the [data] list is empty.
  bool get isEmpty => data.isEmpty;

  /// True when at least one item exists.
  bool get isNotEmpty => data.isNotEmpty;

  // ── Deserialisation ────────────────────────────────────────────────────────

  /// Deserialise from a NestJS paginated response body.
  ///
  /// [fromJson] is called on each item in `response['data']`.
  ///
  /// Example:
  /// ```dart
  /// PaginatedResponse.fromJson(body, AttendanceModel.fromJson)
  /// ```
  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final rawList = json['data'] as List<dynamic>? ?? [];
    return PaginatedResponse<T>(
      data: rawList
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? rawList.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? rawList.length,
    );
  }

  // ── Mutations (returns new instances) ──────────────────────────────────────

  /// Merges [next] page items into this response.
  ///
  /// Used for infinite-scroll / load-more patterns in providers.
  /// The returned response carries the updated [page] and [total] from [next].
  PaginatedResponse<T> append(PaginatedResponse<T> next) {
    return PaginatedResponse<T>(
      data: [...data, ...next.data],
      total: next.total,
      page: next.page,
      limit: next.limit,
    );
  }

  /// Returns a copy with the specified fields replaced.
  PaginatedResponse<T> copyWith({
    List<T>? data,
    int? total,
    int? page,
    int? limit,
  }) {
    return PaginatedResponse<T>(
      data: data ?? this.data,
      total: total ?? this.total,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  // ── Empty factory ──────────────────────────────────────────────────────────

  /// Creates an empty first-page response — useful as an initial state in
  /// providers before the first API call completes.
  static PaginatedResponse<T> empty<T>({int limit = 20}) {
    return PaginatedResponse<T>(
      data: const [],
      total: 0,
      page: 1,
      limit: limit,
    );
  }

  // ── Equatable ──────────────────────────────────────────────────────────────

  @override
  List<Object?> get props => [data, total, page, limit];
}

// ── Pagination parameters ──────────────────────────────────────────────────────

/// Query parameters for paginated API requests.
///
/// Serialises to `?page=1&limit=20` via [toQueryParams].
///
/// Usage:
/// ```dart
/// var _params = const PaginationParams();
///
/// Future<void> _loadMore() async {
///   final result = await _repo.fetchHistory(_params);
///   _response = _response.append(result);
///   _params = _params.nextPage;
/// }
/// ```
class PaginationParams extends Equatable {
  const PaginationParams({
    this.page = 1,
    this.limit = 20,
  })  : assert(page >= 1, 'page must be >= 1'),
        assert(limit >= 1 && limit <= 100, 'limit must be between 1 and 100');

  /// Current page number (1-indexed).
  final int page;

  /// Items per page. Capped at 100 to match NestJS guard defaults.
  final int limit;

  // ── Derived ────────────────────────────────────────────────────────────────

  bool get isFirstPage => page == 1;

  /// Returns a copy advanced to the next page.
  PaginationParams get nextPage => copyWith(page: page + 1);

  /// Returns a reset copy starting from page 1.
  PaginationParams get reset => copyWith(page: 1);

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Converts to Dio query parameters map.
  ///
  /// Pass directly to `dio.get(url, queryParameters: params.toQueryParams())`.
  Map<String, String> toQueryParams() => {
        'page': page.toString(),
        'limit': limit.toString(),
      };

  // ── CopyWith ───────────────────────────────────────────────────────────────

  PaginationParams copyWith({int? page, int? limit}) {
    return PaginationParams(
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }

  @override
  List<Object?> get props => [page, limit];
}
