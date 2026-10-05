import 'dart:async';
import 'dart:io';

import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/models/listing_review.dart';
import 'package:farmspot_app/models/my_farm_listing_page.dart';
import 'package:farmspot_app/screens/all_reviews_screen.dart';
import 'package:farmspot_app/screens/seller/my_farm_screen.dart';
import 'package:farmspot_app/services/my_farm_listings_service.dart';
import 'package:farmspot_app/widgets/my_farm_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Answers one intercepted request. The listings endpoint is NOT answered here:
/// it goes through [ScriptedGateway], so a test can hand back a page sequence
/// that no server would produce (an overlapping page, a failing page) without
/// arranging for the socket layer to do it.
///
/// Only farms and farm stats are served, because the screen resolves the
/// selected farm before it asks for any listing.
typedef _RequestHandler =
    Future<http.Response> Function(String method, Uri url);

/// Reports a member the double does not implement, then fails loudly rather than
/// answering null and turning a real gap into a silent empty screen.
Never _missing(Invocation invocation, Object owner, String what) {
  fail(
    'The app used ${invocation.memberName} on $what ($owner), '
    'which this test double does not implement.',
  );
}

class _StubOverrides extends HttpOverrides {
  _StubOverrides(this.onRequest);

  final _RequestHandler onRequest;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _StubClient(onRequest);
}

class _StubHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _StubClientResponse implements HttpClientResponse {
  _StubClientResponse(this._body, this.statusCode);

  final List<int> _body;

  @override
  final int statusCode;

  @override
  final _StubHeaders headers = _StubHeaders();

  @override
  int get contentLength => _body.length;

  // StreamedResponse inspects these when followRedirects is on, and a missing
  // member here would surface as an opaque "could not reach the server" instead
  // of a real failure.
  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => true;

  @override
  String get reasonPhrase => 'OK';

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation i) =>
      _missing(i, runtimeType, 'the HTTP response');
}

class _StubRequest implements HttpClientRequest {
  _StubRequest(this.method, this.url, this.onRequest);

  @override
  final String method;

  /// The URL is recorded by the handler, not read off the interface:
  /// HttpClientRequest has no url member, so this is plain test scaffolding.
  final Uri url;

  final _RequestHandler onRequest;

  @override
  final HttpHeaders headers = _StubHeaders();

  @override
  int contentLength = 0;

  @override
  int maxRedirects = 0;

  @override
  bool followRedirects = true;

  @override
  bool persistentConnection = true;

  Future<HttpClientResponse>? _response;

  @override
  Future<HttpClientResponse> get done => _response ??= _respond();

  @override
  Future<HttpClientResponse> close() => _respond();

  Future<HttpClientResponse> _respond() async {
    final response = await onRequest(method, url);
    return _StubClientResponse(response.bodyBytes, response.statusCode);
  }

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {}

  @override
  Future flush() async {}

  @override
  void write(Object? object) {}

  @override
  dynamic noSuchMethod(Invocation i) =>
      _missing(i, runtimeType, 'the HTTP request');
}

class _StubClient implements HttpClient {
  _StubClient(this.onRequest);

  final _RequestHandler onRequest;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StubRequest(method, url, onRequest);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation i) =>
      _missing(i, runtimeType, 'the HTTP client');
}

/// One farm, so the farm card and switcher stay out of the way and the listing
/// list is the thing under test. The screen's real data path runs; only HTTP is
/// replaced, and only for the two farm endpoints.
void _stubFarmEndpoints() {
  HttpOverrides.global = _StubOverrides((method, url) async {
    if (url.path.endsWith('/farms')) {
      return http.Response(
        '{"farms":[{"FRM_ID":"AAAAAA","FRM_NAME":"North Field",'
        '"FRM_BARANGAY":"Bayan","FRM_STATUS":"APPROVED"}]}',
        200,
      );
    }
    if (url.path.contains('stats')) {
      return http.Response(
        '{"profile_views":0,"buyer_contacts":0,"active_listings":0}',
        200,
      );
    }
    // The listings endpoint must never be answered here: reaching it would mean
    // the screen bypassed the injected gateway, and the test's script would
    // silently stop describing what was rendered.
    fail('${url.path} was fetched over HTTP instead of through the gateway.');
  });
  addTearDown(() => HttpOverrides.global = null);
}

