import 'package:flutter/material.dart';

enum ExpensePeriodMode { month, last30Days, allTime, custom }

class ExpensePeriod {
  const ExpensePeriod({required this.mode, required this.month, this.customRange});

  final ExpensePeriodMode mode;
  final DateTime month;
  final DateTimeRange? customRange;

  DateTimeRange? range(DateTime now) => switch (mode) {
    ExpensePeriodMode.month => DateTimeRange(
      start: DateTime(month.year, month.month),
      end: DateTime(month.year, month.month + 1, 0)),
    ExpensePeriodMode.last30Days => DateTimeRange(
      start: DateTime(now.year, now.month, now.day - 29),
      end: DateTime(now.year, now.month, now.day)),
    ExpensePeriodMode.allTime => null,
    ExpensePeriodMode.custom => customRange,
  };

  bool includes(DateTime date, DateTime now) {
    final selected = range(now);
    if (selected == null) return true;
    final day = DateUtils.dateOnly(date);
    return !day.isBefore(DateUtils.dateOnly(selected.start)) &&
      !day.isAfter(DateUtils.dateOnly(selected.end));
  }
}
