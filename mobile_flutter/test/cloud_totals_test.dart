import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/data/cloud_totals.dart';
import 'package:homebudget_flutter/data/firebase_services.dart';

void main() {
  CloudExpense expense({required int? base, required DateTime date,
      bool shared = false, String category = 'food'}) => CloudExpense(
    id: 'test', authorId: 'alice', amountCents: 1000, baseAmountCents: base,
    currency: 'EUR', categoryId: category, description: '', isShared: shared,
    expenseDate: date,
  );

  test('cloud totals use converted cents and exclude older or unconverted expenses', () {
    final now = DateTime(2026, 10, 15, 12);
    final totals = calculateCloudTotals([
      expense(base: 117500, date: DateTime(2026, 10, 2), shared: true),
      expense(base: 2500, date: DateTime(2026, 10, 3), category: 'travel'),
      expense(base: null, date: DateTime(2026, 10, 4)),
      expense(base: 9000, date: DateTime(2026, 9, 30)),
      expense(base: 3000, date: DateTime(2026, 10, 16)),
    ], now);
    expect(totals.monthlyCents, 120000);
    expect(totals.sharedCents, 117500);
    expect(totals.byCategory, {'food': 117500, 'travel': 2500});
    expect(totals.unconvertedCount, 1);
  });

  test('running shared total respects the last reset across month boundaries', () {
    final totals = calculateCloudTotals([
      expense(base: 1000, date: DateTime(2026, 9, 10), shared: true),
      expense(base: 2000, date: DateTime(2026, 9, 25), shared: true),
      expense(base: 3000, date: DateTime(2026, 10, 2), shared: true),
      expense(base: 4000, date: DateTime(2026, 10, 3)),
    ], DateTime(2026, 10, 15), sharedResetAt: DateTime(2026, 9, 20));
    expect(totals.runningSharedCents, 5000);
    expect(totals.sharedCents, 3000);
    expect(totals.monthlyCents, 7000);
  });
}
