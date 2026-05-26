import 'package:smart_meal_management/core/errors/app_exception.dart';

/// Represents a user-facing error value returned by repositories.
///
/// Repositories never throw — they return [Result<T>] where the error branch
/// carries a [Failure]. UI layers switch on the subtype to show appropriate
/// messages.
sealed class Failure {
  const Failure({required this.message, this.cause});

  final String message;
  final Object? cause;
}

// ── Concrete failure types ─────────────────────────────────────────────────────

final class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
    super.cause,
    this.statusCode,
  });

  final int? statusCode;

  factory NetworkFailure.fromException(NetworkException e) =>
      NetworkFailure(message: e.message, statusCode: e.statusCode, cause: e);
}

final class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.cause});

  factory AuthFailure.fromException(AuthException e) =>
      AuthFailure(message: e.message, cause: e);
}

final class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    super.cause,
    this.fieldErrors = const {},
  });

  final Map<String, String> fieldErrors;

  factory ValidationFailure.fromException(ValidationException e) =>
      ValidationFailure(
        message: e.message,
        fieldErrors: e.fieldErrors,
        cause: e,
      );
}

final class StorageFailure extends Failure {
  const StorageFailure({required super.message, super.cause});

  factory StorageFailure.fromException(StorageException e) =>
      StorageFailure(message: e.message, cause: e);
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({required super.message, super.cause});

  factory UnexpectedFailure.fromException(AppException e) =>
      UnexpectedFailure(message: e.message, cause: e);
}

// ── Converter helper ───────────────────────────────────────────────────────────

/// Converts any [AppException] subtype to its corresponding [Failure] subtype.
///
/// Use inside repository catch blocks:
/// ```dart
/// } on AppException catch (e) {
///   return Err(failureFromException(e));
/// }
/// ```
Failure failureFromException(AppException e) => switch (e) {
      NetworkException() => NetworkFailure.fromException(e),
      AuthException() => AuthFailure.fromException(e),
      ValidationException() => ValidationFailure.fromException(e),
      StorageException() => StorageFailure.fromException(e),
      UnexpectedException() => UnexpectedFailure.fromException(e),
    };
