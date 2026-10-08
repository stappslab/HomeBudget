const maxEmailLength = 254;
const maxPasswordLength = 128;
const minNewPasswordLength = 15;
const maxDisplayNameLength = 60;
const maxHouseholdNameLength = 80;
const maxCategoryNameLength = 40;
const maxRecurringNameLength = 60;
const maxExpenseDescriptionLength = 500;
const maxInviteCodeLength = 64;

final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');
final _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? emailInputError(String raw) {
  final email = raw.trim();
  if (email.isEmpty || email.length > maxEmailLength ||
      _controlCharacters.hasMatch(email) || !_emailShape.hasMatch(email)) {
    return 'Enter a valid email address (up to $maxEmailLength characters).';
  }
  return null;
}

String? passwordInputError(String password, {required bool creating}) {
  final length = password.runes.length;
  if (length > maxPasswordLength) {
    return 'Password must be at most $maxPasswordLength characters.';
  }
  if (creating && length < minNewPasswordLength) {
    return 'Use at least $minNewPasswordLength characters for a new password.';
  }
  if (length == 0) return 'Enter your password.';
  return null;
}

String? textInputError(String raw, {
  required String label,
  required int maximum,
  bool optional = false,
}) {
  final value = raw.trim();
  if (!optional && value.isEmpty) return 'Enter $label.';
  if (value.runes.length > maximum) {
    return '$label must be at most $maximum characters.';
  }
  if (_controlCharacters.hasMatch(value)) {
    return '$label cannot contain control characters or line breaks.';
  }
  return null;
}