/// A scripted /my-listings.
///
/// Records every request and answers from [pages], so a test can assert both what
/// was asked for (page, farm, filter) and what came back. The failure modes of an
/// infinite list are all about which request went out and when: a page fetched
/// twice, a page fetched past the end, or a filter applied on the client instead
/// of being asked for.
class ScriptedGateway implements MyFarmListingsGateway {
  /// Answers by page number.
  final Map<int, MyFarmListingPage> pages = {};

  final List<
    ({int page, int perPage, String? farmId, MyFarmStatusFilter status})
  >
  requests = [];

  /// Pages that throw instead of answering.
  final Set<int> failingPages = {};

  /// Set to hold page 1 open, so a test can act before it lands.
  Completer<MyFarmListingPage>? holdFirstPage;

  @override
  Future<MyFarmListingPage> fetch({
    required int page,
    required int perPage,
    required String? farmId,
    required MyFarmStatusFilter status,
  }) async {
    requests.add((
      page: page,
      perPage: perPage,
      farmId: farmId,
      status: status,
    ));

    if (page == 1) {
      final hold = holdFirstPage;
      if (hold != null) return hold.future;
    }

    if (failingPages.contains(page)) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    return pages[page] ?? const MyFarmListingPage();
  }

  int get callCount => requests.length;

  ({int page, int perPage, String? farmId, MyFarmStatusFilter status})?
  get last => requests.isEmpty ? null : requests.last;

  List<int> get pagesRequested =>
      requests.map((r) => r.page).toList(growable: false);
}

/// A listing as My Farm receives it: the fields the row reads, and nothing else.
Listing aListing(
  String id,
  String crop, {
  String farmId = 'AAAAAA',
  String status = 'AVAILABLE_NOW',
  String availability = 'ACTIVE',
  double? ratingAverage,
  int ratingCount = 0,
  bool hasOpenReport = false,
  String? expiryDate,
}) {
  return Listing(
    id: id,
    cropIcon: crop,
    status: status,
    availability: availability,
    expiryDate: expiryDate,
    farmId: farmId,
    farmName: 'North Field',
    categoryId: 'CAT001',
    categoryName: 'Vegetable',
    hasOpenReport: hasOpenReport,
    ratings: RatingSummary(average: ratingAverage, count: ratingCount),
  );
}

/// One page of listings, with a summary that agrees with it unless a test says
/// otherwise.
MyFarmListingPage aPage({
  List<Listing> listings = const [],
  int currentPage = 1,
  int lastPage = 1,
  int? total,
  MyFarmSummary? summary,
}) {
  final count = total ?? listings.length;
  return MyFarmListingPage(
    listings: listings,
    currentPage: currentPage,
    lastPage: lastPage,
    total: count,
    summary: summary ?? MyFarmSummary(totalListings: count, activeCount: count),
  );
}

void _usePhone(WidgetTester tester, {Size size = const Size(400, 900)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Lets the screen's futures land. Real async, so it needs runAsync before a
/// pump can show the result.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The page's vertical Scrollable, excluding the horizontal farm switcher and
/// filter row. scrollUntilVisible wants the Scrollable the CustomScrollView
/// builds, not the widget itself.
final pageScrollable = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axis == Axis.vertical,
);

/// A row's text, scoped to that row.
///
/// Unscoped, these texts collide with the filter row: the "Expired" chip is both
/// a filter and a listing status, so `find.text('Expired')` would match the
/// filter plus the row and scroll to whichever comes first.
Finder inRow(String text) => find.descendant(
  of: find.byType(MyFarmListingRow),
  matching: find.text(text),
);

/// A row's text, scoped to that row and not required to match exactly.
Finder inRowContaining(Pattern text) => find.descendant(
  of: find.byType(MyFarmListingRow),
  matching: find.textContaining(text),
);

/// Scrolls down until [finder] is on screen. The rows are built lazily, so
/// asserting on one without revealing it first would pass or fail for the wrong
/// reason.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 120, scrollable: pageScrollable);
  await settle(tester);
}

