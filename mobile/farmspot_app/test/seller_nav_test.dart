import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/screens/home_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';
import 'package:farmspot_app/widgets/seller_widgets.dart';

void main() {
  // Deterministic widget check of the fallback path that previously hid
  // "My Farm": with network blocked (testWidgets returns 400 for all HTTP),
  // fetchUser() fails and isSeller() must fall back to the cached user. Because
  // login() now guarantees the cache is authoritative, the seller nav shows
  // even on the very first HomeScreen build.
  testWidgets('HomeScreen shows SellerBottomNav from cached seller user',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'some-token',
      'user_data': jsonEncode({
        'USR_ID': 'XXXXXX',
        'USR_NAME': 'Rejean Libando',
        'USR_MOBILE_NUMBER': '09878687656',
        'USR_IS_SELLER': 1,
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(SellerBottomNav), findsWidgets);
    expect(find.byType(FarmSpotBottomNav), findsNothing);
  });

  // Buyer (USR_IS_SELLER=0) must keep the buyer-only nav, no regression.
  testWidgets('HomeScreen shows buyer nav for a plain buyer', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'some-token',
      'user_data': jsonEncode({
        'USR_ID': 'YYYYYY',
        'USR_NAME': 'Plain Buyer',
        'USR_MOBILE_NUMBER': '09170000000',
        'USR_IS_SELLER': 0,
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(FarmSpotBottomNav), findsWidgets);
    expect(find.byType(SellerBottomNav), findsNothing);
  });
}
