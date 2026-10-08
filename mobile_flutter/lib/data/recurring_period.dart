import 'package:flutter/foundation.dart';

String recurringMonth(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

DateTime recurringDueDate(int year, int month, int dueDay) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(
    year,
    month,
    dueDay == 0 ? lastDay : dueDay.clamp(1, lastDay),
  );
}

String normalizeRecurringName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

enum RecurringStatus { upcoming, due, overdue, partial, paid, overpaid }

RecurringStatus recurringStatus({
  required bool paid,
  required DateTime today,
  required DateTime dueDate,
  required int graceDays,
  int paidCents = 0,
  int? expectedCents,
}) {
  if (expectedCents != null && paidCents > expectedCents) {
    return RecurringStatus.overpaid;
  }
  if (paid) return RecurringStatus.paid;
  final day = DateTime(today.year, today.month, today.day);
  final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
  if (day.isAfter(DateTime(due.year, due.month, due.day + graceDays))) {
    return RecurringStatus.overdue;
  }
  if (!day.isBefore(due)) return RecurringStatus.due;
  return paidCents > 0 ? RecurringStatus.partial : RecurringStatus.upcoming;
}

@immutable
class RecurringLink {
  const RecurringLink(this.id, this.month);
  final String id, month;

  @override
  bool operator ==(Object other) =>
      other is RecurringLink && other.id == id && other.month == month;

  @override
  int get hashCode => Object.hash(id, month);
}

/// Values are in the recurring obligation's original currency, not base currency.
class RecurringPaymentSummary {
  const RecurringPaymentSummary({
    required this.expectedCents,
    required this.paidCents,
  });
  final int expectedCents, paidCents;
  int get remainingCents => (expectedCents - paidCents).clamp(0, expectedCents);
  int get overpaidCents => (paidCents - expectedCents).clamp(0, paidCents);
  bool get settled => paidCents >= expectedCents;
}
