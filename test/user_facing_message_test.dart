// Raw exception text must never reach a user; messages the app raises on
// purpose (AppException) are shown as written.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/core/errors/app_exception.dart';

void main() {
  const fallback = 'Something went wrong';

  test('an app-raised error shows its own message', () {
    expect(
      userFacingMessage(
        const UnexpectedException(
          message: 'Too many entries. Choose a shorter range.',
        ),
        fallback: fallback,
      ),
      'Too many entries. Choose a shorter range.',
    );
    expect(
      userFacingMessage(
        const NetworkException(message: 'No internet connection'),
        fallback: fallback,
      ),
      'No internet connection',
    );
  });

  test('raw exceptions never leak their technical text', () {
    for (final raw in <Object>[
      Exception('Null check operator used on a null value'),
      StateError('Bad state: stream closed'),
      const FileSystemException('Cannot open file', '/data/user/0/x.pdf'),
      'plain string error',
    ]) {
      final shown = userFacingMessage(raw, fallback: fallback);
      expect(shown, fallback, reason: '$raw');
      expect(shown.contains('Exception'), isFalse);
    }
  });
}
