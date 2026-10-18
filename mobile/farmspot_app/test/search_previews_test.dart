import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/farm_pin.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/models/listing_review.dart';
import 'package:farmspot_app/models/search_suggestions.dart';
import 'package:farmspot_app/models/seller_summary.dart';
import 'package:farmspot_app/models/user_profile.dart';
import 'package:farmspot_app/screens/farm_profile_screen.dart';
import 'package:farmspot_app/screens/search_all_screen.dart';
import 'package:farmspot_app/screens/search_results_screen.dart';
import 'package:farmspot_app/screens/search_screen.dart';
import 'package:farmspot_app/screens/user_profile_screen.dart';
import 'package:farmspot_app/widgets/search_widgets.dart';

FarmPin _farm(String id, String name) => FarmPin(
      id: id,
      name: name,
      barangay: 'Bulua',
      activeListingsCount: 5,
    );

/// A seller search row. [userId] is the account the profile opens on, so the
/// row's own id doubles as it here.
SellerSummary _seller(String userId, String name) => SellerSummary(
      id: userId,
      userId: userId,
      name: name,
      farmCount: 1,
      activeListingsCount: 18,
    );

SearchSuggestions _suggestions({
  List<FarmPin> farms = const [],
  List<SellerSummary> sellers = const [],
}) =>
    SearchSuggestions(farms: farms, sellers: sellers);

