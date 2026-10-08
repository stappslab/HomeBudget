import 'package:flutter/material.dart';
import '../data/recurring_period.dart';
import '../utils/money.dart';
import 'tutorial_page.dart';

Future<bool> confirmRecurringPayment(
  BuildContext context, {
  required String name,
  required String month,
  required String currency,
  required RecurringPaymentSummary summary,
  required int amountCents,
}) async {
  final excess = amountCents - summary.remainingCents;
  final message = summary.settled
      ? 'This month is already paid. This additional payment will exceed the expected amount by ${money(summary.overpaidCents + amountCents, currency)}.'
      : excess > 0
      ? 'This payment exceeds the remaining amount by ${money(excess, currency)}. Confirm that it belongs to this recurring item.'
      : excess < 0
      ? 'Record a partial payment? ${money(-excess, currency)} will remain unpaid.'
      : 'This payment covers the remaining amount for this month.';
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text('Link to $name?')),
              const TutorialHelpButton(topic: TutorialTopic.recurring),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'Payment month: $month\n'
              'Expected: ${money(summary.expectedCents, currency)}\n'
              'Already paid: ${money(summary.paidCents, currency)}\n'
              'This payment: ${money(amountCents, currency)}\n\n$message\n\n'
              'This expense counts once toward this monthly item.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm payment'),
            ),
          ],
        ),
      ) ??
      false;
}
