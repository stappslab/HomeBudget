import 'package:intl/intl.dart';

const supportedCurrencies = ['RSD', 'EUR', 'USD', 'BAM', 'CHF'];

String money(int cents, String currency) => NumberFormat.currency(
      locale: 'en_US', name: currency, symbol: currency, decimalDigits: 2,
    ).format(cents / 100);

int? parseCents(String raw) {
  if (raw.length > 32) return null;
  var value = raw.trim().replaceAll(RegExp(r'[\s\u00a0]'), '');
  if (value.contains(',') && value.contains('.')) {
    value = value.lastIndexOf(',') > value.lastIndexOf('.')
        ? value.replaceAll('.', '').replaceAll(',', '.')
        : value.replaceAll(',', '');
  } else {
    value = value.replaceAll(',', '.');
  }
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final units = int.tryParse(parts.first);
  final cents = int.tryParse((parts.length > 1 ? parts.last : '').padRight(2, '0'));
  if (units == null || cents == null) return null;
  return units * 100 + cents;
}

/// Budget entry also accepts common thousands grouping, such as 50.000 or
/// 50,000. Expense amounts keep the stricter parser above.
int? parseBudgetCents(String raw) {
  if (raw.length > 32) return null;
  final value = raw.trim().replaceAll(RegExp(r'[\s\u00a0]'), '');
  if (RegExp(r'^\d{1,3}([.,]\d{3})+([.,]\d{1,2})?$').hasMatch(value)) {
    final separator = value.lastIndexOf(RegExp(r'[.,]'));
    final hasDecimals = value.length - separator - 1 <= 2;
    final whole = hasDecimals ? value.substring(0, separator) : value;
    final fraction = hasDecimals ? value.substring(separator + 1) : '';
    final normalized = whole.replaceAll(RegExp(r'[.,]'), '');
    return parseCents(hasDecimals ? '$normalized.$fraction' : normalized);
  }
  return parseCents(value);
}

/// Parses a positive exchange rate with up to six decimal places.
/// One rate unit is stored as 1,000,000 micros to avoid double rounding.
int? parseRateMicros(String raw) {
  if (raw.length > 32) return null;
  final value = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final units = int.tryParse(parts.first);
  final fraction = int.tryParse((parts.length > 1 ? parts.last : '').padRight(6, '0'));
  if (units == null || fraction == null) return null;
  final micros = units * 1000000 + fraction;
  return micros > 0 ? micros : null;
}

int convertCents(int amountCents, int rateMicros) =>
    (amountCents * rateMicros + 500000) ~/ 1000000;
