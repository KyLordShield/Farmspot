import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/screens/in_app_messages_screen.dart';
import 'package:farmspot_app/screens/messages_inbox_screen.dart';
import 'package:farmspot_app/services/message_service.dart';

Map<String, dynamic> conversationJson({
  String id = 'CNV0001',
  String otherName = 'React A',
  String? cropName = 'carrot',
  int unread = 0,
  String role = 'BUYER',
  String? lastMessage = 'last one',
}) {
  return {
    'id': id,
    'listing_id': 'LST0001',
    'buyer_id': 'BUY0001',
    'seller_farmer_id': 'FMR0001',
    'farm_id': 'FRM0001',
    'last_message': lastMessage,
    'last_message_at':
        DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
    'created_at': DateTime.now().toIso8601String(),
    'unread_count': unread,
    'my_role': role,
    'farm': {
      'id': 'FRM0001',
      'name': 'React A Farm',
      'barangay': 'Sudlon II'
    },
    'other_party': {'id': 'USR0002', 'name': otherName, 'photo': null},
    'listing': {
      'id': 'LST0001',
      'crop_icon': cropName,
      'image': null,
      'category': {'id': 'CAT0001', 'name': 'Vegetables'},
      'farm': {
        'id': 'FRM0001',
        'name': 'React A Farm',
        'barangay': 'Sudlon II'
      },
    },
  };
}

ChatMessage message({
  required String id,
  required String content,
  required bool isMine,
  int minutesAgo = 1,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'CNV0001',
    senderId: isMine ? 'USR0001' : 'USR0002',
    content: content,
    isMine: isMine,
    isRead: isMine,
    createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
  );
}

/// In-memory stand-in for the backend, so the chat's polling, sending and
/// failure handling are exercised without a server.
class FakeGateway implements MessagesGateway {
  List<ChatMessage> stored = [];
  List<Conversation> inbox = [];
  String? sendError;
  int messageReads = 0;
  int sends = 0;
  String? lastAfterCursor;

  @override
  Future<Conversation> startConversation(String listingId) async =>
      Conversation.fromJson(conversationJson());

  @override
  Future<List<Conversation>> fetchConversations() async => inbox;

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId,
      {String? after}) async {
    messageReads++;
    lastAfterCursor = after;
    if (after == null) return List.of(stored);
    // Mirror the server's incremental contract: everything newer than the
    // cursor the client already holds.
    final index = stored.indexWhere((m) => m.id == after);
    if (index < 0) return List.of(stored);
    return stored.sublist(index + 1);
  }

  @override
  Future<ChatMessage> sendMessage(String conversationId, String content) async {
    sends++;
    if (sendError != null) throw Exception(sendError!);
    final saved = message(id: 'MSGNEW$sends', content: content, isMine: true);
    stored = [...stored, saved];
    return saved;
  }
}

Conversation thread({String role = 'BUYER', String otherName = 'React A'}) =>
    Conversation.fromJson(conversationJson(role: role, otherName: otherName));

