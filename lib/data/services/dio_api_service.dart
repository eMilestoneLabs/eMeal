import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';
import 'package:smart_meal_management/shared/models/result.dart';

// ── DioApiService ──────────────────────────────────────────────────────────────

/// Production-ready HTTP client for all MealAttend REST API calls.
///
/// ## Responsibilities
///
/// - Injects `Authorization: Bearer <accessToken>` on every authenticated request.
/// - Intercepts `401 Unauthorized` responses, silently refreshes the access
///   token via the refresh-token endpoint, then retries the original request
///   exactly once.  A second `401` on the retried request triggers logout.
/// - Maps `DioException` into the app's typed [Failure] hierarchy so
///   repositories never deal with raw Dio errors.
/// - Logs request/response details in development when verbose logging is on.
///
/// ## Usage in a repository
///
/// ```dart
/// final result = await DioApiService.instance.get<Map<String, dynamic>>(
///   '/v1/groups/$groupId',
/// );
/// switch (result) {
///   case Ok(:final value):
///     return Ok(GroupModel.fromJson(value));
///   case Err(:final failure):
///     return Err(failure);
/// }
/// ```
///
/// ## Integration checklist (Phase B6)
///
/// 1. Remove `MockAuthService` calls from [AuthRepository] when
///    `EnvConfig.current.mockAuthEnabled == false`.
/// 2. Replace mock repo implementations with real API calls using this service.
/// 3. Update `_refreshEndpoint` to match the NestJS `/v1/auth/refresh` route.
///
/// ## Thread safety
///
/// [_isRefreshing] prevents concurrent token-refresh storms. If a second
/// request 401s while a refresh is in flight, it waits until the refresh
/// completes before deciding whether to retry.
class DioApiService {
  DioApiService._() {
    _dio = _buildDio();
    _dio.interceptors.add(_AuthInterceptor(_dio, this));
    if (EnvConfig.current.enableVerboseLogging) {
      _dio.interceptors.add(LogInterceptor(
        requestHeader: true,
        responseHeader: false,
        requestBody: true,
        responseBody: true,
        error: true,
        logPrint: (obj) => debugPrint('[DioApiService] $obj'),
      ));
    }
  }

  static final DioApiService instance = DioApiService._();

  late final Dio _dio;

  /// Whether a token refresh is currently in flight.
  bool _isRefreshing = false;

  // ── Dio factory ───────────────────────────────────────────────────────────

