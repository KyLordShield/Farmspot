import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cross_file/cross_file.dart';

import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/models/home_feed_page.dart';
import 'package:farmspot_app/models/home_filters.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/screens/home_screen.dart';
import 'package:farmspot_app/services/home_feed_gateway.dart';
import 'package:farmspot_app/services/message_service.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

/// The home feed as a sequence of pages instead of one unpaged response.
///
/// Each test here is about one of the three things paging can get wrong, and
/// all three are invisible in the app until you look for them: a spinner where
/// the skeleton should be, a second page that never arrives because the scroll
/// listener fired on a list that has no extent yet, and a page two that repeats
/// a listing from page one.
class _FakeFeed implements HomeFeedGateway {
  /// Page number -> the rows that page returns.
  final Map<int, List<Listing>> pages;

  /// Page numbers that should throw the first time they are asked for, and
  /// answer afterwards. Used to pin recovery: a page that fails forever would
  /// leave the retry button on screen and prove nothing about what happens
  /// after it succeeds.
  final Set<int> failingOncePages;

  /// Every page number actually asked for, in order.
  final List<int> requested = [];

  /// Filters seen on the first request, so a test can pin what was sent.
  String? firstCategory;
  bool? firstPersonalized;

  _FakeFeed({required this.pages, this.failingOncePages = const {}});

  @override
  Future<HomeFeedPage> fetchFeedPage({
    required int page,
    required int perPage,
    String? search,
    String? category,
    String? availability,
    HomeSortMode sort = HomeSortMode.latest,
    bool personalized = true,
  }) async {
    requested.add(page);
    if (page == 1) {
      firstCategory = category;
      firstPersonalized = personalized;
    }
    if (failingOncePages.contains(page)) {
      failingOncePages.remove(page);
      throw Exception('Could not reach the server. Check your connection.');
    }
    final rows = pages[page] ?? const [];
    final lastPage = pages.keys.isEmpty
        ? 1
        : pages.keys.reduce((a, b) => a > b ? a : b);
    return HomeFeedPage(
      listings: rows,
      currentPage: page,
      lastPage: lastPage,
      total: lastPage * perPage,
    );
  }
}

class _NoMessages implements MessagesGateway {
  @override
  Future<List<Conversation>> fetchConversations() async => [];

  @override
  Future<Conversation> startConversation(String listingId) async =>
      throw UnimplementedError();

  @override
  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    String? after,
  }) async => [];

  @override
  Future<ChatMessage> sendMessage(
    String conversationId,
    String content, {
    XFile? image,
  }) async => throw UnimplementedError();
}

Listing _row(String id) => Listing(
  id: id,
  cropIcon: 'Crop $id',
  status: 'AVAILABLE_NOW',
  farmName: 'Reyes Farm',
  farmId: 'FRM001',
  categoryId: 'LEAFVG',
);

List<Listing> _rows(String prefix, int count) => [
  for (var i = 1; i <= count; i++) _row('$prefix$i'),
];

Future<void> _pumpHome(WidgetTester tester, _FakeFeed feed) async {
  SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(gateway: _NoMessages(), feedGateway: feed),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  // The feed's first paint waits on the public-farm fetch and the buyer's
  // position, and both are real async work — a socket and a platform channel.
  // A testWidgets body runs under fake async, where neither can ever complete,
  // so the wait has to happen inside runAsync or the feed stays a skeleton
  // forever. Only that first step needs it: the fake gateway below is pure
  // Dart, so later pages settle in the ordinary pump loop.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('first load shows the ladder skeleton, then real cards', (
    tester,
  ) async {
    final feed = _FakeFeed(pages: {1: _rows('A', 4)});
    await _pumpHome(tester, feed);
    await tester.pump();

    // Skeleton rather than a bare spinner: the feed keeps its shape while the
    // first page is in flight.
    expect(find.byType(CropCardSkeleton), findsWidgets);
    expect(find.byType(CropCard), findsNothing);

    await _settle(tester);

    expect(find.byType(CropCardSkeleton), findsNothing);
    expect(find.byType(CropCard), findsNWidgets(4));
    expect(feed.requested, [1]);
  });

  testWidgets('scrolling to the bottom appends the next page', (tester) async {
    final feed = _FakeFeed(pages: {1: _rows('A', 6), 2: _rows('B', 6)});
    await _pumpHome(tester, feed);
    await _settle(tester);

    expect(find.text('Crop A1'), findsOneWidget);
    expect(feed.requested, [1]);

    // Well past the threshold: a fling would do it, a drag has to.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await _settle(tester);

    expect(feed.requested, [1, 2]);

    // Down to the end, where page two's last card now sits.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await _settle(tester);

    expect(find.text('Crop B6'), findsOneWidget);
  });

  testWidgets('the default feed asks the server to rank it', (tester) async {
    final feed = _FakeFeed(pages: {1: _rows('A', 2)});
    await _pumpHome(tester, feed);
    await _settle(tester);

    expect(feed.firstPersonalized, isTrue);
    expect(feed.firstCategory, isNull);
  });

  testWidgets('a listing repeated by the server is not shown twice', (
    tester,
  ) async {
    // Ranking shifts between requests, so the same row can come back on page
    // two. The repeats here are the two cards the buyer is looking at when the
    // next page lands, so a second copy would be right on screen.
    final feed = _FakeFeed(
      pages: {
        1: _rows('A', 8),
        2: [_row('A7'), _row('A8')],
      },
    );
    await _pumpHome(tester, feed);
    await _settle(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await _settle(tester);

    expect(feed.requested, [1, 2]);
    expect(
      find.text('Crop A8'),
      findsOneWidget,
      reason: 'a listing already on the feed is not appended a second time',
    );
  });

  testWidgets('a failed later page keeps the cards and offers a retry', (
    tester,
  ) async {
    final feed = _FakeFeed(
      pages: {1: _rows('A', 6), 2: _rows('B', 6)},
      failingOncePages: {2},
    );
    await _pumpHome(tester, feed);
    await _settle(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await _settle(tester);

    // The feed did not collapse into an error screen over six good cards.
    expect(find.byType(CropCard), findsNWidgets(6));
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);

    // The retry asks for the same page again, not the next one.
    await tester.ensureVisible(find.text('Try again'));
    await tester.pump();
    await tester.tap(find.text('Try again'));
    await _settle(tester);

    expect(feed.requested, [1, 2, 2]);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a last page does not keep asking for more', (tester) async {
    final feed = _FakeFeed(pages: {1: _rows('A', 4)});
    await _pumpHome(tester, feed);
    await _settle(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await _settle(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await _settle(tester);

    expect(feed.requested, [1]);
  });
}
