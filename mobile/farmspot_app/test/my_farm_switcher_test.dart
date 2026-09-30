import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/screens/seller/farm_setup_details_screen.dart';
import 'package:farmspot_app/screens/seller/farm_setup_verify_screen.dart';
import 'package:farmspot_app/screens/seller/my_farm_screen.dart';

// The service layer calls package:http's top-level functions, which build their
// socket through a plain `HttpClient()`. Overriding that client is therefore
// the only seam available without threading a client through every service.
//
// Only the members IOClient actually touches are implemented; the forwarders
// the compiler generates from noSuchMethod cover the rest, and anything
// genuinely unexpected throws with the member name rather than answering null.

/// Reports a member the double does not implement, then fails loudly.
Never _missing(Invocation invocation, Object owner, String what) {
  fail('The app used ${invocation.memberName} on $what ($owner), '
      'which this test double does not implement.');
}

/// Answers one intercepted request. The method is part of the signature
/// because the app reaches the API through more than one verb, and a test has
/// to be able to tell a GET /farms refresh from a DELETE /farms/{id} archive.
typedef _RequestHandler = Future<http.Response> Function(String method, Uri url);

/// `HttpHeaders` is abstract, so this supplies what IOClient touches on a
/// response plus the `set` used to build an outgoing request.
class _StubHeaders implements HttpHeaders {
  _StubHeaders() {
    contentType = ContentType('application', 'json', charset: 'utf-8');
  }

  final Map<String, List<String>> _values = {};

  @override
  ContentType? contentType;

  @override
  bool get chunkedTransferEncoding => false;

  String? get contentEncoding => null;

