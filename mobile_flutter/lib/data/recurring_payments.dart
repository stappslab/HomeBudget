import 'firebase_services.dart';
import 'recurring_period.dart';

Map<String, List<CloudExpense>> groupRecurringPayments(
  Iterable<CloudExpense> expenses,
  String month,
) {
  final grouped = <String, List<CloudExpense>>{};
  for (final expense in expenses) {
    if (expense.recurringId != null && expense.recurringMonth == month) {
      (grouped[expense.recurringId!] ??= []).add(expense);
    }
  }
  return grouped;
}

RecurringPaymentSummary summarizeRecurringPayments(
  CloudRecurringTemplate effective,
  Iterable<CloudExpense> payments, {
  String? excludeExpenseId,
}) => RecurringPaymentSummary(
  expectedCents: effective.amountCents,
  paidCents: payments
      .where(
        (expense) =>
            expense.id != excludeExpenseId &&
            expense.currency == effective.currency,
      )
      .fold<int>(0, (sum, expense) => sum + expense.amountCents),
);

List<CloudRecurringTemplate> recurringCandidates(
  Iterable<CloudRecurringTemplate> templates, {
  required String month,
  required String categoryId,
  required String currency,
  required bool shared,
  required String description,
}) {
  final text = normalizeRecurringName(description);
  return templates
      .where(
        (item) =>
            !item.archived &&
            item.startMonth.compareTo(month) <= 0 &&
            item.categoryId == categoryId &&
            item.currency == currency &&
            item.isShared == shared &&
            (text.isEmpty || normalizeRecurringName(item.name) == text),
      )
      .toList();
}
