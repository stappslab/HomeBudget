import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:homebudget_flutter/data/firebase_services.dart';
import 'package:homebudget_flutter/data/recurring_payments.dart';
import 'package:homebudget_flutter/data/recurring_period.dart';
import 'package:homebudget_flutter/data/cloud_totals.dart';

CloudRecurringTemplate template({
  String id = 'rent',
  String name = 'Rent',
  String category = 'home',
}) => CloudRecurringTemplate(
  id: id,
  name: name,
  categoryId: category,
  amountCents: 100000,
  currency: 'EUR',
  dueDay: 5,
  graceDays: 3,
  isShared: true,
  startMonth: '2026-10',
  archived: false,
);
CloudExpense payment(
  String id,
  int amount, {
  String? recurringId = 'rent',
  String month = '2026-10',
}) => CloudExpense(
  id: id,
  authorId: 'john',
  amountCents: amount,
  baseAmountCents: amount * 117,
  rateToBaseMicros: 117000000,
  currency: 'EUR',
  categoryId: 'home',
  description: 'Rent',
  isShared: true,
  expenseDate: DateTime(2026, 10, 5),
  recurringId: recurringId,
  recurringMonth: recurringId == null ? null : month,
);

void main() {
  test(
    'partial payments, edits, deletion and unlink recompute from real expenses',
    () {
      final t = template();
      final first = payment('one', 40000);
      final second = payment('two', 60000);
      expect(summarizeRecurringPayments(t, [first]).remainingCents, 60000);
      expect(summarizeRecurringPayments(t, [first, second]).settled, true);
      expect(
        summarizeRecurringPayments(t, [
          first,
          second,
        ], excludeExpenseId: 'two').paidCents,
        40000,
      );
      expect(
        summarizeRecurringPayments(t, [
          payment('one', 30000),
          second,
        ]).remainingCents,
        10000,
      );
      expect(summarizeRecurringPayments(t, [second]).remainingCents, 40000);
      final grouped = groupRecurringPayments([
        first,
        payment('two', 60000, recurringId: null),
      ], '2026-10');
      expect(
        summarizeRecurringPayments(t, grouped['rent']!).remainingCents,
        60000,
      );
      // An unlinked expense remains spending. A deleted expense cannot contribute.
      expect(
        calculateCloudTotals([
          first,
          payment('two', 60000, recurringId: null),
        ], DateTime(2026, 10, 20)).monthlyCents,
        11700000,
      );
      expect(
        calculateCloudTotals([first], DateTime(2026, 10, 20)).monthlyCents,
        4680000,
      );
    },
  );
  test(
    'overpayment never creates negative remaining and statuses respect due date',
    () {
      final summary = summarizeRecurringPayments(template(), [
        payment('one', 110000),
      ]);
      expect(summary.remainingCents, 0);
      expect(summary.overpaidCents, 10000);
      expect(
        recurringStatus(
          paid: summary.settled,
          paidCents: summary.paidCents,
          expectedCents: summary.expectedCents,
          today: DateTime(2026, 10, 20),
          dueDate: DateTime(2026, 10, 5),
          graceDays: 3,
        ),
        RecurringStatus.overpaid,
      );
      expect(
        recurringStatus(
          paid: false,
          paidCents: 40000,
          expectedCents: 100000,
          today: DateTime(2026, 10, 3),
          dueDate: DateTime(2026, 10, 5),
          graceDays: 3,
        ),
        RecurringStatus.partial,
      );
      expect(
        recurringStatus(
          paid: false,
          paidCents: 40000,
          expectedCents: 100000,
          today: DateTime(2026, 10, 9),
          dueDate: DateTime(2026, 10, 5),
          graceDays: 3,
        ),
        RecurringStatus.overdue,
      );
    },
  );
  test(
    'matching is exact after normalization, blank descriptions allow several candidates',
    () {
      List<CloudRecurringTemplate> match(
        String description, {
        String currency = 'EUR',
        bool shared = true,
      }) => recurringCandidates(
        [template(), template(id: 'mortgage', name: 'Mortgage')],
        month: '2026-10',
        categoryId: 'home',
        currency: currency,
        shared: shared,
        description: description,
      );
      expect(match('  RENT  ').single.id, 'rent');
      expect(match('').length, 2);
      expect(match('Rent October'), isEmpty);
      expect(match('Rent', currency: 'RSD'), isEmpty);
      expect(match('Rent', shared: false), isEmpty);
    },
  );
  test('monthly snapshot survives future template changes', () {
    const snapshot = CloudRecurringOccurrence(
      recurringId: 'rent',
      month: '2026-10',
      pendingSync: false,
      expectedCents: 80000,
      name: 'Rent',
      categoryId: 'dining',
      currency: 'EUR',
      isShared: true,
    );
    final effective = snapshot.effectiveTemplate(template());
    expect(effective.amountCents, 80000);
    expect(effective.categoryId, 'dining');
    expect(
      summarizeRecurringPayments(effective, [
        payment('one', 40000),
      ]).remainingCents,
      40000,
    );
  });
  for (final count in [100, 1000, 10000]) {
    test('$count records group correctly without a hidden page cap', () {
      final records = List.generate(
        count,
        (i) => payment('p$i', 100, month: i.isEven ? '2026-10' : '2026-09'),
      );
      final clock = Stopwatch()..start();
      final grouped = groupRecurringPayments(records, '2026-10');
      final summary = summarizeRecurringPayments(template(), grouped['rent']!);
      clock.stop();
      expect(summary.paidCents, count ~/ 2 * 100);
      // Timing is diagnostic, not a benchmark of an Android phone or Firestore network.
      debugPrint('$count records: ${clock.elapsedMicroseconds} microseconds');
    });
  }
}
