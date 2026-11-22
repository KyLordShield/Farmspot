import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder signupField(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

Future<void> signupNext(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Next'));
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

Future<void> signupToContact(WidgetTester tester) async {
  await tester.enterText(signupField('FirstName'), 'Test Person');
  await tester.enterText(signupField('Lastname'), 'Example');
  await signupNext(tester);
}

Future<void> signupToPassword(WidgetTester tester) async {
  await signupToContact(tester);
  await tester.enterText(signupField('email'), 'person@example.com');
  await tester.enterText(signupField('mobile number'), '09123456789');
  await signupNext(tester);
}
