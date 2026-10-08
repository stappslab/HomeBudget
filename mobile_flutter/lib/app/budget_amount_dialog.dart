import 'package:flutter/material.dart';

import '../utils/money.dart';
import 'tutorial_page.dart';

Future<int?> showBudgetAmountDialog(
  BuildContext context, {
  required String title,
  required String currency,
  int? current,
}) {
  var amount = current == null ? '' : (current / 100).toStringAsFixed(2);
  String? validationError;
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text('$title budget')),
            const TutorialHelpButton(topic: TutorialTopic.plan),
          ],
        ),
        content: TextFormField(
          initialValue: amount,
          maxLength: 20,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount in $currency',
            hintText: 'e.g. 50000 or 50,000.00',
            errorText: validationError,
          ),
          onChanged: (value) => update(() {
            amount = value;
            validationError = null;
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final cents = parseBudgetCents(amount);
              if (cents == null || cents > 1000000000) {
                update(
                  () =>
                      validationError = 'Enter an amount up to 10,000,000.00.',
                );
                return;
              }
              Navigator.pop(dialogContext, cents);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
