import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/farm_pin.dart';
import 'package:farmspot_app/screens/home_screen.dart';
import 'package:farmspot_app/screens/insights_screen.dart';
import 'package:farmspot_app/screens/map_screen.dart';
import 'package:farmspot_app/screens/profile_screen.dart';
import 'package:farmspot_app/services/session_state.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';
import 'package:farmspot_app/widgets/seller_widgets.dart';

/// Seeds the on-disk cache exactly as a completed login would, then runs the
/// same [SessionState.init] that `main()` runs behind the splash. Going through
/// the real init (rather than poking the notifier) is deliberate: it keeps the
/// test honest about the production path.
Future<void> _signInAs({required bool seller}) async {
  SharedPreferences.setMockInitialValues({
    'auth_token': 'some-token',
    'user_data': jsonEncode({
      'USR_ID': 'XXXXXX',
      'USR_NAME': 'Rejean Libando',
      'USR_MOBILE_NUMBER': '09878687656',
      'USR_IS_SELLER': seller ? 1 : 0,
    }),
  });
  await SessionState.instance.init();
}

/// One frame. No settling, no pumping the 4s message poll to completion.
///
/// This is the whole point of the shared session state. The old code resolved
/// the role in each screen's `initState` via an async call, so the first frame
/// always painted the buyer nav and only corrected itself after the round trip
/// — the "My Farm tab disappears then comes back" symptom. A test that pumps
/// twenty times cannot catch that; this one can.
Future<void> _pumpOneFrame(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
}

