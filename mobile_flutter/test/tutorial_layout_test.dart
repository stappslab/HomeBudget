import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homebudget_flutter/app/tutorial_page.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(320, 640),
    const Size(280, 520),
    const Size(240, 480),
  ]) {
    testWidgets('tutorial pages fit a ${size.width}x${size.height} screen', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.4),
            ),
            child: const AppTutorialPage(),
          ),
        ),
      );
      for (
        var page = 0;
        page < tutorialSteps(TutorialTopic.all).length;
        page++
      ) {
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Tutorial page $page overflowed',
        );
        if (page < tutorialSteps(TutorialTopic.all).length - 1) {
          await tester.tap(find.text('Next'));
        }
      }
    });
  }
}