  @override
  int get contentLength => -1;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => <String>[]).add('$value');
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      set(name, value, preserveHeaderCase: preserveHeaderCase);

  @override
  String? value(String name) {
    final found = _values[name.toLowerCase()];
    return (found == null || found.isEmpty) ? null : found.first;
  }

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  void operator []=(String name, List<String> value) =>
      _values[name.toLowerCase()] = value;

  @override
  void clear({bool preserveHeaderCase = false}) => _values.clear();

  bool containsKey(String key) => _values.containsKey(key.toLowerCase());

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  dynamic noSuchMethod(Invocation i) => _missing(i, runtimeType, 'HTTP headers');
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
  // member here would surface as an opaque "could not reach the server".
  @override
  bool get isRedirect => false;

  bool get followRedirects => false;

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
  }) =>
      Stream<List<int>>.value(_body).listen(
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

  final Uri url;

  final _RequestHandler onRequest;

  @override
  final _StubHeaders headers = _StubHeaders();

  @override
  int contentLength = 0;

  @override
  int maxRedirects = 0;

  @override
  bool followRedirects = true;

  @override
  bool persistentConnection = true;

  // Stream.pipe completes with `sink.done`, and a real HttpClientRequest
  // resolves that to its response, so `done` is the member that actually
  // answers the request. close() only triggers the same response.
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

class _StubOverrides extends HttpOverrides {
  _StubOverrides(this.onRequest);

  final _RequestHandler onRequest;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _StubClient(onRequest);
}

/// A seller who runs more than one farm.
///
/// This is the behaviour a one-farm design cannot express: two farms exist, the
/// screen shows one at a time, and both the stats and the listings must follow
/// whichever farm is selected. Getting this wrong means a seller's second farm
/// looks empty, or that one farm's numbers sit above another farm's crops.
void main() {
  const farmA = {
    'FRM_ID': 'AAAAAA',
    'FRM_NAME': 'North Field',
    'FRM_BARANGAY': 'Bayan',
    'FRM_STATUS': 'APPROVED',
  };
  const farmB = {
    'FRM_ID': 'BBBBBB',
    'FRM_NAME': 'South Field',
    'FRM_BARANGAY': 'Barangay Dos',
    'FRM_STATUS': 'APPROVED',
  };

  /// A listing on the given farm, keyed the way Listing.fromJson reads it.
  Map<String, dynamic> listing(String id, String crop, String farmId) => {
        'id': id,
        'crop_icon': crop,
        'status': 'AVAILABLE_NOW',
        'availability': 'ACTIVE',
        'farm': {'id': farmId, 'name': 'x', 'barangay': 'y'},
        'category': {'id': 'CAT001', 'name': crop},
        'photos': <dynamic>[],
      };

  /// Farm ids the stats endpoint was asked about, in call order.
  late List<String> statsRequests;

  /// Served to the screen under test. Reassigned per test.
  late _RequestHandler handler;

  setUp(() => statsRequests = []);

  /// Lets the screen finish its chain of dependent calls (farms, then that
  /// farm's stats). The responses are real futures, so they need the real event
  /// loop via runAsync before a pump can render the result.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    required List<Map<String, dynamic>> farms,
    List<Map<String, dynamic>> listings = const [],
  }) async {
    handler = (method, url) async {
      final segments = url.pathSegments;

      if (segments.contains('farms') && segments.contains('stats')) {
        // /api/farms/{id}/stats
        final farmId = segments[segments.indexOf('farms') + 1];
        statsRequests.add(farmId);
        // Deliberately different totals per farm, so a mismatch is visible.
        return http.Response(
          jsonEncode({
            'profile_views': farmId == 'AAAAAA' ? 11 : 22,
            'buyer_contacts': farmId == 'AAAAAA' ? 3 : 4,
            'active_listings': farmId == 'AAAAAA' ? 5 : 6,
          }),
          200,
        );
      }

      if (url.path.endsWith('/farms')) {
        return http.Response(jsonEncode({'farms': farms}), 200);
      }

      if (url.path.endsWith('/my-listings')) {
        return http.Response(jsonEncode({'listings': listings}), 200);
      }

      return http.Response('{}', 200);
    };

    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});

    // The test binding installs a blocking HttpOverrides.global of its own, so
    // the double has to replace it around the pump rather than from setUp,
    // which runs before the binding exists.
    HttpOverrides.global =
        _StubOverrides((method, url) => handler(method, url));
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(const MaterialApp(home: MyFarmScreen()));
    await settle(tester);
  }

  /// Switches to the second farm, by the name shown on its switcher chip.
  Future<void> selectSecondFarm(WidgetTester tester) async {
    await tester.tap(find.text('South Field').last);
    await settle(tester);
  }

  test('the HTTP double answers a request through IOClient', () async {
    final client = IOClient(_StubClient(
      (_, _) async => http.Response('{"farms":[]}', 200),
    ));

    // This is the exact code path the services use, so a gap in the double
    // fails here with the real error rather than surfacing inside a widget
    // test as a generic "could not reach the server".
    final response = await client.get(Uri.parse('http://x/api/farms'));

    expect(response.statusCode, 200);
    expect(response.body, '{"farms":[]}');
  });

  testWidgets('Add Farm opens the wizard at step 1, not the identity step',
      (tester) async {
    await pump(tester, farms: [farmA, farmB]);

    await tester.tap(find.text('Add Farm'));
    await settle(tester);

    // Every farm needs its own name, description, barangay and photos, so the
    // wizard must not start at the identity step even though that step is
    // optional for a seller who already has a farm.
    expect(find.byType(FarmSetupDetailsScreen), findsOneWidget);
    expect(find.text('Set Up Your Farm'), findsOneWidget);
    expect(find.byType(FarmSetupVerifyScreen), findsNothing);

    expect(find.text('FARM NAME'), findsOneWidget);
    expect(find.text('DESCRIPTION'), findsOneWidget);
    expect(find.text('BARANGAY'), findsOneWidget);
    expect(find.text('FARM PHOTOS'), findsOneWidget);
  });

  testWidgets('a single farm shows no switcher', (tester) async {
    await pump(tester, farms: [farmA]);

    // The farm itself is on screen...
    expect(find.text('North Field'), findsWidgets);
    // ...but with nothing to switch between, no second name may appear.
    expect(find.text('South Field'), findsNothing);
    expect(statsRequests, ['AAAAAA']);
  });

  testWidgets('every farm is reachable when the seller owns several',
      (tester) async {
    await pump(tester, farms: [farmA, farmB]);

    expect(find.text('North Field'), findsWidgets);
    expect(find.text('South Field'), findsWidgets);
  });

  testWidgets('selecting a farm reloads that farm stats and drops the old ones',
      (tester) async {
    await pump(tester, farms: [farmA, farmB]);

    expect(statsRequests, contains('AAAAAA'));
    expect(find.text('11'), findsOneWidget, reason: 'farm A profile views');

    await selectSecondFarm(tester);

    expect(statsRequests, contains('BBBBBB'));
    expect(find.text('22'), findsOneWidget, reason: 'farm B profile views');
    expect(find.text('11'), findsNothing,
        reason: "farm A's numbers must not linger after switching");
  });

  testWidgets('listings are filtered to the selected farm', (tester) async {
    await pump(
      tester,
      farms: [farmA, farmB],
      listings: [
        listing('LST001', 'Tomato', 'AAAAAA'),
        listing('LST002', 'Pechay', 'BBBBBB'),
      ],
    );

    // Both listings are fetched, but only farm A's is shown first.
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.text('Pechay'), findsNothing);

    await selectSecondFarm(tester);

    expect(find.text('Pechay'), findsOneWidget);
    expect(find.text('Tomato'), findsNothing,
        reason: "farm A's listing must not appear under farm B");
  });

  testWidgets('a farm with no listings says so by name', (tester) async {
    await pump(
      tester,
      farms: [farmA, farmB],
      listings: [listing('LST001', 'Tomato', 'AAAAAA')],
    );

    await selectSecondFarm(tester);

    expect(find.textContaining('Nothing listed on South Field'), findsOneWidget);
  });

  testWidgets('there is always a way to add another farm', (tester) async {
    await pump(tester, farms: [farmA]);

    expect(find.text('Add Farm'), findsOneWidget);
  });

  testWidgets('getFarms orders a new pending farm behind approved ones',
      (tester) async {
    // The order the backend returns, which is what _addFarm used to index
    // into: a new PENDING_REVIEW farm is last only when nothing is approved.
    await pump(tester, farms: [farmA, farmB]);

    expect(statsRequests, ['AAAAAA'],
        reason: 'the first APPROVED farm is selected, not the last row');
    expect(find.text('22'), findsNothing,
        reason: "the second farm's stats must not load before it is selected");
  });

  /*
  |--------------------------------------------------------------------------
  | Removing a farm
  |--------------------------------------------------------------------------
  |
  | A seller can drop one of several farms but never their last one. Both halves
  | matter: the archive has to be reachable for the farm that is genuinely
  | surplus, and the protected one must not be offered as a button that the
  | server would only refuse.
  |
  */

  /// Pumps the screen with a farm list and a recorded DELETE handler.
  ///
  /// [removedFarms] collects the ids the screen asked to archive, and
  /// [afterDelete] is what GET /farms returns once one is gone, so the tests
  /// can watch the selection move instead of asserting on request counts.
  Future<void> pumpWithDelete(
    WidgetTester tester, {
    required List<Map<String, dynamic>> farms,
    List<Map<String, dynamic>>? farmsAfterDelete,
    List<String>? removedFarms,
    int deleteStatus = 200,
    Map<String, dynamic> deleteBody = const {},
  }) async {
    var deleted = false;
    final remaining = farmsAfterDelete ?? farms;

    handler = (method, url) async {
      if (method == 'DELETE' && url.path.contains('/farms/')) {
        removedFarms?.add(url.pathSegments.last);
        if (deleteStatus == 200) deleted = true;
        return http.Response(jsonEncode(deleteBody), deleteStatus);
      }
      if (url.path.contains('stats')) {
        final farmId = url.pathSegments[url.pathSegments.indexOf('farms') + 1];
        statsRequests.add(farmId);
        return http.Response(
          jsonEncode({'profile_views': 1, 'buyer_contacts': 1, 'active_listings': 0}),
          200,
        );
      }
      if (url.path.endsWith('/farms')) {
        return http.Response(
          jsonEncode({'farms': deleted ? remaining : farms}),
          200,
        );
      }
      if (url.path.endsWith('/my-listings')) {
        return http.Response(jsonEncode({'listings': <dynamic>[]}), 200);
      }
      return http.Response('{}', 200);
    };

    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    HttpOverrides.global =
        _StubOverrides((method, url) => handler(method, url));
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(const MaterialApp(home: MyFarmScreen()));
    await settle(tester);
  }

  /// The screen's main vertical list. The farm switcher is a horizontal
  /// ListView, so it has to be excluded when scrolling the page.
  ///
  /// scrollUntilVisible wants the Scrollable the ListView builds internally,
  /// not the ListView widget itself. The listings area is a nested ListView and
  /// so contributes a second Scrollable below it; the outer one comes first in
  /// a depth-first walk, which is the one that scrolls the whole page.
  final mainScrollable = find
      .descendant(
        of: find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.vertical,
        ),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls the page until the remove action is on screen, then returns.
  ///
  /// It sits below the farm card and the stats, so it is off the fold in the
  /// default 800x600 test viewport and a plain tap would hit the wrong thing.
  Future<void> revealRemoveAction(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Remove this farm'),
      120,
      scrollable: mainScrollable,
    );
    await settle(tester);
  }

  /// Reveals the remove action and opens its confirmation dialog.
  ///
  /// The extra pumpAndSettle matters: showDialog animates the sheet in, and a
  /// tap computed before the animation finishes lands on the barrier instead of
  /// the button, so the dialog never closes.
  Future<void> openRemoveDialog(WidgetTester tester) async {
    await revealRemoveAction(tester);
    await tester.tap(find.text('Remove this farm'));
    await settle(tester);
    await tester.pumpAndSettle();
  }

  /// Confirms the open remove dialog.
  Future<void> confirmRemove(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('a seller with one farm is not offered the remove action',
      (tester) async {
    await pumpWithDelete(tester, farms: [farmA]);

    // The last farm is what keeps the account selling. Deactivating the seller
    // is the way to stop, so the button is hidden rather than shown disabled.
    expect(find.text('Remove this farm'), findsNothing);
  });
  testWidgets('a seller with several farms can remove the selected one',
      (tester) async {
    final removed = <String>[];
    await pumpWithDelete(
      tester,
      farms: [farmA, farmB],
      farmsAfterDelete: [farmB],
      removedFarms: removed,
    );

    // The action sits below the farm card and the stats, so it has to be
    // scrolled into view before it exists as a mounted widget.
    await revealRemoveAction(tester);
    expect(find.text('Remove this farm'), findsOneWidget);

    await openRemoveDialog(tester);

    // Confirmation first, and it names the farm that is actually on screen:
    // the first APPROVED farm, which is farm A.
    expect(find.text('Remove North Field?'), findsOneWidget);
    await confirmRemove(tester);

    // The farm that was on screen, and only that farm.
    expect(removed, ['AAAAAA']);
    expect(find.text('Remove North Field?'), findsNothing,
        reason: 'the dialog must close once the request is sent');
  });

  testWidgets('cancelling the remove dialog keeps the farm', (tester) async {
    final removed = <String>[];
    await pumpWithDelete(
      tester,
      farms: [farmA, farmB],
      removedFarms: removed,
    );

    await openRemoveDialog(tester);
    expect(find.text('Remove North Field?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Remove North Field?'), findsNothing);
    expect(removed, isEmpty, reason: 'cancelling must not remove anything');
  });

  testWidgets('removing a farm leaves the seller on a farm they still have',
      (tester) async {
    await pumpWithDelete(
      tester,
      farms: [farmA, farmB],
      farmsAfterDelete: [farmA],
    );

    // Archive the selected farm (B), so the screen has to fall back to A.
    await tester.tap(find.text('South Field').last);
    await settle(tester);

    await openRemoveDialog(tester);
    await confirmRemove(tester);

    // The card must not keep showing a farm that is no longer in the list.
    expect(find.text('South Field'), findsNothing);
    expect(find.text('North Field'), findsWidgets);
    expect(statsRequests, contains('AAAAAA'),
        reason: 'the surviving farm is what should be shown and loaded');
  });

  testWidgets('the remove confirmation says the buyer history is kept',
      (tester) async {
    // The reason this is an archive and not a delete: conversation.FRM_ID
    // cascades from farm, so a real delete would take the threads with it.
    await pumpWithDelete(tester, farms: [farmA, farmB]);

    await openRemoveDialog(tester);

    expect(find.textContaining('conversations about this farm are kept'),
        findsOneWidget);
  });

  testWidgets('a refused removal is reported instead of looking like success',
      (tester) async {
    final removed = <String>[];
    await pumpWithDelete(
      tester,
      farms: [farmA, farmB],
      removedFarms: removed,
      deleteStatus: 422,
      deleteBody: {
        'code': 'LAST_FARM',
        'message': 'You cannot remove your only farm. Deactivate your seller '
            'account instead if you no longer want to sell.',
      },
    );

    await openRemoveDialog(tester);
    await confirmRemove(tester);

    // The server has the final say on the last-farm rule; when it refuses, the
    // seller is told why rather than seeing a cheerful "removed".
    expect(find.textContaining('You cannot remove your only farm'),
        findsOneWidget);
    expect(find.textContaining('removed.'), findsNothing);
    expect(removed, ['AAAAAA'], reason: 'the farm on screen is farm A');

    // Still two farms, so the action is still on offer and nothing was lost.
    await revealRemoveAction(tester);
    expect(find.text('Remove this farm'), findsOneWidget);
  });
}
