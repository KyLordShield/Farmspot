import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:farmspot_app/models/farm_setup_data.dart';
import 'package:farmspot_app/screens/seller/farm_setup_details_screen.dart';
import 'package:farmspot_app/screens/seller/farm_setup_verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first-step back exits setup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        FarmSetupDetailsScreen(farmSetupData: FarmSetupData()),
                  ),
                ),
                child: const Text('Open setup'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open setup'), findsOneWidget);
    expect(find.byType(FarmSetupDetailsScreen), findsNothing);
  });

  testWidgets('verification back retains editable farm details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final photo = XFile.fromData(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      name: 'farm-photo.png',
    );
    final data = FarmSetupData()
      ..name = 'Original Farm'
      ..description = 'Fresh local produce'
      ..barangay = 'Pusok'
      ..photos = [photo];
    await tester.pumpWidget(
      MaterialApp(home: FarmSetupDetailsScreen(farmSetupData: data)),
    );
    await tester.pumpAndSettle();
    final next = find.text('Next: Verify Identity');
    await tester.scrollUntilVisible(
      next,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.byType(FarmSetupVerifyScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 800));
    await tester.pumpAndSettle();
    final name = find.byType(TextField).first;
    expect(tester.widget<TextField>(name).controller!.text, 'Original Farm');
    await tester.enterText(name, 'Renamed Farm');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      next,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(data.name, 'Renamed Farm');
    expect(data.description, 'Fresh local produce');
    expect(data.photos.single, same(photo));
  });
}
