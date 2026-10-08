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

  test('shared spending compares members for this month and since reset', () {
    CloudExpense by(String uid, String name, int cents, DateTime date,
        {bool shared = true}) => CloudExpense(
      id: '$uid-${date.day}', authorId: uid, authorName: name,
      amountCents: cents, baseAmountCents: cents, currency: 'RSD',
      categoryId: 'food', description: '', isShared: shared, expenseDate: date);
    final result = calculateMemberSharedSpending([
      by('alice', 'Alice', 1000, DateTime(2026, 9, 10)),
      by('alice', 'Alice', 2000, DateTime(2026, 9, 25)),
      by('alice', 'Alice', 3000, DateTime(2026, 10, 2)),
      by('bob', 'Bob', 4500, DateTime(2026, 10, 3)),
      by('bob', 'Bob', 9000, DateTime(2026, 10, 4), shared: false),
    ], DateTime(2026, 10, 15), sharedResetAt: DateTime(2026, 9, 20));
    expect(result['alice']?.monthlyCents, 3000);
    expect(result['alice']?.runningCents, 5000);
    expect(result['bob']?.monthlyCents, 4500);
    expect(result['bob']?.runningCents, 4500);
  });
}
