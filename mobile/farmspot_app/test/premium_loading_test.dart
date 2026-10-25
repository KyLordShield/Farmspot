import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/widgets/lottie_loader.dart';

void main() {
  testWidgets(
    'blocking action shows branded loading, blocks back, then closes only its overlay',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  calls++;
                  await withFarmLottieLoading(
                    context,
                    () => pending.future,
                    message: 'Saving alert settings...',
                  );
                },
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.byType(FarmLottieLoading), findsOneWidget);
      expect(find.text('Saving alert settings...'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(FarmLottieLoading), findsOneWidget);
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(FarmLottieLoading), findsNothing);
      expect(find.text('Save'), findsOneWidget);
    },
  );
  testWidgets('failure dismisses loader, preserves screen, and allows retry', (
    tester,
  ) async {
    var pending = Completer<void>();
    var errors = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                try {
                  await withFarmLottieLoading(
                    context,
                    () => pending.future,
                    message: 'Posting your request...',
                  );
                } catch (_) {
                  errors++;
                }
              },
              child: const Text('Post'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Post'));
    await tester.pump();
    pending.completeError(Exception('Connection failed'));
    await tester.pumpAndSettle();
    expect(errors, 1);
    expect(find.byType(FarmLottieLoading), findsNothing);
    expect(find.text('Post'), findsOneWidget);
    pending = Completer<void>();
    await tester.tap(find.text('Post'));
    await tester.pump();
    expect(find.byType(FarmLottieLoading), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(FarmLottieLoading), findsNothing);
  });
  testWidgets(
    'session navigation during an action never pops the replacement screen',
    (tester) async {
      final pending = Completer<void>();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await withFarmLottieLoading(
                    context,
                    () => pending.future,
                    message: 'Saving...',
                  );
                },
                child: const Text('Begin'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Begin'));
      await tester.pump();
      nav.currentState!.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Sign in again')),
        ),
        (_) => false,
      );
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.byType(FarmLottieLoading), findsNothing);
    },
  );
}