/// Scrolls up until [finder] is on screen.
///
/// scrollUntilVisible only ever scrolls one way — down, for a list that reads
/// top to bottom — so it can never find a row that has scrolled off above the
/// viewport. This drags the other way instead.
Future<void> revealAbove(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(finder, pageScrollable, const Offset(0, 200));
  await settle(tester);
}

/// The filter row's own horizontal Scrollable, so a chip further right can be
/// scrolled into existence — it is a ListView, so the last chips are not built
/// until the row is scrolled.
final filterScrollable = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axis == Axis.horizontal,
);

/// Taps a filter chip, scrolling the horizontal chip row to it first.
///
/// The row is a ListView, so a chip past the right edge is not built at all and
/// one past the left edge has been unbuilt — tapping either misses, because the
/// chip's centre is outside the 400px-wide test screen. Walk the row towards the
/// chip in small steps, reversing if a step scrolls it out of existence.
Future<void> tapFilter(WidgetTester tester, MyFarmStatusFilter filter) async {
  final chip = find.byKey(MyFarmFilterRow.chipKey(filter));
  // Bring it into existence first; from here it is scrolled, not built.
  await tester.scrollUntilVisible(chip, 60, scrollable: filterScrollable);

  var towardsRight = true;
  for (var step = 0; step < 40; step++) {
    if (!tester.any(chip)) {
      // Stepped past it. Come back the other way.
      await tester.drag(filterScrollable, Offset(towardsRight ? -60 : 60, 0));
      towardsRight = !towardsRight;
      await settle(tester);
      continue;
    }
    final centre = tester.getCenter(chip, warnIfMissed: false);
    if (centre.dx >= 8 && centre.dx <= 392) break;
    // Off the left edge means dragging the row rightwards, and vice versa.
    towardsRight = centre.dx < 8;
    await tester.drag(filterScrollable, Offset(towardsRight ? 60 : -60, 0));
    await settle(tester);
  }

  await tester.tap(chip);
  await settle(tester);
}

Future<void> scrollToTop(WidgetTester tester) async {
  await tester.drag(pageScrollable, const Offset(0, 3000));
  await settle(tester);
  await tester.pumpAndSettle();
}

/// Scrolls the page down far enough to trigger the next-page threshold.
///
/// The negative offset is deliberate: it drags the finger up the screen, which
/// moves the content down the list. A positive offset would scroll *back* to the
/// top and pull the RefreshIndicator over on the way, reloading the whole list.
Future<void> scrollToBottom(WidgetTester tester) async {
  await tester.drag(pageScrollable, const Offset(0, -6000));
  await settle(tester);
}

