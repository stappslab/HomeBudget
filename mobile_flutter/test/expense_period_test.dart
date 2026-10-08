import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/utils/expense_period.dart';

void main() {
  final now = DateTime(2026, 10, 2, 18);

  test('month includes its first and last day, not adjacent months', () {
    final period = ExpensePeriod(
      mode: ExpensePeriodMode.month, month: DateTime(2026, 9));
    expect(period.includes(DateTime(2026, 9, 1), now), isTrue);
    expect(period.includes(DateTime(2026, 9, 30, 23), now), isTrue);
    expect(period.includes(DateTime(2026, 10, 1), now), isFalse);
  });

  test('last 30 days spans month boundary inclusively', () {
    final period = ExpensePeriod(
      mode: ExpensePeriodMode.last30Days, month: DateTime(2026, 10));
    expect(period.includes(DateTime(2026, 9, 3), now), isTrue);
    expect(period.includes(DateTime(2026, 9, 2), now), isFalse);
    expect(period.includes(DateTime(2026, 10, 2), now), isTrue);
  });

  test('custom range is inclusive and all time has no bounds', () {
    final custom = ExpensePeriod(mode: ExpensePeriodMode.custom,
      month: DateTime(2026, 10), customRange: DateTimeRange(
        start: DateTime(2026, 8, 15), end: DateTime(2026, 9, 5)));
    expect(custom.includes(DateTime(2026, 8, 15), now), isTrue);
    expect(custom.includes(DateTime(2026, 9, 5, 23), now), isTrue);
    expect(custom.includes(DateTime(2026, 9, 6), now), isFalse);
    final all = ExpensePeriod(mode: ExpensePeriodMode.allTime,
      month: DateTime(2026, 10));
    expect(all.includes(DateTime(2020), now), isTrue);
  });
}
