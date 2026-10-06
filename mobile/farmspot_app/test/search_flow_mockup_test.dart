import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/crop_suggestion.dart';
import 'package:farmspot_app/models/farm_pin.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/models/listing_review.dart';
import 'package:farmspot_app/models/search_crop_group.dart';
import 'package:farmspot_app/screens/home_screen.dart';
import 'package:farmspot_app/screens/image_search_screen.dart';
import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/screens/search_results_screen.dart';
import 'package:farmspot_app/screens/search_screen.dart';
import 'package:farmspot_app/services/image_detect_service.dart';
import 'package:farmspot_app/services/recent_searches.dart';
import 'package:farmspot_app/widgets/search_widgets.dart';

const _userPos = LatLng(10.3178, 123.8742);

Listing _listing(
  String id,
  String crop,
  String farm, {
  String status = 'AVAILABLE_NOW',
  String? farmId,
  RatingSummary ratings = const RatingSummary.none(),
}) {
  return Listing(
    id: id,
    cropIcon: crop,
    farmName: farm,
    farmId: farmId,
    status: status,
    categoryName: 'Vegetables',
    ratings: ratings,
  );
}

FarmPin _pin(String id, double lat, double lon) {
  return FarmPin(id: id, name: 'Farm $id', latitude: lat, longitude: lon);
}