void main() {
  group('bottom nav picks the right role on the very first frame', () {
    testWidgets('Home shows My Farm immediately, with no settling',
        (tester) async {
      await _signInAs(seller: true);

      await _pumpOneFrame(tester, const HomeScreen());

      expect(find.byType(SellerBottomNav), findsOneWidget);
      expect(find.byType(FarmSpotBottomNav), findsNothing);
      expect(find.text('My Farm'), findsOneWidget);
    });

    testWidgets('Profile shows My Farm immediately', (tester) async {
      await _signInAs(seller: true);

      await _pumpOneFrame(tester, const ProfileScreen());

      expect(find.byType(SellerBottomNav), findsOneWidget);
      expect(find.text('My Farm'), findsOneWidget);
    });

    // Map and Insights used to read only the disk cache and silently stayed on
    // the buyer nav when that cache was missing, so they disagreed with Home
    // about whether the user was a seller.
    testWidgets('Map shows My Farm immediately', (tester) async {
      await _signInAs(seller: true);

      await _pumpOneFrame(
        tester,
        MapScreen(
          loadFarms: () async => <FarmPin>[],
          loadPosition: () async => const LatLng(10.3178, 123.8742),
        ),
      );

      expect(find.byType(SellerBottomNav), findsOneWidget);
      expect(find.text('My Farm'), findsOneWidget);
    });

    testWidgets('Insights shows My Farm immediately', (tester) async {
      await _signInAs(seller: true);

      await _pumpOneFrame(tester, const InsightsScreen());

      expect(find.byType(SellerBottomNav), findsOneWidget);
      expect(find.text('My Farm'), findsOneWidget);
    });

    testWidgets('a buyer keeps the buyer nav with no My Farm', (tester) async {
      await _signInAs(seller: false);

      await _pumpOneFrame(tester, const HomeScreen());

      expect(find.byType(FarmSpotBottomNav), findsOneWidget);
      expect(find.byType(SellerBottomNav), findsNothing);
      expect(find.text('My Farm'), findsNothing);
    });
  });

  group('the role survives switching tabs', () {
    // Tabs are navigated with pushReplacement, which throws away each screen's
    // State. Anything the nav derived per-screen used to be rebuilt from
    // scratch every time; the shared session outlives all of it.
    testWidgets('Home -> Map -> Home keeps My Farm the whole way',
        (tester) async {
      await _signInAs(seller: true);

      await _pumpOneFrame(tester, const HomeScreen());
      expect(find.text('My Farm'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.map_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.text('My Farm'), findsOneWidget,
          reason: 'Map must agree with Home about the role');

      await tester.tap(find.byIcon(Icons.home));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('My Farm'), findsOneWidget);
    });

    testWidgets('Home -> Profile keeps My Farm', (tester) async {
      await _signInAs(seller: true);

      await _pumpOneFrame(tester, const HomeScreen());
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('My Farm'), findsOneWidget);
    });
  });

  group('a role change updates every mounted screen at once', () {
    testWidgets('toggling seller mode swaps the nav without a reload',
        (tester) async {
      await _signInAs(seller: false);
      await _pumpOneFrame(tester, const HomeScreen());
      expect(find.byType(FarmSpotBottomNav), findsOneWidget);

      // What AuthService does after a successful activate/deactivate, once the
      // server has confirmed the new role. Synchronous, like the real call.
      SessionState.instance
          .applyUser({'USR_ID': 'XXXXXX', 'USR_IS_SELLER': 1});
      await tester.pump();

      expect(find.byType(SellerBottomNav), findsOneWidget);
      expect(find.text('My Farm'), findsOneWidget);
    });
  });

  group('SessionState', () {
    test('parses the seller flag whether it is an int or a string', () {
      SessionState.instance.debugSetUser({'USR_IS_SELLER': 1});
      expect(SessionState.instance.isSeller, isTrue);

      SessionState.instance.debugSetUser({'USR_IS_SELLER': '1'});
      expect(SessionState.instance.isSeller, isTrue);

      SessionState.instance.debugSetUser({'USR_IS_SELLER': 0});
      expect(SessionState.instance.isSeller, isFalse);

      SessionState.instance.debugSetUser({'USR_IS_SELLER': '0'});
      expect(SessionState.instance.isSeller, isFalse);
    });

    test('a missing user is a buyer, not a crash', () {
      SessionState.instance.debugSetUser(null);
      expect(SessionState.instance.isSeller, isFalse);
      expect(SessionState.instance.isLoggedIn, isFalse);
    });

    test('notifies listeners only when the user actually changes', () {
      SessionState.instance.debugSetUser({'USR_ID': '1', 'USR_IS_SELLER': 1});
      var notifications = 0;
      void count() => notifications++;
      SessionState.instance.addListener(count);

      // A background refetch that confirms what we already knew must not
      // rebuild the nav.
      SessionState.instance
          .applyUser({'USR_ID': '1', 'USR_IS_SELLER': 1});
      expect(notifications, 0);

      SessionState.instance
          .applyUser({'USR_ID': '1', 'USR_IS_SELLER': 0});
      expect(notifications, 1);

      SessionState.instance.removeListener(count);
    });

    test('ignores key ordering when comparing users', () {
      SessionState.instance.debugSetUser({
        'USR_ID': '1',
        'USR_IS_SELLER': 1,
      });
      var notifications = 0;
      void count() => notifications++;
      SessionState.instance.addListener(count);

      SessionState.instance.applyUser({
        'USR_IS_SELLER': 1,
        'USR_ID': '1',
      });
      expect(notifications, 0, reason: 'same data, different key order');

      SessionState.instance.removeListener(count);
    });

    test('clear drops the role on sign-out', () {
      SessionState.instance.debugSetUser({'USR_IS_SELLER': 1});
      SessionState.instance.clear();
      expect(SessionState.instance.isSeller, isFalse);
      expect(SessionState.instance.isLoggedIn, isFalse);
    });

    test('a corrupt cache does not brick launch', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'some-token',
        'user_data': '{not valid json',
      });
      await SessionState.instance.init();

      expect(SessionState.instance.isSeller, isFalse);
      expect(SessionState.instance.isInitialised, isTrue);
    });
  });
}
