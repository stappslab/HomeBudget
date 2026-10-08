import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/utils/input_limits.dart';

void main() {
  test('email rejects malformed and oversized values', () {
    expect(emailInputError('name@example.com'), isNull);
    expect(emailInputError('no-at-sign'), isNotNull);
    expect(emailInputError('${'a' * 250}@example.com'), isNotNull);
    expect(emailInputError('a\nb@example.com'), isNotNull);
  });

  test('new passwords use length without composition restrictions', () {
    expect(passwordInputError('short', creating: true), isNotNull);
    expect(passwordInputError('correct horse battery staple', creating: true), isNull);
    expect(passwordInputError('🔒' * 15, creating: true), isNull);
    expect(passwordInputError('a' * 129, creating: false), isNotNull);
    expect(passwordInputError('oldpass', creating: false), isNull);
  });

  test('names and descriptions reject excess length and control characters', () {
    expect(textInputError('  ', label: 'Name', maximum: 40), isNotNull);
    expect(textInputError('a' * 41, label: 'Name', maximum: 40), isNotNull);
    expect(textInputError('Name\nNext', label: 'Name', maximum: 40), isNotNull);
    expect(textInputError('Dinner 🍲', label: 'Name', maximum: 40), isNull);
    expect(textInputError('', label: 'Description', maximum: 500, optional: true), isNull);
    expect(textInputError('a' * 501, label: 'Description', maximum: 500,
      optional: true), isNotNull);
  });
}
