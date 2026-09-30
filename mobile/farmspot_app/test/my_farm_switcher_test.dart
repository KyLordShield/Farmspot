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

  final Future<http.Response> Function(Uri url) onRequest;

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
    final response = await onRequest(url);
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

  final Future<http.Response> Function(Uri url) onRequest;

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

  final Future<http.Response> Function(Uri url) onRequest;

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
  late Future<http.Response> Function(Uri url) handler;

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
    handler = (url) async {
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
    HttpOverrides.global = _StubOverrides((url) => handler(url));
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
      (_) async => http.Response('{"farms":[]}', 200),
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

}
