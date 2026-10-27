import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/models/farm_setup_data.dart';
import 'package:farmspot_app/screens/seller/farm_setup_details_screen.dart';
import 'package:farmspot_app/screens/edit_profile_screen.dart';
import 'package:farmspot_app/widgets/common_widgets.dart';

void main() {
  testWidgets('farm setup caps name, description and barangay input', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: FarmSetupDetailsScreen(farmSetupData: FarmSetupData())),
    );
    await tester.pumpAndSettle();
    final name = find
        .byWidgetPredicate((w) => w is TextField && w.maxLength == 100)
        .first;
    await tester.enterText(name, 'F' * 200);
    expect(tester.widget<TextField>(name).controller!.text.length, 100);
    final description = find.byWidgetPredicate(
      (w) => w is TextField && w.maxLength == 1000,
    );
    await tester.enterText(description, 'D' * 1500);
    expect(tester.widget<TextField>(description).controller!.text.length, 1000);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final barangay = find
        .byWidgetPredicate((w) => w is TextField && w.maxLength == 100)
        .last;
    await tester.scrollUntilVisible(
      barangay,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(barangay, 'B' * 200);
    expect(tester.widget<TextField>(barangay).controller!.text.length, 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile address and shared registration field cap pasted text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EditProfileScreen(firstName: 'Test', lastName: 'Person'),
      ),
    );
    await tester.pumpAndSettle();
    final address = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'address',
    );
    await tester.enterText(address, 'A' * 300);
    expect(tester.widget<TextField>(address).controller!.text.length, 255);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FarmSpotTextField(
            hint: 'address',
            maxLength: 255,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'A' * 300);
    expect(controller.text.length, 255);
  });
}
