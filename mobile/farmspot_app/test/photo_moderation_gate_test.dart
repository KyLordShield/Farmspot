import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:farmspot_app/widgets/photo_moderation_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
                accepted = await screenPhotos(context, [
                  XFile('photo.jpg'),
                ], check: (_) => pending.future);
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
