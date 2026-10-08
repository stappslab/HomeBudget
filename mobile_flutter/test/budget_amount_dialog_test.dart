import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/app/budget_amount_dialog.dart';

void main() {
  testWidgets('saving a category budget closes only the dialog', (tester) async {
    int? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(onPressed: () async {
        saved = await showBudgetAmountDialog(context,
          title: 'Groceries', currency: 'RSD');
      }, child: const Text('Set budget')),
    ))));

    await tester.tap(find.text('Set budget'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '5000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, 500000);
    expect(find.text('Set budget'), findsOneWidget);
    expect(find.text('Groceries budget'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid budget stays open and explains the error', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(onPressed: () => showBudgetAmountDialog(context,
        title: 'Monthly', currency: 'RSD'), child: const Text('Set budget')),
    ))));

    await tester.tap(find.text('Set budget'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'not a number');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Monthly budget'), findsOneWidget);
    expect(find.text('Enter an amount up to 10,000,000.00.'), findsOneWidget);
  });
}
