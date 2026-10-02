import 'firebase_services.dart';

class CloudTotals {
  const CloudTotals({required this.monthlyCents, required this.sharedCents,
    required this.runningSharedCents, required this.byCategory,
    required this.unconvertedCount});
  final int monthlyCents;
  final int sharedCents;
  final int runningSharedCents;
  final Map<String, int> byCategory;
  final int unconvertedCount;
}

CloudTotals calculateCloudTotals(List<CloudExpense> expenses, DateTime now,
    {DateTime? sharedResetAt}) {
  var monthly = 0;
  var shared = 0;
  var runningShared = 0;
  var unconverted = 0;
  final byCategory = <String, int>{};
  for (final expense in expenses) {
    final date = expense.expenseDate;
    if (date.isAfter(now)) continue;
    final base = expense.baseAmountCents;
    if (expense.isShared && base != null &&
        !date.isBefore(sharedResetAt ?? DateTime.utc(2000))) {
      runningShared += base;
    }
    if (date.year != now.year || date.month != now.month) continue;
    if (base == null) {
      unconverted++;
      continue;
    }
    monthly += base;
    if (expense.isShared) shared += base;
    byCategory.update(expense.categoryId, (value) => value + base, ifAbsent: () => base);
  }
  return CloudTotals(monthlyCents: monthly, sharedCents: shared,
    runningSharedCents: runningShared,
    byCategory: byCategory, unconvertedCount: unconverted);
}
