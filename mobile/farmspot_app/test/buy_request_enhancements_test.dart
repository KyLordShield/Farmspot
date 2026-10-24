import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farmspot_app/models/buy_request.dart';
import 'package:farmspot_app/models/crop_choice.dart';
import 'package:farmspot_app/screens/premium/buy_request_form_screen.dart';
import 'package:farmspot_app/screens/premium/buy_request_pin_screen.dart';
import 'package:farmspot_app/screens/seller/requests_board_screen.dart';
import 'package:farmspot_app/screens/in_app_messages_screen.dart';
import 'buy_requests_test.dart' show FakeRequests, requestJson;

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'auth_token': 'test-token'}),
  );

  test(
    'crop suggestions handle typo, sentences, joined words, and aliases',
    () {
      const catalog = [
        CropChoice('Cabbage', ['repolyo']),
        CropChoice('Tomato', ['kamatis']),
        CropChoice('Pechay'),
      ];
      for (final query in [
        'cabbge',
        'cabbge I need for business',
        'Ineedcabbage',
        'repolyo',
      ]) {
        expect(suggestCrops(query, catalog).first.name, 'Cabbage');
      }
      expect(suggestCrops('zzzzzzzz', catalog), isEmpty);
    },
  );

  test('model distinguishes no location from a saved pin and reads phone', () {
    expect(BuyRequest.fromJson(requestJson()).hasPin, isFalse);
    final pin = BuyRequest.fromJson({
      ...requestJson(),
      'location': {'latitude': 10.3178123, 'longitude': 123.8742123},
      'buyer': {'id': 'B', 'name': 'Buyer', 'phone': '09171234567'},
    });
    expect(pin.hasPin, isTrue);
    expect(pin.latitude, 10.3178123);
    expect(pin.buyerPhone, '09171234567');
  });

  testWidgets('buyer must confirm a crop suggestion before posting', (
    tester,
  ) async {
    final api = FakeRequests();
    await tester.pumpWidget(
      MaterialApp(home: BuyRequestFormScreen(gateway: api)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'cabbge I need for business',
    );
    await tester.pump();
    expect(find.widgetWithText(ChoiceChip, 'Cabbage'), findsOneWidget);
    await tester.tap(find.text('Post request'));
    await tester.pump();
    expect(api.posted, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cabbage'));
    await tester.pump();
    expect(find.text('Selected crop: Cabbage'), findsOneWidget);
  });

  testWidgets(
    'map starts without a pin and requires a tap before confirmation',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuyRequestPinScreen(tileLayer: ColoredBox(color: Colors.white)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(find.byType(FlutterMap)).height, greaterThan(100));
      expect(tester.getRect(find.byType(FlutterMap)).width, greaterThan(100));
      final confirm = find.byKey(const Key('confirm-request-pin'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(find.textContaining('No pin selected'), findsOneWidget);
      await tester.tapAt(tester.getRect(find.byType(FlutterMap)).center);
      await tester.pump(const Duration(milliseconds: 850));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(find.byIcon(Icons.location_pin), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('seller call opens tel externally without opening in-app chat', (
    tester,
  ) async {
    final api = FakeRequests()
      ..rows = [
        const BuyRequest(
          id: 'REQ001',
          crop: 'Cabbage',
          quantityKg: 20,
          frequency: 'weekly',
          buyerName: 'Buyer',
          buyerPhone: '0917 123 4567',
        ),
      ];
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: RequestsBoardScreen(
          gateway: api,
          externalCallLauncher: (uri) async {
            opened = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No location shared'), findsOneWidget);
    expect(find.text('View map pin'), findsNothing);
    await tester.tap(find.text('Call buyer'));
    await tester.pump();
    expect(opened?.scheme, 'tel');
    expect(opened?.path, '09171234567');
    expect(find.byType(InAppMessagesScreen), findsNothing);
  });

  testWidgets('a buyer without a phone still has in-app messaging', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: RequestsBoardScreen(gateway: FakeRequests())),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No phone number available. You can still message the buyer.'),
      findsOneWidget,
    );
    expect(find.text('Message buyer'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Call buyer'),
          )
          .onPressed,
      isNull,
    );
  });
}
