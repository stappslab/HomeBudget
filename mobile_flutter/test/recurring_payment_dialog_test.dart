import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/app/recurring_payment_dialog.dart';
import 'package:homebudget_flutter/data/recurring_period.dart';

void main() {
  for (final amount in [40000, 60000, 70000]) {
    testWidgets(
      'confirmation distinguishes a $amount payment from the remaining balance',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await confirmRecurringPayment(
                      context,
                      name: 'Rent',
                      month: '2026-10',
                      currency: 'EUR',
                      amountCents: amount,
                      summary: const RecurringPaymentSummary(
                        expectedCents: 100000,
                        paidCents: 40000,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining(
            amount < 60000
                ? 'partial payment'
                : amount > 60000
                ? 'exceeds the remaining'
                : 'covers the remaining',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(result, false);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm payment'));
        await tester.pumpAndSettle();
        expect(result, true);
      },
    );
  }
}
