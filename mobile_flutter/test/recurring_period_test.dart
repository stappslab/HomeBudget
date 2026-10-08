import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/data/recurring_period.dart';

void main() {
  test('month keys and end-of-month due dates are stable', () {
    expect(recurringMonth(DateTime(2026, 2, 28)), '2026-02');
    expect(recurringDueDate(2028, 2, 0), DateTime(2028, 2, 29));
    expect(recurringDueDate(2026, 2, 0), DateTime(2026, 2, 28));
  });

  test('payment status respects due date and grace days', () {
    final due = DateTime(2026, 10, 1);
    expect(recurringStatus(paid: false, today: DateTime(2026, 9, 30),
      dueDate: due, graceDays: 3), RecurringStatus.upcoming);
    expect(recurringStatus(paid: false, today: DateTime(2026, 10, 4),
      dueDate: due, graceDays: 3), RecurringStatus.due);
    expect(recurringStatus(paid: false, today: DateTime(2026, 10, 5),
      dueDate: due, graceDays: 3), RecurringStatus.overdue);
    expect(recurringStatus(paid: true, today: DateTime(2026, 10, 5),
      dueDate: due, graceDays: 3), RecurringStatus.paid);
  });

  test('description matching ignores case and repeated whitespace', () {
    expect(normalizeRecurringName('  RENT   October '), 'rent october');
    expect(normalizeRecurringName('Rent'), normalizeRecurringName('  rent  '));
  });
}
