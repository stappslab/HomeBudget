import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/data/cloud_totals.dart';
import 'package:homebudget_flutter/data/firebase_services.dart';

void main() {
  test('monthly totals remain correct with years of expense history', () {
    final now = DateTime(2026, 10, 15);
    for (final size in [100, 1000, 10000]) {
      final expenses = List.generate(size, (index) => CloudExpense(
        id: '$index', authorId: index.isEven ? 'a' : 'b',
        authorName: index.isEven ? 'Alex' : 'Sam',
        amountCents: 100, baseAmountCents: 100,
        currency: 'EUR', categoryId: 'home',
        description: 'Receipt $index', isShared: index.isEven,
        expenseDate: DateTime(2026, 10 - index ~/ 40, 1),
      ));
      final recentStart = DateTime(now.year, now.month - 5);
      final recent = expenses.where((expense) =>
        !expense.expenseDate.isBefore(recentStart)).toList();
      final fullScan = Stopwatch()..start();
      final fullTotals = calculateCloudTotals(expenses, now);
      fullScan.stop();
      final recentScan = Stopwatch()..start();
      final recentTotals = calculateCloudTotals(recent, now);
      final members = calculateMemberSharedSpending(recent, now);
      recentScan.stop();
      expect(recentTotals.monthlyCents, fullTotals.monthlyCents);
      expect(recentTotals.byCategory, fullTotals.byCategory);
      expect(members['a']?.monthlyCents, 2000);
      expect(recent.length, lessThanOrEqualTo(240));
      // Timings are diagnostic; CI and phone hardware have different speeds.
      // ignore: avoid_print
      print('scale=$size recent=${recent.length} '
        'full_scan_us=${fullScan.elapsedMicroseconds} '
        'recent_scan_us=${recentScan.elapsedMicroseconds}');
    }
  });
}
