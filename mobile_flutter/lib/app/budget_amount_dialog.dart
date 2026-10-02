import 'package:flutter/material.dart';

import '../utils/money.dart';

Future<int?> showBudgetAmountDialog(BuildContext context, {
  required String title,
  required String currency,
  int? current,
}) {
  var amount = current == null ? '' : (current / 100).toStringAsFixed(2);
  return showDialog<int>(context: context, builder: (dialogContext) => AlertDialog(
    title: Text('$title budget'),
    content: TextFormField(initialValue: amount,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: 'Amount in $currency'),
      onChanged: (value) => amount = value),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(dialogContext, parseCents(amount)),
        child: const Text('Save')),
    ],
  ));
}
