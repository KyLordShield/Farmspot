import 'package:farmspot_app/screens/login_screen.dart';
import 'package:farmspot_app/widgets/association_contact_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('contact is accessible before signing in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final contact = find.text('Contact the Association');
    await tester.ensureVisible(contact);
    await tester.tap(contact);
    await tester.pumpAndSettle();
    expect(find.text('Manilyn B. Alferez'), findsOneWidget);
    expect(find.text('Association Secretary'), findsOneWidget);
    expect(find.text('manilyn.alferez@example.com'), findsOneWidget);
    expect(find.text('0917 482 6390'), findsOneWidget);
    expect(find.textContaining('Sample phone and email'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('deactivated account message includes the contact', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showAssociationContactDialog(context, accountDeactivated: true),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Account Deactivated'), findsOneWidget);
    expect(find.text('Manilyn B. Alferez'), findsOneWidget);
  });
}