void main() {
  group('SearchScreen (Screen 1) — live', () {
    Future<void> pumpSearch(
      WidgetTester tester, {
      Future<List<CropSuggestion>> Function(String)? loadSuggestions,
      List<String> recents = const [],
    }) async {
      SharedPreferences.setMockInitialValues({'recent_searches': recents});
      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            loadSuggestions: loadSuggestions ?? (_) async => const [],
          ),
        ),
      );
      await tester.pump(); // resolve the recents load
    }

    testWidgets('shows RECENT SEARCHES from local storage before typing', (
      tester,
    ) async {
      await pumpSearch(tester, recents: ['Eggplant', 'Cabbage', 'Tomatoes']);

      expect(find.text('RECENT SEARCHES'), findsOneWidget);
      for (final term in ['Eggplant', 'Cabbage', 'Tomatoes']) {
        expect(find.text(term), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty recents shows a friendly placeholder', (tester) async {
      await pumpSearch(tester);

      expect(find.text('RECENT SEARCHES'), findsOneWidget);
      expect(
        find.text('Your recent searches will appear here.'),
        findsOneWidget,
      );
    });

    testWidgets('typing debounces 450ms then shows live suggestion rows', (
      tester,
    ) async {
      var calls = 0;
      await pumpSearch(
        tester,
        loadSuggestions: (term) async {
          calls++;
          return [
            const CropSuggestion(name: 'Tomato', count: 4),
            const CropSuggestion(name: 'Tomato Ridge', count: 1),
          ];
        },
      );

      await tester.enterText(find.byType(TextField), 'tomato');
      await tester.pump();

      expect(find.text('RECENT SEARCHES'), findsNothing);
      expect(find.text('SUGGESTIONS'), findsOneWidget);

      // Debounce hasn't elapsed yet — no suggestion request sent.
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, 0, reason: 'request must wait for the 450ms debounce');

      // Past the debounce: one request, real rows, fake mockup rows gone.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 1);
      expect(find.text('Tomato'), findsOneWidget);
      expect(find.text('4 farms selling nearby'), findsOneWidget);
      expect(find.text('Tomato Ridge'), findsOneWidget);
      expect(find.text('1 farm selling nearby'), findsOneWidget);
      expect(find.text('Beside Little A\u2019s Farm'), findsNothing);
      expect(find.text('Available now'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clearing the field returns to recent searches', (
      tester,
    ) async {
      await pumpSearch(tester, recents: ['Eggplant']);

      await tester.enterText(find.byType(TextField), 'tomato');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('RECENT SEARCHES'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('RECENT SEARCHES'), findsOneWidget);
      expect(find.text('Eggplant'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'submitting navigates to the real results screen with the term',
      (tester) async {
        await pumpSearch(tester);

        await tester.enterText(find.byType(TextField), 'tomato');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        expect(find.byType(SearchResultsScreen), findsOneWidget);
        expect(find.text('Tomato'), findsOneWidget); // results header title
      },
    );

    testWidgets('tapping a recent term navigates with that term', (
      tester,
    ) async {
      await pumpSearch(tester, recents: ['Eggplant']);

      await tester.tap(find.text('Eggplant'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      expect(find.text('Eggplant'), findsOneWidget);
    });

    testWidgets('tapping a suggestion submits that crop name', (tester) async {
      await pumpSearch(
        tester,
        loadSuggestions: (term) async {
          return [const CropSuggestion(name: 'Carrots', count: 3)];
        },
      );

      await tester.enterText(find.byType(TextField), 'car');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Carrots'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      expect(find.text('Carrots'), findsWidgets); // header + suggestion term
    });
  });

  group('RecentSearches (local storage)', () {
    test(
      'stores most-recent-first, deduped (case-insensitive), capped',
      () async {
        SharedPreferences.setMockInitialValues({});
        await RecentSearches.add('Tomato');
        await RecentSearches.add('Eggplant');
        await RecentSearches.add('tomato'); // newer casing wins, dup removed
        await RecentSearches.add('Cabbage');
        await RecentSearches.add('Rice');
        await RecentSearches.add('Pepper');

        expect(await RecentSearches.load(), [
          'Pepper',
          'Rice',
          'Cabbage',
          'tomato',
          'Eggplant',
        ]);
      },
    );

    test('ignores blank terms and starts empty', () async {
      SharedPreferences.setMockInitialValues({});
      await RecentSearches.add('   ');
      await RecentSearches.add('');
      expect(await RecentSearches.load(), isEmpty);
    });
  });

  group('SearchResultsScreen (Screen 2) — live', () {
    Future<void> pumpResults(
      WidgetTester tester, {
      required List<Listing> listings,
      List<FarmPin> farms = const [],
      Future<List<Listing>> Function(String)? loadResults,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsScreen(
            query: 'Carrots',
            loadResults: loadResults ?? (term) async => listings,
            loadBuyerPosition: () async => _userPos,
            loadFarms: () async => farms,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Both text and image search draw the same card widget, so a buyer moving
    // between the two should not see the card change shape. It did: text search
    // built its card payload before any farm coordinate was known, so every
    // card permanently read "Distance unavailable", and the status was never
    // copied across, so no "Available now" pill appeared — while image search,
    // building the same payload after the same lookup, showed both.

    testWidgets('text search cards show a real distance and a status pill', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpResults(
        tester,
        listings: [
          _listing('L1', 'Carrots', 'Bayan Farm', farmId: 'F1'),
          _listing(
            'L2',
            'Carrots',
            'Upland Farm',
            status: 'SOON_TO_HARVEST',
            farmId: 'F2',
          ),
        ],
        farms: [
          // ~1.1 km north of the buyer, and one unknown farm to prove the
          // "unavailable" wording is reserved for farms that really have no
          // coordinates rather than shown for every result.
          _pin('F1', _userPos.latitude + 0.01, _userPos.longitude),
        ],
      );

      expect(find.text('1.0 km away'), findsOneWidget);
      expect(find.text('Available Now'), findsOneWidget);
      expect(find.text('Soon to Harvest'), findsOneWidget);
      // The farm with no pin is the only one allowed to say so.
      expect(find.text('Distance unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('text search cards show the rating, hidden when unrated', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpResults(
        tester,
        listings: [
          _listing(
            'L1',
            'Carrots',
            'Bayan Farm',
            farmId: 'F1',
            ratings: const RatingSummary(average: 4.5, count: 12),
          ),
          // Same crop, nobody has reviewed it: the label has to collapse rather
          // than print a 0.0 that reads like a verdict nobody wrote.
          _listing('L2', 'Carrots', 'Upland Farm', farmId: 'F2'),
        ],
        farms: [_pin('F1', _userPos.latitude, _userPos.longitude)],
      );

      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('(12)'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets(
      'no location shows every result instead of a false radius claim',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: SearchResultsScreen(
              query: 'Carrots',
              loadResults: (_) async => [
                _listing('L1', 'Carrots', 'Bayan Farm', farmId: 'F1'),
              ],
              loadFarms: () async => [_pin('F1', 10.3178, 123.8742)],
              loadBuyerPosition: () async => null,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Splitting an unknown radius would put everything under "Other farms" and
        // claim no farm is within 15 km — a statement about a location never
        // established.
        expect(find.text('Bayan Farm'), findsOneWidget);
        expect(find.textContaining('within'), findsNothing);
        expect(find.text('Near you'), findsNothing);
        expect(find.text('Distance unavailable'), findsOneWidget);
      },
    );

    testWidgets('results render while the permission dialog is still open', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // A first-run permission prompt stays open for as long as the buyer takes
      // to answer it, so the lookup can outlast any timeout the screen would
      // put on it. The results cannot wait for that.
      final pending = Completer<LatLng?>();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsScreen(
            query: 'Carrots',
            loadResults: (_) async => [
              _listing('L1', 'Carrots', 'Bayan Farm', farmId: 'F1'),
            ],
            loadFarms: () async => [
              _pin('F1', _userPos.latitude + 0.01, _userPos.longitude),
            ],
            loadBuyerPosition: () => pending.future,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Bayan Farm'), findsOneWidget);
      // Pending is not "denied": neither a denial message nor a radius claim.
      expect(find.textContaining('Distances need'), findsNothing);
      expect(find.textContaining('within'), findsNothing);

      pending.complete(_userPos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('1.0 km away'), findsOneWidget);
    });

    testWidgets('image-search merges alias terms (kamatis + tomato) into one '
        'mixed list', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsScreen(
            query: 'kamatis',
            groups: const [
              SearchCropGroup(title: 'Tomato', terms: ['kamatis', 'tomato']),
            ],
            detectionConfidences: const [('Tomato', 0.88)],
            loadResults: (term) async => [
              _listing('L1', 'Kamatis', 'Bayan Farm', farmId: 'F1'),
              if (term == 'tomato')
                _listing('L2', 'tomato', 'Upland Farm', farmId: 'F2'),
            ],
            loadFarms: () async => [
              _pin('F1', 10.3178, 123.8742),
              _pin('F2', 10.3178, 123.8742),
            ],
            loadBuyerPosition: () async => _userPos,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // BOTH spellings show together in the single mixed list. Confidence is
      // deliberately NOT surfaced: buyers cannot act on it, so it stays
      // internal to ranking.
      expect(find.text('Bayan Farm'), findsOneWidget);
      expect(find.text('Upland Farm'), findsOneWidget);
      expect(find.textContaining('88%'), findsNothing);
      // No per-crop section header in the mixed list.
      expect(find.text('Near you'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows real count line, sort toolbar, and grid', (
      tester,
    ) async {
      await pumpResults(
        tester,
        listings: [
          _listing('L1', 'Carrots', "Little A's Farm", farmId: 'F1'),
          _listing(
            'L2',
            'Carrots',
            'Big Ben Farm',
            status: 'SOON_TO_HARVEST',
            farmId: 'F2',
          ),
          _listing('L3', 'Carrots', 'Sun Village Farm'),
        ],
        farms: [_pin('F1', 10.3178, 123.8742), _pin('F2', 10.40, 123.95)],
      );

      expect(find.text('Nearest'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      // F1 is at the buyer (0 km -> near), F2 is ~12 km away (near),
      // L3 has no farm/position (grouped under "Other farms").
      expect(
        find.text('2 farms selling Carrots within 15 km of you'),
        findsOneWidget,
      );
      expect(find.text('Near you'), findsOneWidget);
      expect(find.text("Little A's Farm"), findsOneWidget);
      expect(find.text('Big Ben Farm'), findsOneWidget);

      // The far group sits below the fold of the lazy ListView.
      await tester.scrollUntilVisible(
        find.text('Other farms'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Other farms'), findsOneWidget);
      expect(find.text('Sun Village Farm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('farms beyond the radius are grouped under "Other farms" '
        'instead of being hidden', (tester) async {
      await pumpResults(
        tester,
        listings: [
          _listing('L1', 'Carrots', "Little A's Farm", farmId: 'F1'),
          _listing('L2', 'Carrots', 'Far Away Farm', farmId: 'F2'),
          _listing('L3', 'Carrots', 'No Coords Farm'),
        ],
        farms: [
          _pin('F1', 10.3178, 123.8742), // 0 km -> near
          _pin('F2', 10.60, 124.20), // ~65 km away -> "Other farms"
        ],
      );

      expect(find.text('Near you'), findsOneWidget);
      final nearGrid = find.byType(SearchResultGrid).at(0);
      expect(
        find.descendant(of: nearGrid, matching: find.text("Little A's Farm")),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('Other farms'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Far Away Farm'), findsOneWidget);
      expect(find.text('No Coords Farm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('when nothing is near, all results still appear under '
        '"All results"', (tester) async {
      await pumpResults(
        tester,
        listings: [
          _listing('L1', 'Carrots', 'Far Far Away Farm', farmId: 'F1'),
        ],
        farms: [_pin('F1', 10.80, 124.50)], // hugely far from the buyer
      );

      expect(
        find.textContaining('No farms selling Carrots within'),
        findsOneWidget,
      );
      expect(find.text('All results'), findsOneWidget);
      expect(find.text('Far Far Away Farm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Nearest sorts by haversine distance; Available bumps '
        'AVAILABLE_NOW first', (tester) async {
      await pumpResults(
        tester,
        listings: [
          _listing('L1', 'Carrots', "Little A's Farm", farmId: 'F1'), // far
          _listing(
            'L2',
            'Carrots',
            'Big Ben Farm',
            status: 'SOON_TO_HARVEST',
            farmId: 'F2', // near
          ),
        ],
        farms: [
          _pin('F2', 10.3178, 123.8742), // same as buyer position -> nearest
          _pin('F1', 10.80, 124.50), // far
        ],
      );

      var firstCard = find.byType(SearchResultCard).at(0);
      expect(
        find.descendant(of: firstCard, matching: find.text('Big Ben Farm')),
        findsOneWidget,
        reason: 'Nearest order must put the haversine-closest farm first',
      );

      await tester.tap(find.text('Available'));
      await tester.pump();

      firstCard = find.byType(SearchResultCard).at(0);
      expect(
        find.descendant(of: firstCard, matching: find.text("Little A's Farm")),
        findsOneWidget,
        reason: 'Available order puts AVAILABLE_NOW before SOON_TO_HARVEST',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a card opens the real ProductDetailScreen', (
      tester,
    ) async {
      await pumpResults(
        tester,
        listings: [_listing('L1', 'Carrots', "Little A's Farm", farmId: 'F1')],
        farms: [_pin('F1', 10.3178, 123.8742)],
      );

      await tester.tap(find.byType(SearchResultCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
      expect(find.text('Carrots'), findsWidgets);
    });

    testWidgets('empty results shows the friendly empty state', (tester) async {
      await pumpResults(tester, listings: []);

      expect(find.text('0 farms selling Carrots near you'), findsOneWidget);
      expect(find.text('No farms selling this crop yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('network failure shows error state with retry', (tester) async {
      await pumpResults(
        tester,
        listings: const [],
        loadResults: (term) async =>
            throw Exception('Could not reach the server.'),
      );

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('result cards never overflow at phone/desktop sizes and '
        'device text scales', (tester) async {
      final listings = [
        _listing('L1', 'Carrots', "Little A's Farm", farmId: 'F1'),
        _listing('L2', 'Carrots', 'Big Ben Farm', farmId: 'F2'),
        _listing('L3', 'Carrots', 'Sun Village Farm'),
      ];
      for (final width in [360.0, 1280.0]) {
        for (final scale in [1.0, 1.3]) {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);

          await pumpResults(tester, listings: listings);
          await tester.pump();

          expect(
            tester.takeException(),
            isNull,
            reason: 'width $width, text scale $scale must not overflow',
          );
          expect(find.byType(SearchResultCard), findsNWidgets(3));
        }
      }
    });

    testWidgets(
      'image-search cards with an availability badge never overflow',
      (tester) async {
        // The badge sits over the photo, so the multi-crop card layout gets the
        // same overflow sweep as the plain text-search card above.
        const groups = [
          SearchCropGroup(title: 'Cabbage', terms: ['cabbage']),
        ];
        for (final width in [360.0, 1280.0]) {
          for (final scale in [1.0, 1.3]) {
            await tester.binding.setSurfaceSize(Size(width, 900));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.platformDispatcher.clearAllTestValues);

            await tester.pumpWidget(
              MaterialApp(
                home: SearchResultsScreen(
                  query: 'Cabbage',
                  groups: groups,
                  loadResults: (term) async => [
                    _listing(
                      'L1',
                      'Cabbage',
                      "Little A's Farm",
                      status: 'AVAILABLE_NOW',
                      farmId: 'F1',
                    ),
                    _listing(
                      'L2',
                      'Cabbage',
                      'Big Ben Farm',
                      status: 'SOON_TO_HARVEST',
                      farmId: 'F2',
                    ),
                  ],
                  loadBuyerPosition: () async => _userPos,
                  loadFarms: () async => [
                    _pin('F1', _userPos.latitude, _userPos.longitude),
                    _pin('F2', _userPos.latitude + 0.01, _userPos.longitude),
                  ],
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));

            expect(
              tester.takeException(),
              isNull,
              reason: 'width $width, text scale $scale must not overflow',
            );
            // Same labels Home shows, in the same place.
            expect(find.text('Available Now'), findsOneWidget);
            expect(find.text('Soon to Harvest'), findsOneWidget);
            // Confidence stays out of the UI entirely.
            expect(find.textContaining('%'), findsNothing);
          }
        }
      },
    );
  });

  group('ImageSearchScreen (Screen 3) — capture -> identify -> results', () {
    testWidgets('capture step shows viewfinder and Camera/Gallery', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ImageSearchScreen()));

      expect(find.text('Identify crop'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.textContaining('Point your camera'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Camera advances to scanning, then jumps straight to the '
        'live multi-crop results screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Records the terms the screen actually searches for, so alias fan-out
      // is verified rather than assumed.
      final searched = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: ImageSearchScreen(
            pickImage: (_) async => XFile('/tmp/crop.jpg'),
            detect: (_) async => [
              DetectedCrop(name: 'Carrots', confidence: 0.94),
              DetectedCrop(name: 'Lettuce', confidence: 0.77),
            ],
            // A real listing carries the SELLER's own spelling, which is
            // independent of the search term. Distinct ids keep the per-alias
            // dedup in the screen from collapsing these into one card.
            loadResults: (term) async {
              searched.add(term);
              return [
                _listing(
                  'L-$term',
                  'Seller $term',
                  "Little A's Farm",
                  farmId: 'F1',
                ),
              ];
            },
            loadBuyerPosition: () async => _userPos,
            loadFarms: () async => [_pin('F1', 10.3178, 123.8742)],
          ),
        ),
      );

      await tester.tap(find.text('Camera'));
      await tester.pump();
      expect(find.text('Scanning Image'), findsOneWidget);

      // Scan completes -> live results screen (no "detected" interstitial).
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SearchResultsScreen), findsOneWidget);
      // ONE summary line for the whole photo, not a section per crop.
      expect(find.text('2 crops found in your photo'), findsOneWidget);

      // "Lettuce" fans out over its aliases; "Carrots" is an unknown label so
      // it is searched verbatim. Three searches, three cards rendered.
      expect(searched, containsAll(<String>['Carrots', 'lettuce', 'letchuce']));
      expect(find.text('Seller Carrots'), findsOneWidget);
      expect(find.text('Seller lettuce'), findsOneWidget);
      expect(find.text('Seller letchuce'), findsOneWidget);

      // All three listings render as separate cards (the fixture gives each alias
      // its own listing id) and none of them leak a confidence percentage,
      // which is for ranking only.
      expect(find.byType(SearchResultCard), findsNWidgets(3));
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'detecting nothing bounces back to capture with an error toast',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ImageSearchScreen(
              pickImage: (_) async => XFile('/tmp/crop.jpg'),
              detect: (_) async => <DetectedCrop>[],
            ),
          ),
        );

        await tester.tap(find.text('Camera'));
        await tester.pumpAndSettle();

        expect(find.text('Identify crop'), findsOneWidget);
        expect(find.byType(SearchResultsScreen), findsNothing);
        expect(
          find.textContaining('Could not identify the crop'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('HomeScreen search bar entry', () {
    Future<void> pumpHome(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'some-token',
        'user_data':
            '{"USR_ID":"TTTTTT","USR_NAME":"Tester",'
            '"USR_MOBILE_NUMBER":"09170000000","USR_IS_SELLER":0}',
      });
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('tapping the empty hint area opens the SearchScreen', (
      tester,
    ) async {
      await pumpHome(tester);

      // Tap the bar BODY (the hint text), not the magnifier icon — this used to
      // be swallowed by the readOnly TextField, so only the icon navigated.
      await tester.tap(find.text('Search Crops or farms'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('tapping the camera icon opens the ImageSearchScreen', (
      tester,
    ) async {
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.camera_alt_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(ImageSearchScreen), findsOneWidget);
    });
  });
}