  static Dio _buildDio() {
    final env = EnvConfig.current;
    return Dio(
      BaseOptions(
        baseUrl: env.apiV1,
        connectTimeout: env.connectTimeout,
        receiveTimeout: env.receiveTimeout,
        sendTimeout: env.sendTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        validateStatus: (status) =>
            // Accept 2xx; everything else is an error.
            status != null && status >= 200 && status < 300,
      ),
    );
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Issues a `GET` request to [path] and maps the body to [T].
  ///
  /// [queryParameters] are appended as URL query params.
  Future<Result<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
  }) =>
      _request<T>(
        path: path,
        method: 'GET',
        queryParameters: queryParameters,
        requiresAuth: requiresAuth,
      );

  /// Issues a `POST` request to [path] with an optional JSON [body].
  Future<Result<T>> post<T>(
    String path, {
    Object? body,
    bool requiresAuth = true,
  }) =>
      _request<T>(
        path: path,
        method: 'POST',
        body: body,
        requiresAuth: requiresAuth,
      );

  /// Issues a `PUT` request to [path] with an optional JSON [body].
  Future<Result<T>> put<T>(
    String path, {
    Object? body,
    bool requiresAuth = true,
  }) =>
      _request<T>(
        path: path,
        method: 'PUT',
        body: body,
        requiresAuth: requiresAuth,
      );

  /// Issues a `PATCH` request to [path] with an optional JSON [body].
  Future<Result<T>> patch<T>(
    String path, {
    Object? body,
    bool requiresAuth = true,
  }) =>
      _request<T>(
        path: path,
        method: 'PATCH',
        body: body,
        requiresAuth: requiresAuth,
      );

  /// Issues a `DELETE` request to [path].
  Future<Result<T>> delete<T>(
    String path, {
    bool requiresAuth = true,
  }) =>
      _request<T>(
        path: path,
        method: 'DELETE',
        requiresAuth: requiresAuth,
      );

  // ── Core request dispatcher ───────────────────────────────────────────────

  Future<Result<T>> _request<T>({
    required String path,
    required String method,
    Object? body,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = true,
    bool isRetry = false,
  }) async {
    try {
      final options = Options(
        method: method,
        extra: {
          _kRequiresAuth: requiresAuth,
          _kIsRetry: isRetry,
        },
      );

      final response = await _dio.request<T>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: options,
      );

      return Ok(response.data as T);
    } on DioException catch (e) {
      return Err(_mapDioError(e));
    } on SocketException {
      return const Err(NetworkFailure(
        message: 'No internet connection. Please check your network.',
      ));
    } catch (e) {
      return Err(UnexpectedFailure(message: e.toString(), cause: e));
    }
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  /// Refreshes the access token using the stored refresh token.
  ///
  /// On success: overwrites the session in [AuthStorageService] and returns
  /// the new `accessToken`.
  /// On failure: clears the stored session and returns `null`, signalling that
  /// the user must log in again.
  Future<String?> refreshAccessToken() async {
    if (_isRefreshing) return null;
    _isRefreshing = true;

    try {
      final session = await AuthStorageService.instance.loadSession();
      if (session == null || session.isExpired) {
        await AuthStorageService.instance.clearSession();
        return null;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        _refreshEndpoint,
        data: {'refreshToken': session.refreshToken},
        options: Options(extra: {_kRequiresAuth: false}),
      );

      final body = response.data;
      if (body == null) return null;

      final newAccessToken = body['accessToken'] as String?;
      final newRefreshToken = body['refreshToken'] as String?;
      if (newAccessToken == null || newRefreshToken == null) return null;

      // Persist refreshed session — only tokens change, user profile stays.
      final updatedSession = session.copyWith(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      );
      await AuthStorageService.instance.saveSession(updatedSession);
      return newAccessToken;
    } catch (_) {
      await AuthStorageService.instance.clearSession();
      return null;
    } finally {
      _isRefreshing = false;
    }
  }

  // ── Error mapping ─────────────────────────────────────────────────────────

  /// Converts a [DioException] into the app-layer [Failure] hierarchy.
  Failure _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const NetworkFailure(
          message: 'Request timed out. Please try again.',
        );

      case DioExceptionType.connectionError:
        return const NetworkFailure(
          message: 'Unable to reach the server. Check your connection.',
        );

      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        final serverMessage = _extractServerMessage(e.response);

        if (status == 401) {
          return AuthFailure(
            message: serverMessage ?? 'Session expired. Please log in again.',
            cause: e,
          );
        }
        if (status == 403) {
          return AuthFailure(
            message: serverMessage ?? 'You don\'t have permission for this.',
            cause: e,
          );
        }
        if (status == 422 || status == 400) {
          return ValidationFailure(
            message: serverMessage ?? 'Invalid request. Check your input.',
            fieldErrors: _extractFieldErrors(e.response),
            cause: e,
          );
        }
        if (status >= 500) {
          return NetworkFailure(
            message: serverMessage ?? 'Server error. Please try again later.',
            statusCode: status,
            cause: e,
          );
        }
        return NetworkFailure(
          message: serverMessage ?? 'Unexpected server response ($status).',
          statusCode: status,
          cause: e,
        );

      case DioExceptionType.cancel:
        return const NetworkFailure(message: 'Request was cancelled.');

      case DioExceptionType.unknown:
      case DioExceptionType.badCertificate:
        return NetworkFailure(
          message: 'Connection error: ${e.message ?? 'Unknown'}',
          cause: e,
        );
    }
  }

  /// Pulls the human-readable `message` field from API error bodies.
  String? _extractServerMessage(Response<dynamic>? response) {
    try {
      final data = response?.data;
      if (data is Map<String, dynamic>) {
        return data['message'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Pulls per-field validation errors from API error bodies.
  ///
  /// Expects the NestJS class-validator error format:
  /// ```json
  /// { "errors": { "email": "must be a valid email" } }
  /// ```
  Map<String, String> _extractFieldErrors(Response<dynamic>? response) {
    try {
      final data = response?.data;
      if (data is Map<String, dynamic>) {
        final errors = data['errors'];
        if (errors is Map) {
          return errors.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {}
    return {};
  }

  // ── Constants ─────────────────────────────────────────────────────────────

  /// NestJS route that accepts `{ refreshToken }` and returns new token pair.
  static const String _refreshEndpoint = '/auth/refresh';

  /// Extra key used to mark authenticated requests (read by [_AuthInterceptor]).
  static const String _kRequiresAuth = 'requiresAuth';

  /// Extra key used to prevent infinite retry loops.
  static const String _kIsRetry = 'isRetry';
}

// ── Auth interceptor ───────────────────────────────────────────────────────────

/// Dio interceptor that:
///
/// 1. Attaches `Authorization: Bearer <token>` to every request marked with
///    `requiresAuth: true` (default).
/// 2. On a `401` response, calls [DioApiService.refreshAccessToken] exactly
///    once and retries the original request with the new token.  If the retry
///    also 401s, the request fails with an [AuthFailure].
///
/// ## Why a separate class?
///
/// Keeping the interceptor outside [DioApiService] avoids a circular reference
/// between the service and its own Dio instance in the `onError` handler.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio, this._service);

  final Dio _dio;
  final DioApiService _service;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final requiresAuth = options.extra[DioApiService._kRequiresAuth] != false;

    if (requiresAuth) {
      final session = await AuthStorageService.instance.loadSession();
      if (session != null && session.isValid) {
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final isRetry = err.requestOptions.extra[DioApiService._kIsRetry] == true;
    final is401 = err.response?.statusCode == 401;

    // Only attempt refresh on 401 for authenticated, non-retry requests.
    if (!is401 || isRetry) {
      return handler.next(err);
    }

    final newToken = await _service.refreshAccessToken();

    if (newToken == null) {
      // Refresh failed — propagate the 401 so the caller sees AuthFailure.
      return handler.next(err);
    }

    // Retry original request with the new token.
    try {
      final opts = err.requestOptions;
      opts.headers['Authorization'] = 'Bearer $newToken';
      opts.extra[DioApiService._kIsRetry] = true;

      final response = await _dio.fetch<dynamic>(opts);
      return handler.resolve(response);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }
}
