import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/screens/profile_screen.dart';

// Widget checks for the Profile screen's seller/buyer badge and the stats row
// "no flashing zero" behavior. Network is blocked in testWidgets, so the stats
// fetch fails and the row must render "—" instead of a fake '0'; the badge must
// derive from the cached seller flag exactly like it does live.
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
  testWidgets('approved seller gets a "Seller Account" badge, no zero stats',
      (tester) async {
    await _pumpProfile(tester, 1);

    expect(find.text('Seller Account'), findsOneWidget);
    expect(find.text('Buyer Account'), findsNothing);

    // Stats fetch failed under blocked network -> "—" everywhere, never a '0'.
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
    expect(find.text('Searches'), findsOneWidget);
    expect(find.text('Farm Visited'), findsOneWidget);
    expect(find.text('Contact Made'), findsOneWidget);
  });

  testWidgets('plain buyer gets a "Buyer Account" badge', (tester) async {
    await _pumpProfile(tester, 0);

    expect(find.text('Buyer Account'), findsOneWidget);
    expect(find.text('Seller Account'), findsNothing);

    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
  });
}