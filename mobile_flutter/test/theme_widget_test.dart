import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/app/theme.dart';

void main() {
  testWidgets('light and dark themes render readable budget cards', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: appTheme(brightness: brightness),
        home: const Scaffold(
          body: Card(child: ListTile(
            leading: Icon(Icons.shopping_basket_outlined),
            title: Text('Groceries'),
            subtitle: Text('RSD 12,500.00 remaining'),
          )),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
