/// Centralized authentication field validators.
///
/// Single source of truth for SRS Module 01 — Part 6 (Field Validation & Input
/// Specifications). Used by every auth form so rules stay consistent (DRY) and
/// match the backend DTO contracts exactly (no client/server drift):
///   - Full Name : 2–30 chars, letters/spaces only (FV / Part 3)
///   - Email     : RFC-ish, trimmed/lowercased (FV)
///   - Mobile    : 10 digits (FV-007 digits only)
///   - Password  : min 8 (backend MinLength(8); strength meter advises further)
///   - Age       : 13–99, under-13 blocked (AUTH-018); admin min 18
///
/// Each method returns `null` when valid, or a user-facing message when not.
library;

import 'package:smart_meal_management/features/auth/widgets/password_strength_indicator.dart';

abstract final class AuthValidators {
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _nameRe = RegExp(r"^[A-Za-z][A-Za-z .'-]*$");

  static String? name(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Enter your full name';
    if (v.length < 2) return 'Name must be at least 2 characters';
    if (v.length > 30) return 'Name must be 30 characters or fewer';
    if (!_nameRe.hasMatch(v)) return 'Use letters and spaces only';
    return null;
  }

  static String? email(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Enter your email address';
    if (!_emailRe.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// 10-digit mobile (digits-only is enforced at the input layer too).
  static String? mobile(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Enter your mobile number';
    if (!RegExp(r'^\d{10}$').hasMatch(v)) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  /// Strong-password policy (AUTH / Issue 4): min 8 chars AND not "weak" — i.e.
  /// at least two character classes (letters + a number/uppercase/symbol). Weak
  /// passwords are rejected for both account creation and password reset.
  static String? password(String value) {
    if (value.isEmpty) return 'Enter a password';
    if (value.length < 8) return 'Password must be at least 8 characters';
    final strength = PasswordStrengthIndicator.strengthOf(value);
    if (strength.index <= PasswordStrength.weak.index) {
      return 'Too weak — add a number or a capital letter';
    }
    return null;
  }

  static String? confirmPassword(String value, String original) {
    if (value.isEmpty) return 'Re-enter your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  /// Age range per AUTH-018 / Part 3. [min] is 13 for students, 18 for admins.
  static String? age(String value, {int min = 13, int max = 99}) {
    final v = value.trim();
    if (v.isEmpty) return 'Enter your age';
    final n = int.tryParse(v);
    if (n == null) return 'Age must be a number';
    if (n < min) {
      return min >= 18
          ? 'You must be at least $min years old'
          : 'You must be at least 13 years old to register';
    }
    if (n > max) return 'Enter an age of $max or below';
    return null;
  }

  static String? required(String value, String message) =>
      value.trim().isEmpty ? message : null;

  /// Live variant: suppress the error on an empty field the user hasn't filled
  /// yet (avoids premature "required" nagging) while still flagging invalid
  /// content as it is typed (FV-001).
  static String? live(String value, String? Function(String) validator) =>
      value.trim().isEmpty ? null : validator(value);
}