/// Names a keystroke term and settles the 450ms typeahead debounce.
Future<void> _typeAndSettle(WidgetTester tester, String term) async {
  await tester.enterText(find.byType(TextField), term);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Pumps a frame plus the push transition only. The [FarmProfileScreen] and
/// [SearchAllScreen] targets fall back to their real loaders under test (a 400
/// from the test HTTP override), so settling would risk waiting on a loading
/// animation; the push itself is what these navigation tests assert.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('SearchScreen typeahead — farm/seller previews', () {
    Future<void> pumpTypeahead(
      WidgetTester tester, {
      required Future<SearchSuggestions> Function(String term) loadPreviews,
    }) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            loadSuggestions: (_) async => const [],
            loadPreviews: loadPreviews,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows farm and seller groups for the typed term', (
      tester,
    ) async {
      await pumpTypeahead(
        tester,
        loadPreviews: (_) async => _suggestions(
          farms: [_farm('F1', 'Bayan Farm')],
          sellers: [_seller('NB12UR', 'Rejean Libando')],
        ),
      );

      await _typeAndSettle(tester, 'libando');

      expect(find.text('Farms'), findsOneWidget);
      expect(find.text('Sellers'), findsOneWidget);
      expect(find.text('Bayan Farm'), findsOneWidget);
      expect(find.text('Rejean Libando'), findsOneWidget);
      // One match each: the preview is not capped, so there is nothing more to
      // show and no "See all".
      expect(find.text('See all'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"See all" appears once a group hits the cap and opens the '
        'full list', (tester) async {
      await pumpTypeahead(
        tester,
        loadPreviews: (_) async => _suggestions(
          farms: [
            for (var i = 0; i < searchPreviewCap; i++) _farm('F$i', 'Farm $i'),
          ],
        ),
      );

      await _typeAndSettle(tester, 'farm');

      expect(find.text('See all'), findsOneWidget);

      await tester.tap(find.text('See all'));
      await _settleRoute(tester);

      expect(find.byType(SearchAllScreen), findsOneWidget);
    });

    testWidgets('tapping a farm preview opens its farm profile', (tester) async {
      await pumpTypeahead(
        tester,
        loadPreviews: (_) async =>
            _suggestions(farms: [_farm('F1', 'Bayan Farm')]),
      );

      await _typeAndSettle(tester, 'bayan');
      await tester.tap(find.text('Bayan Farm'));
      await _settleRoute(tester);

      expect(find.byType(FarmProfileScreen), findsOneWidget);
    });

    testWidgets('tapping a seller preview opens the user profile', (
      tester,
    ) async {
      await pumpTypeahead(
        tester,
        loadPreviews: (_) async =>
            _suggestions(sellers: [_seller('NB12UR', 'Rejean Libando')]),
      );

      await _typeAndSettle(tester, 'libando');
      await tester.tap(find.text('Rejean Libando'));
      await _settleRoute(tester);

      expect(find.byType(UserProfileScreen), findsOneWidget);
    });

    testWidgets('clearing the field drops the previews', (tester) async {
      await pumpTypeahead(
        tester,
        loadPreviews: (_) async =>
            _suggestions(farms: [_farm('F1', 'Bayan Farm')]),
      );

      await _typeAndSettle(tester, 'bayan');
      expect(find.text('Bayan Farm'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Bayan Farm'), findsNothing);
      expect(find.text('RECENT SEARCHES'), findsOneWidget);
    });
  });

  group('SearchResultsScreen — farm/seller previews above the grid', () {
    Future<void> pumpResults(
      WidgetTester tester, {
      required Future<SearchSuggestions> Function(String term) loadPreviews,
      List<Listing> listings = const [],
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsScreen(
            query: 'libando',
            loadResults: (_) async => listings,
            loadFarms: () async => const [],
            loadBuyerPosition: () async => null,
            loadPreviews: loadPreviews,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('renders the preview groups even when no crop matches', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpResults(
        tester,
        loadPreviews: (_) async => _suggestions(
          farms: [_farm('F1', 'libando farm')],
          sellers: [_seller('NB12UR', 'Rejean Libando')],
        ),
      );

      expect(find.text('Farms'), findsOneWidget);
      expect(find.text('Sellers'), findsOneWidget);
      expect(find.text('libando farm'), findsOneWidget);
      expect(find.text('Rejean Libando'), findsOneWidget);
      // The crop side is still its own honest empty state below the previews.
      expect(find.text('No farms selling this crop yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"See all" opens the full farm list', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpResults(
        tester,
        loadPreviews: (_) async => _suggestions(
          farms: [
            for (var i = 0; i < searchPreviewCap; i++) _farm('F$i', 'Farm $i'),
          ],
        ),
      );

      await tester.tap(find.text('See all'));
      await _settleRoute(tester);

      expect(find.byType(SearchAllScreen), findsOneWidget);
    });
  });

  group('SearchAllScreen', () {
    testWidgets('lists every farm the injected search returns', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchAllScreen(
            query: 'libando',
            type: SearchAllType.farms,
            load: (_) async => _suggestions(
              farms: [
                _farm('F1', 'Bayan Farm'),
                _farm('F2', 'Upland Farm'),
                _farm('F3', 'Sun Village Farm'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Farms'), findsOneWidget);
      expect(find.text('"libando"'), findsOneWidget);
      expect(find.text('Bayan Farm'), findsOneWidget);
      expect(find.text('Upland Farm'), findsOneWidget);
      expect(find.text('Sun Village Farm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists every seller the injected search returns', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchAllScreen(
            query: 'libando',
            type: SearchAllType.sellers,
            load: (_) async =>
                _suggestions(sellers: [_seller('NB12UR', 'Rejean Libando')]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Sellers'), findsOneWidget);
      expect(find.text('Rejean Libando'), findsOneWidget);
    });
  });

  group('UserProfileScreen', () {
    testWidgets('a seller shows their contact details and farms', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final profile = UserProfile(
        id: 'PS1EIL',
        name: 'Rejean Libando',
        address: 'Agus, Ibabao',
        phone: '09294262530',
        isSeller: true,
        farmerId: 'NB12UR',
        farmCount: 1,
        activeListingsCount: 18,
        farms: [_farm('F1', 'libando farm')],
        rating: const RatingSummary(average: 4.5, count: 34),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfileScreen(userId: 'PS1EIL', initialProfile: profile),
        ),
      );
      await tester.pump();

      expect(find.text('Rejean Libando'), findsWidgets);
      expect(find.text('Seller'), findsOneWidget);
      expect(find.text('Contact number'), findsOneWidget);
      expect(find.text('09294262530'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Agus, Ibabao'), findsOneWidget);
      expect(find.text('Farms'), findsOneWidget); // section header
      expect(find.text('libando farm'), findsOneWidget);
      expect(find.text('Report this seller'), findsOneWidget);
      // The profile is about the person only; it must not carry a listing wall.
      expect(find.text('Listings'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pure buyer shows just the profile, with no farms', (
      tester,
    ) async {
      final profile = UserProfile(
        id: 'BUYER1',
        name: 'Juan Buyer',
        address: 'Cebu City',
        phone: '09171234567',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfileScreen(userId: 'BUYER1', initialProfile: profile),
        ),
      );
      await tester.pump();

      expect(find.text('Juan Buyer'), findsOneWidget);
      expect(find.text('Buyer'), findsOneWidget);
      expect(find.text('09171234567'), findsOneWidget);
      expect(find.text('Farms'), findsNothing);
      expect(find.text('Report this user'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('load failure shows a retry, not a crash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UserProfileScreen(
            userId: 'PS1EIL',
            loadProfile: (_) async =>
                throw Exception('Could not reach the server.'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
