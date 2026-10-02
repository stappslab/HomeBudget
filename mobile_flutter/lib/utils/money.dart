import 'package:intl/intl.dart';

const supportedCurrencies = ['RSD', 'EUR', 'USD', 'BAM', 'CHF'];

String money(int cents, String currency) => NumberFormat.currency(
      locale: 'en_US', name: currency, symbol: currency, decimalDigits: 2,
    ).format(cents / 100);

int? parseCents(String raw) {
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

/// Parses a positive exchange rate with up to six decimal places.
/// One rate unit is stored as 1,000,000 micros to avoid double rounding.
int? parseRateMicros(String raw) {
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
