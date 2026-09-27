import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/screens/home_screen.dart';
import 'package:farmspot_app/screens/messages_inbox_screen.dart';
import 'package:farmspot_app/services/message_service.dart';

/// Stands in for the backend so the Home bell can be exercised without a
/// server. Only the inbox call is used by Home.
class _HomeGateway implements MessagesGateway {
  List<Conversation> inbox = [];
  Object? inboxError;

  @override
  Future<List<Conversation>> fetchConversations() async {
    if (inboxError != null) throw inboxError!;
    return inbox;
  }

  @override
  Future<Conversation> startConversation(String listingId) async =>
      throw UnimplementedError();

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId,
          {String? after}) async =>
      [];

  @override
  Future<ChatMessage> sendMessage(String conversationId, String content) async =>
      throw UnimplementedError();
}

Conversation _thread({int unread = 0, String other = 'React A'}) =>
    Conversation.fromJson({
      'id': 'CNV0001',
      'listing_id': 'LST0001',
      'buyer_id': 'BUY0001',
      'seller_farmer_id': 'FMR0001',
      'farm_id': 'FRM0001',
      'last_message': 'hi',
      'last_message_at': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
      'unread_count': unread,
      'my_role': 'BUYER',
      'farm': {'id': 'FRM0001', 'name': 'React A Farm', 'barangay': 'Sudlon II'},
      'other_party': {'id': 'USR0002', 'name': other, 'photo': null},
      'listing': {
        'id': 'LST0001',
        'crop_icon': 'Carrot',
        'image': null,
        'category': {'id': 'CAT0001', 'name': 'Vegetables'},
        'farm': {
          'id': 'FRM0001',
          'name': 'React A Farm',
          'barangay': 'Sudlon II'
        },
      },
    });

Future<void> _pumpHome(WidgetTester tester, _HomeGateway api) async {
  SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  await tester.pumpWidget(MaterialApp(home: HomeScreen(gateway: api)));
  // Let the feed, the seller status and the unread count settle.
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('the bell is in the header, not buried in the feed',
      (tester) async {
    await _pumpHome(tester, _HomeGateway());

    final bell = find.byIcon(Icons.notifications_none_rounded);
    expect(bell, findsOneWidget);

    // The header sits above the scrollable feed, so the bell is reachable
    // without scrolling and stays put however far down the user is.
    final headerBellY = tester.getTopLeft(bell).dy;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pump();
    expect(tester.getTopLeft(bell).dy, headerBellY,
        reason: 'the entry must not scroll away with the feed');
  });

  testWidgets('no badge when every thread is read', (tester) async {
    await _pumpHome(tester, _HomeGateway()..inbox = [_thread(unread: 0)]);

    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the badge totals unread across every thread', (tester) async {
    await _pumpHome(tester, _HomeGateway()
      ..inbox = [
        _thread(unread: 2),
        _thread(unread: 3, other: 'Maria Santos'),
      ]);

    // 2 + 3 unread, not "the first thread's 2".
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('a large unread count is capped at 99+', (tester) async {
    await _pumpHome(tester,
        _HomeGateway()..inbox = [_thread(unread: 120)]);

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('120'), findsNothing);
  });

  testWidgets('tapping the bell opens the inbox', (tester) async {
    await _pumpHome(tester, _HomeGateway()..inbox = [_thread(unread: 1)]);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MessagesInboxScreen), findsOneWidget);
    expect(find.text('React A'), findsOneWidget,
        reason: 'the inbox must open on the real thread list');
  });

  testWidgets('the header copy stays role-agnostic for a seller who also buys',
      (tester) async {
    // Mark the account as a seller via the cached user the banner reads.
    SharedPreferences.setMockInitialValues({
      'auth_token': 'test-token',
      'user': '{"USR_IS_SELLER":1,"USR_ROLE":"GENERAL_USER"}',
    });
    final api = _HomeGateway()
      ..inbox = [
        _thread(unread: 0, other: 'Maria Santos'), // as a seller
        _thread(unread: 0, other: 'Kapatid Farm'), // as a buyer
      ];
    await tester.pumpWidget(MaterialApp(home: HomeScreen(gateway: api)));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Messages from buyers'), findsNothing,
        reason: 'a farmer can be a buyer in one thread and a seller in another');
  });

  testWidgets('a failed inbox call leaves the bell usable with no badge',
      (tester) async {
    await _pumpHome(tester, _HomeGateway()..inboxError = Exception('offline'));

    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'an unread-count failure must not break the Home screen');
  });
}
