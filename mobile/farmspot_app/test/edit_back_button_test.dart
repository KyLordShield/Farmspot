import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/screens/seller/add_crop_screen.dart';
import 'package:farmspot_app/screens/seller/edit_farm_screen.dart';

// The setup/edit screens now carry a top-left back arrow. With nothing typed it
// pops straight back; once the form has unsaved changes it asks first
// ("Discard changes?", Cancel / red Discard), so an accidental back can never
// silently drop real work.

Future<void> _pushScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => screen),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add crop: back arrow pops straight back with no changes made',
      (tester) async {
    await _pushScreen(tester, const AddCropScreen(isFirstCrop: true));

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget,
        reason: 'back with no edits must return directly to the caller');
  });

  testWidgets('add crop: back arrow asks before discarding typed changes',
      (tester) async {
    await _pushScreen(tester, const AddCropScreen(isFirstCrop: true));

    await tester.enterText(find.byType(TextField), 'Tomatoes');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget,
        reason: 'dirty forms must confirm before going back');

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget,
        reason: 'confirming Discard must return to the caller');
  });

  testWidgets('add crop: back arrow cancel keeps the form on screen',
      (tester) async {
    await _pushScreen(tester, const AddCropScreen(isFirstCrop: true));

    await tester.enterText(find.byType(TextField), 'Tomatoes');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(TextField), findsOneWidget,
        reason: 'cancelling keeps the form where it was');
  });

  testWidgets('edit farm: back arrow pops straight back with no changes made',
      (tester) async {
    await _pushScreen(tester, const EditFarmScreen(farmId: 'FRMA'));

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget,
        reason: 'back with no edits must return directly to the caller');
  });
}