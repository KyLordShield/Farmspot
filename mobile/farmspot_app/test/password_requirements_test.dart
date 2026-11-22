import 'package:farmspot_app/widgets/password_requirements.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('password requires eight characters and all three character types', () {
    for (final password in [
      '',
      'Abc1234',
      'lowercase1',
      'UPPERCASE1',
      'NoNumbers',
    ]) {
      expect(PasswordRequirements.validate(password), isNotNull);
    }
    expect(PasswordRequirements.validate('Abcdef12'), isNull);
    expect(PasswordRequirements.validate('A longer Password 12!'), isNull);
  });

  testWidgets('checklist updates while typing and clearing the password', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PasswordRequirements(controller: controller)),
      ),
    );
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    controller.text = 'Abcdef12';
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(4));
    controller.clear();
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
