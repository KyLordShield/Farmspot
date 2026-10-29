import 'package:farmspot_app/legal/legal.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:farmspot_app/screens/signup_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:farmspot_app/services/auth_service.dart';

void main() {
  setUpAll(() async {
    await LegalService.catalog();
  });
  testWidgets(
    'registration stays blocked before reviewing the required agreement',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Create Account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Please review and accept the Terms of Service'),
        findsOneWidget,
      );
      expect(find.byType(SignUpScreen), findsOneWidget);
    },
  );
  testWidgets('duplicate fields show friendly alert and inline messages', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'message': 'The details have already been taken.',
          'errors': {
            'USR_EMAIL': ['The email has already been taken.'],
            'USR_MOBILE_NUMBER': ['The mobile number has already been taken.'],
          },
        }),
        422,
      ),
    );
    addTearDown(client.close);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      final values = {
        'Lastname': 'Example',
        'FirstName': 'Test Person',
        'email': 'person@example.com',
        'mobile number': '09123456789',
        'password': 'example123',
        'confirm password': 'example123',
      };
      for (final entry in values.entries) {
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == entry.key,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Create Account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      final policyScroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('legal-reader-scroll')),
          )
          .controller!;
      policyScroll.jumpTo(policyScroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('legal-reader-agree')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Check Your Details'), findsOneWidget);
      expect(find.text('Something Went Wrong'), findsNothing);
      expect(
        find.textContaining('That email is already registered.'),
        findsWidgets,
      );
      expect(
        find.textContaining('That mobile number is already registered.'),
        findsWidgets,
      );
      await tester.tap(find.text('Review Details'));
      await tester.pumpAndSettle();
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(
        fields
            .firstWhere((w) => w.decoration?.hintText == 'email')
            .decoration
            ?.errorText,
        'That email is already registered. Try logging in instead.',
      );
      expect(
        fields
            .firstWhere((w) => w.decoration?.hintText == 'mobile number')
            .decoration
            ?.errorText,
        'That mobile number is already registered.',
      );
    }, () => client);
  });

  test(
    'registration preserves duplicate and invalid field messages from JSON',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'message': 'Please check your details.',
            'errors': {
              'USR_EMAIL': ['That email has already been taken.'],
              'USR_MOBILE_NUMBER': [
                'That mobile number has already been taken.',
              ],
              'USR_PASSWORD': ['The password confirmation does not match.'],
            },
          }),
          422,
        ),
      );
      addTearDown(client.close);
      final result = await AuthService.attemptRegister(
        name: 'Test Person',
        email: 'person@example.com',
        password: 'example123',
        passwordConfirmation: 'different123',
        mobileNumber: '09123456789',
        client: client,
      );
      expect(result.statusCode, 422);
      expect(result.fieldErrors['USR_EMAIL'], [
        'That email has already been taken.',
      ]);
      expect(result.fieldErrors['USR_MOBILE_NUMBER'], [
        'That mobile number has already been taken.',
      ]);
      expect(result.fieldErrors['USR_PASSWORD'], [
        'The password confirmation does not match.',
      ]);
      expect(result.isNetworkError, isFalse);
    },
  );
}
