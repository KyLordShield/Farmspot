import 'dart:convert';
import 'package:farmspot_app/widgets/premium_member_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farmspot_app/models/buy_request.dart';
import 'package:farmspot_app/models/crop_choice.dart';
import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/services/buy_request_service.dart';
import 'package:farmspot_app/screens/premium/buy_request_form_screen.dart';
import 'package:farmspot_app/screens/premium/my_requests_screen.dart';
import 'package:farmspot_app/screens/seller/requests_board_screen.dart';
import 'package:farmspot_app/screens/in_app_messages_screen.dart';

const row = BuyRequest(
  id: 'REQ001',
  crop: 'Pechay',
  quantityKg: 15.5,
  frequency: 'weekly',
  buyerId: 'BUY001',
  buyerName: 'Test Buyer',
  pickupLocation: 'Can collect in Sudlon',
);
const thread = Conversation(
  id: 'CON001',
  listingId: '',
  buyRequestId: 'REQ001',
  cropName: 'Pechay',
  myRole: 'SELLER',
  otherPartyStatus: 'ACTIVE',
  otherPartyId: 'BUY001',
  otherPartyName: 'Test Buyer',
);
Map<String, dynamic> requestJson() => {
  'id': 'REQ001',
  'crop': 'Pechay',
  'quantity_kg': 15.5,
  'frequency': 'weekly',
  'note': '',
  'pickup_location': 'Can collect in Sudlon',
  'buyer': {'id': 'BUY001', 'name': 'Test Buyer'},
  'response_count': 0,
};

class FakeRequests implements BuyRequestsGateway {
  List<BuyRequest> rows = [row];
  String? contacted, removed, search;
  Map<String, dynamic>? posted;
  bool failRemove = false;
  String? updatedId;
  @override
  Future<List<CropChoice>> fetchCrops() async => const [
    CropChoice('Cabbage', ['repolyo']),
    CropChoice('Pechay'),
    CropChoice('Tomato'),
  ];

  @override
  Future<List<BuyRequest>> fetchMine() async => List.of(rows);
  @override
  Future<List<BuyRequest>> fetchBoard({String? search}) async {
    this.search = search;
    return rows;
  }

  @override
  Future<BuyRequest> create({
    required String crop,
    required double quantityKg,
    required String frequency,
    String? note,
    String? pickupLocation,
    double? latitude,
    double? longitude,
  }) async {
    posted = {
      'crop': crop,
      'quantity_kg': quantityKg,
      'frequency': frequency,
      'note': note,
      'pickup_location': pickupLocation,
      'latitude': latitude,
      'longitude': longitude,
    };
    return row;
  }