void main() {
  late ScriptedGateway gateway;

  setUp(() => gateway = ScriptedGateway());

  Future<void> pumpScreen(WidgetTester tester) async {
    _usePhone(tester);
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    _stubFarmEndpoints();
    await tester.pumpWidget(MaterialApp(home: MyFarmScreen(gateway: gateway)));
    await settle(tester);
  }

  /*
  |--------------------------------------------------------------------------
  | Paging
  |--------------------------------------------------------------------------
  */

  testWidgets('the first load asks for page one with paging parameters', (
    tester,
  ) async {
    gateway.pages[1] = aPage(listings: [aListing('LST001', 'Tomato')]);
    await pumpScreen(tester);

    expect(gateway.last!.page, 1);
    expect(gateway.last!.perPage, 10);
    expect(gateway.last!.status, MyFarmStatusFilter.all);

    await reveal(tester, find.text('Tomato'));
    expect(find.text('Tomato'), findsOneWidget);
  });

  testWidgets('scrolling to the end appends the next page', (tester) async {
    gateway.pages[1] = aPage(
      listings: [for (var i = 1; i <= 10; i++) aListing('LST$i', 'Crop $i')],
      currentPage: 1,
      lastPage: 3,
      total: 25,
    );
    gateway.pages[2] = aPage(
      listings: [for (var i = 11; i <= 20; i++) aListing('LST$i', 'Crop $i')],
      currentPage: 2,
      lastPage: 3,
      total: 25,
    );

    await pumpScreen(tester);
    expect(gateway.pagesRequested, [1]);

    await scrollToBottom(tester);

    expect(gateway.pagesRequested, [1, 2]);

    await reveal(tester, find.text('Crop 11'));
    expect(find.text('Crop 11'), findsOneWidget);

    // Appending, not replacing: page one's last row is still there. Scrolling
    // back up to it is the only way to see it, the sliver list has since unbuilt
    // it — but it is still in the list.
    await revealAbove(tester, find.text('Crop 10'));
    expect(find.text('Crop 10'), findsOneWidget);
  });

  testWidgets(
    'the last page is not requested again however far the seller scrolls',
    (tester) async {
      gateway.pages[1] = aPage(listings: [aListing('LST001', 'Tomato')]);
      await pumpScreen(tester);
      expect(gateway.pagesRequested, [1]);

      for (var i = 0; i < 5; i++) {
        await tester.drag(pageScrollable, const Offset(0, -2000));
        await settle(tester);
      }

      // Every scroll asks "is there more?", and the answer stays no. Asking again
      // would mean an empty request every time the seller reaches the bottom.
      expect(gateway.pagesRequested, [1]);
    },
  );

  testWidgets('a row that arrives on two pages is shown once', (tester) async {
    // What happens when a listing is created between two page requests: the
    // server's page 1 shifts and a row shows up again on page 2.
    gateway.pages[1] = aPage(
      listings: [for (var i = 1; i <= 10; i++) aListing('LST$i', 'Crop $i')],
      currentPage: 1,
      lastPage: 2,
      total: 11,
    );
    // LST10 is page one's tenth row; the server now offers it again because a
    // listing was inserted ahead of it between the two requests.
    gateway.pages[2] = aPage(
      listings: [aListing('LST10', 'Crop 10'), aListing('LST11', 'Crop 11')],
      currentPage: 2,
      lastPage: 2,
      total: 11,
    );

    await pumpScreen(tester);
    await scrollToBottom(tester);

    await reveal(tester, find.text('Crop 11'));

    expect(
      find.text('Crop 10'),
      findsOneWidget,
      reason: 'the same listing on two pages is one row, not two',
    );
    expect(find.text('Crop 11'), findsOneWidget);
  });

  testWidgets('a failed page keeps the rows already on screen', (tester) async {
    gateway.pages[1] = aPage(
      listings: [for (var i = 1; i <= 10; i++) aListing('LST$i', 'Crop $i')],
      currentPage: 1,
      lastPage: 2,
      total: 12,
    );
    gateway.failingPages.add(2);

    await pumpScreen(tester);
    await scrollToBottom(tester);

    // The retry rides under the last row, so it has to be scrolled into view
    // before it can be asserted on. Scrolling there means scrolling past page
    // one's first row, which the sliver list has since unbuilt — the rows are
    // only "kept" in state, not pinned on screen.
    await reveal(tester, find.text('Retry'));
    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Back up to the rows the seller was reading. A failure must not empty the
    // list, and the page-2 request produced none of its own.
    await scrollToTop(tester);
    expect(find.text('Crop 1'), findsOneWidget);
    await reveal(tester, find.text('Crop 10'));
    expect(find.text('Crop 10'), findsOneWidget);
  });

  testWidgets('retry loads the missing page exactly once', (tester) async {
    gateway.pages[1] = aPage(
      listings: [for (var i = 1; i <= 10; i++) aListing('LST$i', 'Crop $i')],
      currentPage: 1,
      lastPage: 2,
      total: 12,
    );
    gateway.failingPages.add(2);
    gateway.pages[2] = aPage(
      listings: [aListing('LST011', 'Crop 11')],
      currentPage: 2,
      lastPage: 2,
      total: 12,
    );

    await pumpScreen(tester);
    await scrollToBottom(tester);

    expect(gateway.pagesRequested.where((p) => p == 2).length, 1);

    // The trailing error sits under the bottom nav bar at the end of the list,
    // so it has to be scrolled up into the clear before it can be tapped.
    await revealAbove(tester, find.text('Retry'));

    // The connection comes back: this attempt is the one that works.
    gateway.failingPages.remove(2);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await settle(tester);

    expect(
      gateway.pagesRequested.where((p) => p == 2).length,
      2,
      reason: 'one retry, one request — a second tap must not queue another',
    );

    await reveal(tester, find.text('Crop 11'));
    expect(find.text('Crop 11'), findsOneWidget);
    expect(
      find.text('Retry'),
      findsNothing,
      reason: 'the retry is gone once it has worked',
    );
  });

  testWidgets('a failed first load offers a retry that reloads', (
    tester,
  ) async {
    gateway.failingPages.add(1);
    await pumpScreen(tester);

    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    expect(find.byType(MyFarmListingRow), findsNothing);

    gateway.failingPages.clear();
    gateway.pages[1] = aPage(listings: [aListing('LST001', 'Tomato')]);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await settle(tester);

    await reveal(tester, find.text('Tomato'));
    expect(find.text('Tomato'), findsOneWidget);
  });

  /*
  |--------------------------------------------------------------------------
  | Filters
  |--------------------------------------------------------------------------
  */

  testWidgets('a filter chip asks the server for that bucket', (tester) async {
    gateway.pages[1] = aPage(listings: [aListing('LST001', 'Tomato')]);
    await pumpScreen(tester);
    expect(gateway.last!.status, MyFarmStatusFilter.all);

    await tapFilter(tester, MyFarmStatusFilter.expired);

    expect(gateway.last!.status, MyFarmStatusFilter.expired);
    expect(
      gateway.last!.page,
      1,
      reason: 'a new filter starts from page 1, never from page 2',
    );
  });

  testWidgets('tapping the chip already selected asks for nothing', (
    tester,
  ) async {
    gateway.pages[1] = aPage(listings: [aListing('LST001', 'Tomato')]);
    await pumpScreen(tester);

    final before = gateway.callCount;
    await tester.tap(
      find.byKey(MyFarmFilterRow.chipKey(MyFarmStatusFilter.all)),
    );
    await settle(tester);

    expect(gateway.callCount, before);
  });

  testWidgets('an empty filter names the filter, not the whole farm', (
    tester,
  ) async {
    gateway.pages[1] = aPage(listings: const []);
    await pumpScreen(tester);

    await tapFilter(tester, MyFarmStatusFilter.hidden);

    await reveal(tester, find.textContaining('no hidden by admin listings'));
    expect(find.textContaining('no hidden by admin listings'), findsOneWidget);
    // The farm is not empty, so nothing may claim it is.
    expect(find.textContaining('No crops listed yet'), findsNothing);
  });

  /*
  |--------------------------------------------------------------------------
  | Ratings
  |--------------------------------------------------------------------------
  */

  testWidgets('a rated listing shows its average and count', (tester) async {
    gateway.pages[1] = aPage(
      listings: [
        aListing('LST001', 'Tomato', ratingAverage: 4.5, ratingCount: 12),
      ],
      summary: const MyFarmSummary(
        totalListings: 1,
        activeCount: 1,
        reviewCount: 12,
        ratingAverage: 4.5,
      ),
    );
    await pumpScreen(tester);

    await reveal(tester, find.text('Tomato'));

    // Once on the row, once in the farm summary.
    expect(find.text('4.5'), findsNWidgets(2));
    expect(find.text(' (12)'), findsOneWidget);
    expect(find.text('Based on 12 reviews'), findsOneWidget);
  });

  testWidgets('an unreviewed listing says so instead of showing zero', (
    tester,
  ) async {
    gateway.pages[1] = aPage(listings: [aListing('LST001', 'Tomato')]);
    await pumpScreen(tester);

    await reveal(tester, find.text('Tomato'));

    // On the row and in the summary card: neither may invent a score nobody gave.
    expect(find.text('No reviews yet'), findsNWidgets(2));
    expect(find.text('0.0'), findsNothing);
  });

  testWidgets('the rating label opens the existing reviews screen', (
    tester,
  ) async {
    gateway.pages[1] = aPage(
      listings: [
        aListing('LST001', 'Tomato', ratingAverage: 4.5, ratingCount: 12),
      ],
    );
    await pumpScreen(tester);

    await reveal(tester, find.text('4.5'));
    await tester.tap(find.text('4.5'));
    await tester.pumpAndSettle();

    // Reused as-is. The seller reads the list a buyer reads, and the server's
    // can_review keeps it read-only, so there is no owner-only variant that
    // could drift away from it.
    expect(find.byType(AllReviewsScreen), findsOneWidget);
  });

  /*
  |--------------------------------------------------------------------------
  | Status, moderation and reports
  |--------------------------------------------------------------------------
  */

  testWidgets('an admin-hidden listing explains itself', (tester) async {
    gateway.pages[1] = aPage(
      listings: [aListing('LST001', 'Tomato', availability: 'REMOVED')],
    );
    await pumpScreen(tester);

    await reveal(tester, find.textContaining('Hidden by admin'));

    expect(
      find.textContaining(
        'Buyers cannot see this listing. '
        'Contact the Association Secretary.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a moderated listing still offers its other actions', (
    tester,
  ) async {
    gateway.pages[1] = aPage(
      listings: [aListing('LST001', 'Tomato', availability: 'REMOVED')],
    );
    await pumpScreen(tester);

    await reveal(tester, find.textContaining('Hidden by admin'));

    // Hidden from buyers is not read-only for the seller.
    expect(find.text('Change status'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
  });

  testWidgets('a reported listing shows Under review and nothing more', (
    tester,
  ) async {
    gateway.pages[1] = aPage(
      listings: [aListing('LST001', 'Tomato', hasOpenReport: true)],
    );
    await pumpScreen(tester);

    await reveal(tester, find.textContaining('Under review'));

    expect(
      find.textContaining(
        'A report on this listing is being reviewed '
        'by the Association.',
      ),
      findsOneWidget,
    );
    // The chip states the fact and stops there: a seller who could read the
    // accusation, or who filed it, would know who to be angry at.
    expect(find.textContaining('Reported by'), findsNothing);
  });

  testWidgets('an expired listing offers Renew', (tester) async {
    gateway.pages[1] = aPage(
      listings: [
        aListing(
          'LST001',
          'Tomato',
          expiryDate: DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        ),
      ],
    );
    await pumpScreen(tester);

    await reveal(tester, inRow('Expired'));
    expect(inRow('Renew'), findsOneWidget);
  });

  testWidgets('a live listing counts down the days left', (tester) async {
    gateway.pages[1] = aPage(
      listings: [
        aListing(
          'LST001',
          'Tomato',
          expiryDate: DateTime.now()
              .add(const Duration(days: 2))
              .toIso8601String(),
        ),
      ],
    );
    await pumpScreen(tester);

    await reveal(tester, find.text('Tomato'));

    expect(find.text('Expires in 2 days'), findsOneWidget);
    // Renew belongs to an expired listing only.
    expect(find.text('Renew'), findsNothing);
  });

  testWidgets('each LST_STATUS keeps its own label and colour source', (
    tester,
  ) async {
    expect(ListingOwnerChips.statusInfo('AVAILABLE_NOW').$1, 'Available Now');
    expect(
      ListingOwnerChips.statusInfo('SOON_TO_HARVEST').$1,
      'Soon to Harvest',
    );
    expect(ListingOwnerChips.statusInfo('NOT_AVAILABLE').$1, 'Not Available');
    // Anything the server invents later must not render as an empty chip.
    expect(ListingOwnerChips.statusInfo('SOMETHING_NEW').$1, 'Not Available');
  });

  /*
  |--------------------------------------------------------------------------
  | Summary
  |--------------------------------------------------------------------------
  */

  testWidgets('the summary reports the farm, not the loaded page', (
    tester,
  ) async {
    gateway.pages[1] = aPage(
      listings: [aListing('LST001', 'Tomato')],
      currentPage: 1,
      lastPage: 4,
      total: 37,
      summary: const MyFarmSummary(
        totalListings: 37,
        activeCount: 30,
        expiredCount: 4,
        hiddenCount: 2,
        underReviewCount: 1,
        reviewCount: 88,
        ratingAverage: 4.1,
      ),
    );
    await pumpScreen(tester);

    // One row is loaded; the card must still say 37. Scoped to the card,
    // because the "All" filter chip carries the same total.
    expect(
      find.descendant(
        of: find.byType(MyFarmSummaryCard),
        matching: find.text('37'),
      ),
      findsOneWidget,
    );
    expect(find.text('4.1'), findsOneWidget);
    expect(find.text('Based on 88 reviews'), findsOneWidget);
  });

  testWidgets('the filter counts do not change with the selected filter', (
    tester,
  ) async {
    gateway.pages[1] = aPage(
      listings: [aListing('LST001', 'Tomato')],
      total: 37,
      summary: const MyFarmSummary(
        totalListings: 37,
        activeCount: 30,
        expiredCount: 4,
        hiddenCount: 2,
        underReviewCount: 1,
      ),
    );
    await pumpScreen(tester);

    int totalShown() => find
        .descendant(
          of: find.byType(MyFarmSummaryCard),
          matching: find.text('37'),
        )
        .evaluate()
        .length;
    int allChipCount() => find
        .descendant(
          of: find.byKey(MyFarmFilterRow.chipKey(MyFarmStatusFilter.all)),
          matching: find.text('37'),
        )
        .evaluate()
        .length;

    expect(totalShown(), 1);
    expect(allChipCount(), 1);

    await tester.tap(
      find.byKey(MyFarmFilterRow.chipKey(MyFarmStatusFilter.active)),
    );
    await settle(tester);

    // The totals describe the farm, so narrowing the list cannot shrink them.
    expect(totalShown(), 1);
    expect(allChipCount(), 1);
  });

  /*
  |--------------------------------------------------------------------------
  | Thumbnails
  |--------------------------------------------------------------------------
  */

  test('a Cloudinary list URL is requested at list size', () {
    expect(
      ListingThumbnail.resizedForTest(
        'https://res.cloudinary.com/x/image/upload/v123/abc.jpg',
      ),
      'https://res.cloudinary.com/x/image/upload/w_300,q_auto,f_auto/v123/abc.jpg',
    );
  });

  test('a URL that is not Cloudinary is left alone', () {
    expect(
      ListingThumbnail.resizedForTest('https://example.com/a/b.jpg'),
      'https://example.com/a/b.jpg',
    );
  });

  test('an existing transformation is not stacked twice', () {
    const once = 'https://res.cloudinary.com/x/image/upload/w_800,q_auto/a.jpg';
    expect(ListingThumbnail.resizedForTest(once), once);
  });

  test('a null or empty URL stays null so the placeholder shows', () {
    expect(ListingThumbnail.resizedForTest(null), isNull);
    expect(ListingThumbnail.resizedForTest(''), isNull);
  });

  test('a page with no pagination block is treated as one whole page', () {
    // A server that predates paging sends no pagination key. "Is there more?"
    // must be answerable rather than defaulting to yes, forever.
    final page = MyFarmListingPage.fromJson({
      'listings': [
        {'id': 'LST001', 'status': 'AVAILABLE_NOW'},
      ],
    });

    expect(page.currentPage, 1);
    expect(page.lastPage, 1);
    expect(page.hasMore, isFalse);
    expect(page.total, 1);
  });
}
