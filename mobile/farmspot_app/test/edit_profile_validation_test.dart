import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farmspot_app/screens/edit_profile_screen.dart';
import 'package:farmspot_app/utils/mobile_number.dart';

Finder phoneField() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'mobile number',
);
Future<void> openProfile(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  await tester.pumpWidget(
    const MaterialApp(
      home: EditProfileScreen(
        firstName: 'Test',
        lastName: 'Person',
        phone: '09171234567',
        email: 'person@example.test',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'email is visible and read-only and phone input is digits only capped at eleven',
    (tester) async {
      await openProfile(tester);
      final email = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Email',
        ),
      );
      expect(email.readOnly, isTrue);
      expect(email.controller!.text, 'person@example.test');
      await tester.enterText(phoneField(), '');
      await tester.enterText(phoneField(), 'abc092812345678999');
      expect(
        tester.widget<TextField>(phoneField()).controller!.text,
        '09281234567',
      );
    },
  );

  testWidgets(
    'wrong prefix and short phone are rejected before sending anything',
    (tester) async {
      final client = MockClient(
        (_) async => throw StateError('Invalid input must not reach server'),
      );
      addTearDown(client.close);
      await http.runWithClient(() async {
        await openProfile(tester);
        for (final value in ['08123456789', '0912', '']) {
          await tester.enterText(phoneField(), value);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(phoneField()).decoration!.errorText,
            value.isEmpty
                ? MobileNumber.requiredMessage
                : MobileNumber.invalidMessage,
          );
        }
      }, () => client);
    },
  );

  testWidgets(
    'duplicate phone keeps the entered number and shows registration message beside it',
    (tester) async {
      final client = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.bodyFields['mobile_number'], '09281234567');
        expect(request.bodyFields.containsKey('email'), isFalse);
        expect(request.bodyFields.containsKey('USR_EMAIL'), isFalse);
        return http.Response(
          jsonEncode({
            'message': MobileNumber.duplicateMessage,
            'errors': {
              'mobile_number': [MobileNumber.duplicateMessage],
            },
          }),
          422,
        );
      });
      addTearDown(client.close);
      await http.runWithClient(() async {
        await openProfile(tester);
        await tester.enterText(phoneField(), '09281234567');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(phoneField()).decoration!.errorText,
          MobileNumber.duplicateMessage,
        );
        expect(
          tester.widget<TextField>(phoneField()).controller!.text,
          '09281234567',
        );
        expect(find.text('person@example.test'), findsOneWidget);
      }, () => client);
    },
  );
}
