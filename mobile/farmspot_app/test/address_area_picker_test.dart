import 'package:farmspot_app/screens/signup_screen.dart';
import 'package:farmspot_app/utils/address_areas.dart';
import 'package:farmspot_app/widgets/address_area_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/signup_steps.dart';

void main() {
  test('offline directory distinguishes same-named barangays by city', () {
    expect(AddressAreas.all.length, 137);
    expect(AddressAreas.all.toSet().length, 137);
    expect(AddressAreas.search('banilad').length, 2);
    expect(AddressAreas.search('banilad mandaue'), [
      'Banilad, Mandaue City, Cebu',
    ]);
    expect(AddressAreas.search('pusok'), ['Pusok, Lapu-Lapu City, Cebu']);
  });

  test('changing area preserves house and street details', () {
    const old = '12 Main Street, Pusok, Lapu-Lapu City, Cebu';
    const area = 'Busay, Cebu City, Cebu';
    expect(AddressAreas.withArea(old, area), '12 Main Street, $area');
    expect(
      AddressAreas.withArea('12 Main Street', area),
      '12 Main Street, $area',
    );
    expect(AddressAreas.withArea('busay', area), area);
    expect(
      AddressAreas.withArea(
        '12 Main Street, Pus',
        'Pusok, Lapu-Lapu City, Cebu',
      ),
      '12 Main Street, Pusok, Lapu-Lapu City, Cebu',
    );
  });

  testWidgets(
    'registration allows choosing an area and then editing manually',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await signupToContact(tester);
      final address = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'address',
      );
      await tester.ensureVisible(address);
      await tester.enterText(address, 'pusok');
      await tester.pump();
      expect(find.textContaining('/150'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.ensureVisible(find.text('Pusok, Lapu-Lapu City, Cebu'));
      await tester.tap(find.text('Pusok, Lapu-Lapu City, Cebu'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(address).controller!.text,
        'Pusok, Lapu-Lapu City, Cebu',
      );
      await tester.enterText(
        address,
        '12 Main Street, Pusok, Lapu-Lapu City, Cebu',
      );
      expect(
        tester.widget<TextField>(address).controller!.text,
        startsWith('12 Main Street'),
      );
    },
  );

  testWidgets('selecting an area never silently truncates a long address', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: '${List.filled(140, 'A').join()}, Pus',
    );
    final original = controller.text;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddressAreaField(
            controller: controller,
            maxLength: 150,
            fieldBuilder: (focusNode) =>
                TextField(controller: controller, focusNode: focusNode),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pusok, Lapu-Lapu City, Cebu'));
    await tester.pumpAndSettle();
    expect(controller.text, original);
    expect(find.textContaining('Keep the address within'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test(
    'Agus query uses the map provider city name and rejects unrelated results',
    () {
      expect(
        AddressAreas.mapQuery('Agus, Lapu-Lapu City, Cebu'),
        'Agus, Lapu-Lapu, Philippines',
      );
      expect(
        AddressAreas.mapQuery('Agus, Lapu Lapu City Cebu'),
        'Agus, Lapu-Lapu, Philippines',
      );
      expect(
        AddressAreas.matchesMapResult(
          'Agus, Lapu-Lapu City, Cebu',
          'Agus, Lapu-Lapu, Central Visayas, Philippines',
        ),
        isTrue,
      );
      expect(
        AddressAreas.matchesMapResult(
          'Agus, Lapu-Lapu City, Cebu',
          'Pigafetta Street, Carreta, Cebu City, Philippines',
        ),
        isFalse,
      );
    },
  );
}