Future<void> _pumpChat(
  WidgetTester tester,
  FakeGateway api, {
  Conversation? conversation,
}) async {
  SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  await tester.pumpWidget(
    MaterialApp(
      home: InAppMessagesScreen(
        conversation: conversation ?? thread(),
        gateway: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  test('Conversation parses the server payload, including unread and role', () {
    final c = Conversation.fromJson(conversationJson(unread: 3));

    expect(c.id, 'CNV0001');
    expect(c.listingId, 'LST0001');
    expect(c.otherPartyName, 'React A');
    expect(c.farmName, 'React A Farm');
    expect(c.barangay, 'Sudlon II');
    expect(c.cropName, 'carrot',
        reason: 'the seller-typed crop name wins over the category');
    expect(c.unreadCount, 3);
    expect(c.myRole, 'BUYER');
    expect(c.isSellerSide, isFalse);
  });

  test('crop name falls back to the category when the seller typed none', () {
    final c = Conversation.fromJson(conversationJson(cropName: null));

    expect(c.cropName, 'Vegetables');
  });

  test('a missing counterparty name falls back to the role', () {
    final c = Conversation.fromJson(
        conversationJson(otherName: '', role: 'SELLER'));

    expect(c.isSellerSide, isTrue);
  });

  testWidgets('chat renders the real history from the backend', (tester) async {
    final api = FakeGateway()
      ..stored = [
        message(id: 'MSG0001', content: 'Is the carrot available?', isMine: false),
        message(id: 'MSG0002', content: 'Yes, plenty!', isMine: true),
      ];

    await _pumpChat(tester, api);

    expect(find.text('Is the carrot available?'), findsOneWidget);
    expect(find.text('Yes, plenty!'), findsOneWidget);
    expect(find.text('React A'), findsOneWidget);
    expect(find.text('About: carrot'), findsOneWidget);
  });

  testWidgets('an empty thread prompts the buyer to start the conversation',
      (tester) async {
    await _pumpChat(tester, FakeGateway());

    expect(find.textContaining('Send the seller a question'), findsOneWidget);
  });

  testWidgets('the seller sees buyer-specific empty-state copy', (tester) async {
    await _pumpChat(tester, FakeGateway(), conversation: thread(role: 'SELLER'));

    expect(find.textContaining('Ask the buyer about the crop'), findsOneWidget);
  });

  testWidgets('sending posts to the backend and renders the stored row',
      (tester) async {
    final api = FakeGateway();
    await _pumpChat(tester, api);

    await tester.enterText(find.byType(TextField), 'Can I pick up tomorrow?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.sends, 1, reason: 'a message must reach the backend');
    expect(find.text('Can I pick up tomorrow?'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
      reason: 'the input clears once the server has stored the message',
    );
  });

  testWidgets('a failed send is surfaced and the text is not lost',
      (tester) async {
    final api = FakeGateway()..sendError = 'Server hiccup';
    await _pumpChat(tester, api);

    await tester.enterText(find.byType(TextField), 'hello?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Server hiccup'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'hello?',
      reason: 'the buyer must be able to retry without retyping',
    );
  });

  testWidgets('an empty message is never sent', (tester) async {
    final api = FakeGateway();
    await _pumpChat(tester, api);

    await tester.enterText(find.byType(TextField), '    ');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(api.sends, 0, reason: 'whitespace is not a message');
  });

  testWidgets('an open thread polls and shows a new reply without a refresh',
      (tester) async {
    final api = FakeGateway()
      ..stored = [message(id: 'MSG0001', content: 'Freshly harvested', isMine: false)];
    await _pumpChat(tester, api);

    expect(api.messageReads, 1, reason: 'history is read once on open');
    expect(api.lastAfterCursor, isNull,
        reason: 'the first read asks for the whole thread');

    // The other side replies while this thread sits open.
    api.stored = [
      ...api.stored,
      message(id: 'MSG0002', content: 'On my way now', isMine: false, minutesAgo: 0),
    ];

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.messageReads, greaterThan(1),
        reason: 'an open chat must re-read the thread on a timer');
    expect(api.lastAfterCursor, 'MSG0001',
        reason: 'polls must only ask for what is newer than what we hold');
    expect(find.text('On my way now'), findsOneWidget,
        reason: 'a reply appears without the user pulling to refresh');
  });

  testWidgets('polling stops once the screen is closed', (tester) async {
    final api = FakeGateway();
    await _pumpChat(tester, api);

    final readsWhileOpen = api.messageReads;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump(const Duration(seconds: 12));

    expect(api.messageReads, readsWhileOpen,
        reason: 'a closed chat must not keep hitting the server');
  });

  testWidgets('inbox lists threads with unread counts and opens one',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    final api = FakeGateway()
      ..inbox = [
        Conversation.fromJson(conversationJson(unread: 2)),
        Conversation.fromJson(conversationJson(
            id: 'CNV0002', otherName: 'Maria Santos', cropName: 'lettuce')),
      ];

    await tester.pumpWidget(
      MaterialApp(home: MessagesInboxScreen(gateway: api)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('React A'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'unread badge is shown');
    expect(find.text('About carrot'), findsOneWidget);
    expect(find.text('About lettuce'), findsOneWidget);

    await tester.tap(find.text('React A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(InAppMessagesScreen), findsOneWidget);
  });

  testWidgets('an empty inbox explains what to do next', (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    await tester.pumpWidget(
      MaterialApp(home: MessagesInboxScreen(gateway: FakeGateway())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No messages yet'), findsOneWidget);
  });
}
