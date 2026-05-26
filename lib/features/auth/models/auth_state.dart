import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/features/auth/models/auth_session.dart';

enum AuthPhase { unknown, unauthenticated, authenticated }

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.session});
  final AuthSession session;
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthError extends AuthState {
  const AuthError({required this.failure});
  final Failure failure;
}
