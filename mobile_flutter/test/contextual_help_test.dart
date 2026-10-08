import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/app/tutorial_page.dart';
import 'package:homebudget_flutter/app/budget_amount_dialog.dart';

void main() {
  test(
    'context topics are subsets of the full tutorial, with no duplicate slides',
    () {
      final full = tutorialSteps(TutorialTopic.all);
      expect(full.toSet().length, full.length);
      for (final topic in TutorialTopic.values) {
        final selected = tutorialSteps(topic);
        expect(selected, isNotEmpty);
        expect(selected.toSet().length, selected.length);
        expect(selected.every(full.contains), true);
      }
      expect(tutorialSteps(TutorialTopic.plan), [2]);
      expect(tutorialSteps(TutorialTopic.recurring), [6, 7, 8, 9, 11]);
    },
  );
  for (final topic in TutorialTopic.values.where(
    (t) => t != TutorialTopic.all,
  )) {
    testWidgets('${topic.name} help fits a small screen with enlarged text', (
      tester,
    ) async {
      const size = Size(240, 480);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(1.4),
            ),
            child: AppTutorialPage(topic: topic),
          ),
        ),
      );
      for (var step = 0; step < tutorialSteps(topic).length; step++) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$topic step $step');
        expect(find.text(tutorialTitle(topic)), findsOneWidget);
        if (step < tutorialSteps(topic).length - 1) {
          await tester.tap(find.text('Next'));
        }
      }
      expect(find.text('Back to screen'), findsOneWidget);
    });
  }
  testWidgets(
    'context help and full-tour replacement preserve the underlying expense draft',
    (tester) async {
      final draft = TextEditingController();
      addTearDown(draft.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: draft),
                const TutorialHelpButton(topic: TutorialTopic.payment),
              ],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Rent draft');
      await tester.tap(find.byTooltip('Expense help'));
      await tester.pumpAndSettle();
      expect(find.text('Expense help'), findsOneWidget);
      expect(find.text('1 / 5'), findsOneWidget);
      await tester.tap(find.byTooltip('More help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full tutorial'));
      await tester.pumpAndSettle();
      expect(find.text('How HomeBudget works'), findsOneWidget);
      expect(find.text('1 / 14'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(AppTutorialPage), findsNothing);
      expect(draft.text, 'Rent draft');
    },
  );
  testWidgets('closing plan help returns to the unchanged budget dialog', (
    tester,
  ) async {
    int? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showBudgetAmountDialog(
                  context,
                  title: 'Home',
                  currency: 'RSD',
                );
              },
              child: const Text('Budget'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '50000');
    await tester.tap(find.byTooltip('Plan help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to screen'));
    await tester.pumpAndSettle();
    expect(find.text('50000'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 5000000);
  });
}
