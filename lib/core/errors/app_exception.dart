/// Typed exception hierarchy for the MealAttend infrastructure layer.
///
/// All repository and service methods throw subtypes of [AppException]
/// rather than raw [Exception] or [Error] instances. The repository layer
/// converts these into [Failure] values before they reach any provider.
sealed class AppException implements Exception {
  const AppException({required this.message, this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an HTTP request fails (timeout, 4xx, 5xx, no connectivity).
final class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.cause,
    this.statusCode,
  });

  final int? statusCode;
}

/// Thrown when authentication fails (invalid token, session expired, etc.).
final class AuthException extends AppException {
  const AuthException({required super.message, super.cause});
}

/// Thrown when request or response data fails validation rules.
final class ValidationException extends AppException {
  const ValidationException({
    required super.message,
    super.cause,
    this.fieldErrors = const {},
  });

  /// Per-field validation messages keyed by field name.
  final Map<String, String> fieldErrors;
}

/// Thrown when a local storage operation (secure storage, preferences) fails.
final class StorageException extends AppException {
  const StorageException({required super.message, super.cause});
}

/// Thrown for unexpected/unclassified errors that don't fit other categories.
final class UnexpectedException extends AppException {
  const UnexpectedException({required super.message, super.cause});
}
