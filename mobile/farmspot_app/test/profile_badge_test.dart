import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/screens/profile_screen.dart';

// Widget checks for the Profile screen's seller/buyer badge. Network is blocked
// in testWidgets, so the badge must derive from the cached seller flag exactly
// like it does live — and the removed buyer-stats row must stay gone.
Future<void> _pumpProfile(WidgetTester tester, int isSeller) async {
  SharedPreferences.setMockInitialValues({
    'auth_token': 'some-token',
    'user_data': jsonEncode({
      'USR_ID': isSeller == 1 ? 'XXXXXX' : 'YYYYYY',
      'USR_NAME': isSeller == 1 ? 'Rejean Libando' : 'Plain Buyer',
      'USR_MOBILE_NUMBER': '09878687656',
      'USR_IS_SELLER': isSeller,
    }),
  });

  await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
  // Let _syncStateFromServer settle (network fails, cached user is used).
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('approved seller gets a "Seller Account" badge', (tester) async {
    await _pumpProfile(tester, 1);

    expect(find.text('Seller Account'), findsOneWidget);
    expect(find.text('Buyer Account'), findsNothing);

    // The buyer-activity stats row is gone from Profile entirely.
    expect(find.text('Searches'), findsNothing);
    expect(find.text('Farm Visited'), findsNothing);
    expect(find.text('Contact Made'), findsNothing);
    expect(find.text('Buyer Contacts'), findsNothing);
  });

  testWidgets('plain buyer gets a "Buyer Account" badge', (tester) async {
    await _pumpProfile(tester, 0);

    expect(find.text('Buyer Account'), findsOneWidget);
    expect(find.text('Seller Account'), findsNothing);
  });
}