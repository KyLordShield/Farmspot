import 'package:farmspot_app/screens/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/signup_steps.dart';

void main() {
  testWidgets('steps validate input, slide and preserve details on back', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
    await signupNext(tester);
    expect(find.text('Please enter your first name.'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.enterText(signupField('FirstName'), 'Maria Jane');
    await tester.enterText(signupField('Lastname'), 'Dela Cruz');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final slide = tester.widget<SlideTransition>(
      find.byKey(const Key('signup-slide')),
    );
    expect(slide.position.value.dx, greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await tester.enterText(signupField('email'), 'invalid');
    await tester.enterText(signupField('mobile number'), '0812');
    await signupNext(tester);
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('Please enter a valid email address.'), findsOneWidget);
    await tester.enterText(signupField('email'), 'maria@example.com');
    await tester.enterText(signupField('mobile number'), '09123456789');
    await tester.enterText(signupField('address'), 'My street');
    await signupNext(tester);
    expect(find.text('Step 3 of 3'), findsOneWidget);
    await tester.enterText(signupField('password'), 'MyPassword1');
    await tester.ensureVisible(find.byTooltip('Back'));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(signupField('address')).controller!.text,
      'My street',
    );
    await signupNext(tester);
    expect(
      tester.widget<TextField>(signupField('password')).controller!.text,
      'MyPassword1',
    );
  });
}
