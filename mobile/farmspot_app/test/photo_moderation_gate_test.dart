import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:farmspot_app/services/photo_moderation.dart';
import 'package:farmspot_app/widgets/photo_moderation_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'debug dialog displays ordered scores and copies results without overriding blocking',
    (tester) async {
      final safe = XFile('safe.jpg');
      final flagged = XFile('flagged.jpg');
      final broken = XFile('broken.jpg');
      List<XFile>? accepted;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  accepted = await screenPhotos(
                    context,
                    [safe, flagged, broken],
                    inspect: (photo) async {
                      if (photo == broken) throw StateError('Internal failure');
                      return PhotoModerationResult(
                        score: photo == safe ? 0.125 : 0.85,
                        elapsedMilliseconds: photo == safe ? 12 : 24,
                      );
                    },
                  );
                },
                child: const Text('Select photos'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select photos'));
      await tester.pumpAndSettle();
      expect(find.text('Photo check results (debug)'), findsOneWidget);
      expect(find.text('Block at 0.30 or above.'), findsOneWidget);
      expect(find.text('Photo 1 — ALLOWED'), findsOneWidget);
      expect(find.text('Photo 2 — BLOCKED'), findsOneWidget);
      expect(find.text('Photo 3 — CHECK FAILED — BLOCKED'), findsOneWidget);
      expect(find.textContaining('Score: 0.1250'), findsOneWidget);
      expect(find.textContaining('Score: 0.8500'), findsOneWidget);
      expect(find.textContaining('Score: unavailable'), findsOneWidget);
      expect(find.textContaining('Internal failure'), findsNothing);
      expect(accepted, isNull);
      await tester.tap(find.text('Copy results'));
      await tester.pumpAndSettle();
      expect(
        copied,
        contains(
          'Photo 1: score=0.1250 threshold=0.3 decision=ALLOWED elapsedMs=12',
        ),
      );
      expect(copied, contains('Photo 2: score=0.8500'));
      expect(copied, contains('Photo 3: score=unavailable'));
      expect(copied, isNot(contains('safe.jpg')));
      expect(find.text('Copied'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(accepted, [safe]);
      expect(find.text('Photo check results (debug)'), findsNothing);
    },
  );

  testWidgets('diagnostics can be hidden without changing the result', (
    tester,
  ) async {
    List<XFile>? accepted;
    final photo = XFile('safe.jpg');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                accepted = await screenPhotos(
                  context,
                  [photo],
                  showDebugResults: false,
                  inspect: (_) async => const PhotoModerationResult(
                    score: 0.1,
                    elapsedMilliseconds: 10,
                  ),
                );
              },
              child: const Text('Select photos'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select photos'));
    await tester.pumpAndSettle();
    expect(accepted, [photo]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('keeps safe photos and blocks flagged or failed checks', (
    tester,
  ) async {
    final safe = XFile('safe.jpg');
    final flagged = XFile('flagged.jpg');
    final broken = XFile('broken.jpg');
    List<XFile>? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                accepted = await screenPhotos(
                  context,
                  [safe, flagged, broken],
                  showDebugResults: false,
                  check: (photo) async {
                    if (photo == broken) throw StateError('Unavailable');
                    return photo == safe;
                  },
                );
              },
              child: const Text('Select photos'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select photos'));
    await tester.pumpAndSettle();
    expect(accepted, [safe]);
    expect(find.textContaining('adult content'), findsOneWidget);
    expect(find.textContaining('could not be checked'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('blocks navigation while a check is running', (tester) async {
    final pending = Completer<bool>();
    List<XFile>? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                accepted = await screenPhotos(
                  context,
                  [XFile('photo.jpg')],
                  check: (_) => pending.future,
                  showDebugResults: false,
                );
              },
              child: const Text('Select photos'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select photos'));
    await tester.pump();
    expect(find.text('Checking photos… 0/1'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(accepted, isNull);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(accepted, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
