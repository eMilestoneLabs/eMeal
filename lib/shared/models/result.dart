import 'package:smart_meal_management/core/errors/failure.dart';

/// Represents the absence of a meaningful return value.
///
/// Used as `Result<Unit>` for repository operations that succeed with no data
/// (logout, delete, mark, etc.).  Avoids the ambiguity of `Result<void>` or
/// `Result<bool>`.
final class Unit {
  const Unit._();

  /// The single shared instance — use this everywhere.
  static const Unit instance = Unit._();
}

// ── Result<T> sealed type ──────────────────────────────────────────────────────

/// Discriminated-union return type for all repository methods.
///
/// Replaces the `dartz` package dependency with a zero-package equivalent
/// that integrates directly with the existing [Failure] hierarchy.
///
/// ## Usage in a repository implementation
///
/// ```dart
/// Future<Result<UserModel>> getProfile() async {
///   try {
///     await _delay();
///     return Ok(MockAuthService.currentUser);
///   } catch (e) {
///     return Err(UnknownFailure(message: e.toString()));
///   }
/// }
/// ```
///
/// ## Usage in a provider
///
/// Pattern-match style (recommended):
/// ```dart
/// final result = await _authRepo.getProfile();
/// switch (result) {
///   case Ok(:final value):
///     _user = value;
///     notifyListeners();
///   case Err(:final failure):
///     _handleFailure(failure);
/// }
/// ```
///
/// Fold style (for inline transforms):
/// ```dart
/// final label = result.fold(
///   (failure) => 'Error: ${failure.message}',
///   (user) => user.name,
/// );
/// ```
sealed class Result<T> {
  const Result();
}

/// The success variant of [Result].  Carries the operation's output value.
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

/// The failure variant of [Result].  Carries a typed [Failure] from the domain
/// error hierarchy — never a raw exception.
final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}

// ── Convenience type aliases ───────────────────────────────────────────────────

/// Shorthand for operations that succeed without returning data.
///
/// ```dart
/// Future<VoidResult> logout() async {
///   ...
///   return const Ok(Unit.instance);
/// }
/// ```
typedef VoidResult = Result<Unit>;

// ── Extension helpers ──────────────────────────────────────────────────────────

extension ResultX<T> on Result<T> {
  /// True when this is an [Ok] result.
  bool get isOk => this is Ok<T>;

  /// True when this is an [Err] result.
  bool get isErr => this is Err<T>;

  /// Returns the success value, or null if this is an [Err].
  T? get valueOrNull => switch (this) {
        Ok(:final value) => value,
        Err() => null,
      };

  /// Returns the failure, or null if this is an [Ok].
  Failure? get failureOrNull => switch (this) {
        Ok() => null,
        Err(:final failure) => failure,
      };

  /// Returns the success value, or [defaultValue] if this is an [Err].
  T getOrElse(T defaultValue) => switch (this) {
        Ok(:final value) => value,
        Err() => defaultValue,
      };

  /// Transforms this result into [R] by applying one of two functions.
  ///
  /// Equivalent to `Either.fold` from the `dartz` package.
  R fold<R>(
    R Function(Failure failure) onErr,
    R Function(T value) onOk,
  ) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };

  /// Maps the success value to a new type.  Leaves [Err] unchanged.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok(:final value) => Ok(transform(value)),
        Err(:final failure) => Err(failure),
      };
}