  @override
  Future<BuyRequest> update({
    required String id,
    required String crop,
    required double quantityKg,
    required String frequency,
    String? note,
    String? pickupLocation,
    double? latitude,
    double? longitude,
  }) async {
    updatedId = id;
    return create(
      crop: crop,
      quantityKg: quantityKg,
      frequency: frequency,
      note: note,
      pickupLocation: pickupLocation,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<void> remove(String id) async {
    if (failRemove) throw Exception('Removal failed');
    removed = id;
    rows = [];
  }

  @override
  Future<Conversation> contactBuyer(String id) async {
    contacted = id;
    return thread;
  }

  @override
  Future<List<Conversation>> fetchResponses(String id) async => [thread];
}

void main() {
  test(
    'service updates existing request and explicitly clears removed pin',
    () async {
      final api = BuyRequestService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path.endsWith('/buy-requests/REQ001'), isTrue);
          final body = jsonDecode(request.body) as Map;
          expect(body.containsKey('latitude'), isTrue);
          expect(body['latitude'], isNull);
          expect(body['longitude'], isNull);
          return http.Response(
            jsonEncode({
              'request': {
                ...requestJson(),
                'updated_at': '2026-10-28T10:00:00Z',
              },
            }),
            200,
          );
        }),
      );
      final saved = await api.update(
        id: 'REQ001',
        crop: 'Pechay',
        quantityKg: 15.5,
        frequency: 'weekly',
      );
      expect(saved.updatedAt, DateTime.utc(2026, 10, 28, 10));
    },
  );

  testWidgets(
    'edit prefills request, locks responded crop and saves changed quantity',
    (tester) async {
      final api = FakeRequests();
      await tester.pumpWidget(
        MaterialApp(
          home: BuyRequestFormScreen(
            gateway: api,
            request: const BuyRequest(
              id: 'REQ001',
              crop: 'Pechay',
              quantityKg: 15.5,
              frequency: 'weekly',
              responseCount: 1,
              latitude: 10,
              longitude: 123,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit Buy Request'), findsOneWidget);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.controller!.text, 'Pechay');
      expect(fields.first.readOnly, isTrue);
      expect(find.widgetWithText(ChoiceChip, 'Pechay'), findsNothing);
      await tester.enterText(find.byType(TextField).at(1), '23.75');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(api.updatedId, 'REQ001');
      expect(api.posted?['quantity_kg'], 23.75);
      expect(api.posted?['latitude'], 10);
    },
  );

  testWidgets('crop remains editable before any seller responds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BuyRequestFormScreen(gateway: FakeRequests(), request: row),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).readOnly,
      isFalse,
    );
    await tester.enterText(find.byType(TextField).first, 'Tomato');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Tomato'), findsOneWidget);
  });

  testWidgets('premium buyer badge appears on the seller request board', (
    tester,
  ) async {
    final api = FakeRequests()
      ..rows = [
        BuyRequest.fromJson({
          ...requestJson(),
          'buyer': {
            'id': 'BUY001',
            'name': 'Test Buyer',
            'is_premium': true,
            'premium_expires_at': DateTime.now()
                .add(const Duration(days: 30))
                .toIso8601String(),
          },
        }),
      ];
    await tester.pumpWidget(
      MaterialApp(home: RequestsBoardScreen(gateway: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Premium'), findsOneWidget);
    expect(find.byType(PremiumMemberBadge), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('membership badge disappears when the subscription expires', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PremiumMemberBadge(
          isPremium: true,
          expiresAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      ),
    );
    expect(find.text('Premium'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Premium'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: PremiumMemberBadge(
          isPremium: false,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
      ),
    );
    expect(find.text('Premium'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'notification opens the referenced request at the top of the board',
    (tester) async {
      final api = FakeRequests();
      await tester.pumpWidget(
        MaterialApp(
          home: RequestsBoardScreen(gateway: api, focusRequestId: 'REQ001'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Request from your alert'), findsOneWidget);
      expect(
        find.text('The request from your alert is no longer available.'),
        findsNothing,
      );
    },
  );
  testWidgets('notification explains when its request has been removed', (
    tester,
  ) async {
    final api = FakeRequests()..rows = [];
    await tester.pumpWidget(
      MaterialApp(
        home: RequestsBoardScreen(gateway: api, focusRequestId: 'REQ001'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The request from your alert is no longer available.'),
      findsOneWidget,
    );
  });

  setUp(
    () => SharedPreferences.setMockInitialValues({'auth_token': 'test-token'}),
  );

  test(
    'service posts real request details without radius or expiry fields',
    () async {
      final api = BuyRequestService(
        client: MockClient((request) async {
          expect(request.url.path.endsWith('/buy-requests'), isTrue);
          expect(request.headers['Authorization'], 'Bearer test-token');
          final body = jsonDecode(request.body) as Map;
          expect(body['quantity_kg'], 15.5);
          expect(body.containsKey('radius'), isFalse);
          expect(body.containsKey('expires_at'), isFalse);
          expect(body.containsKey('latitude'), isFalse);
          return http.Response(jsonEncode({'request': requestJson()}), 201);
        }),
      );
      final saved = await api.create(
        crop: 'Pechay',
        quantityKg: 15.5,
        frequency: 'weekly',
      );
      expect(saved.id, 'REQ001');
    },
  );

  test(
    'request chat parses the existing conversation contract without a listing',
    () {
      final parsed = Conversation.fromJson({
        'id': 'CON001',
        'listing_id': null,
        'my_role': 'SELLER',
        'buy_request': {'id': 'REQ001', 'crop': 'Pechay', 'removed': false},
        'other_party': {'id': 'BUY001', 'name': 'Buyer', 'status': 'ACTIVE'},
      });
      expect(parsed.cropName, 'Pechay');
      expect(parsed.listingId, '');
      expect(parsed.buyRequestId, 'REQ001');
      expect(parsed.isSellerSide, isTrue);
    },
  );

  test(
    'service surfaces premium refusal and does not fake a successful post',
    () async {
      final api = BuyRequestService(
        client: MockClient(
          (_) async => http.Response('{"message":"Premium is required"}', 403),
        ),
      );
      await expectLater(
        api.create(crop: 'Pechay', quantityKg: 15, frequency: 'weekly'),
        throwsA(predicate((e) => e.toString().contains('Premium is required'))),
      );
    },
  );

  testWidgets(
    'form has no distance cutoff and saves entered quantity and pickup details',
    (tester) async {
      final api = FakeRequests();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BuyRequestFormScreen(gateway: api),
                ),
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      expect(find.text('Expires in'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pechay'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), '23.75');
      await tester.tap(find.text('Post request'));
      await tester.pumpAndSettle();
      expect(api.posted?['quantity_kg'], 23.75);
      expect(api.posted?['latitude'], isNull);
      expect(find.text('Open form'), findsOneWidget);
    },
  );

  testWidgets(
    'removal is confirmed and persisted before the request disappears',
    (tester) async {
      final api = FakeRequests();
      await tester.pumpWidget(
        MaterialApp(home: MyRequestsScreen(gateway: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pechay'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(api.removed, 'REQ001');
      expect(find.text('Pechay'), findsNothing);
    },
  );

  testWidgets('failed deletion keeps the request visible', (tester) async {
    final api = FakeRequests()..failRemove = true;
    await tester.pumpWidget(MaterialApp(home: MyRequestsScreen(gateway: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(find.text('Pechay'), findsOneWidget);
    expect(find.text('Removal failed'), findsOneWidget);
  });

  testWidgets('free seller board opens the existing in-app chat', (
    tester,
  ) async {
    final api = FakeRequests();
    await tester.pumpWidget(
      MaterialApp(home: RequestsBoardScreen(gateway: api)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Test Buyer'), findsOneWidget);
    expect(find.textContaining('No location shared'), findsOneWidget);
    await tester.tap(find.text('Message buyer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.contacted, 'REQ001');
    expect(find.byType(InAppMessagesScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
