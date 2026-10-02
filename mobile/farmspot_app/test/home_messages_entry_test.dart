import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/app_notification.dart';
import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/screens/home_screen.dart';
import 'package:farmspot_app/screens/messages_inbox_screen.dart';
import 'package:farmspot_app/screens/notifications_screen.dart';
import 'package:farmspot_app/services/message_service.dart';
import 'package:farmspot_app/services/notification_service.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

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
  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    String? after,
  }) async => [];

  @override
  Future<ChatMessage> sendMessage(
    String conversationId,
    String content,
  ) async => throw UnimplementedError();
}

Conversation _thread({
  int unread = 0,
  String other = 'React A',
}) => Conversation.fromJson({
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
    'farm': {'id': 'FRM0001', 'name': 'React A Farm', 'barangay': 'Sudlon II'},
  },
});

/// Stands in for the notification endpoint so the Home bell badge can be
/// exercised without a server. Default: an empty inbox, which is why the
/// existing header tests keep seeing no second badge.
class _HomeNotifications implements NotificationsGateway {
  int unread = 0;
  Object? error;
  List<AppNotification> items = [];

  @override
  Future<int> fetchUnreadCount() async {
    if (error != null) throw error!;
    return unread;
  }

  @override
  Future<NotificationPage> fetchPage(int page) async {
    if (error != null) throw error!;
    return NotificationPage(
      items: items,
      unreadCount: unread,
      currentPage: page,
      lastPage: 1,
      total: items.length,
    );
  }

  @override
  Future<AppNotification> markAsRead(String id) async =>
      throw UnimplementedError();

  @override
  Future<int> markAllAsRead() async {
    unread = 0;
    return 0;
  }
}

Future<void> _pumpHome(
  WidgetTester tester,
  _HomeGateway api, [
  _HomeNotifications? notifications,
]) async {
  SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        gateway: api,
        notificationGateway: notifications ?? _HomeNotifications(),
      ),
    ),
  );
  // Let the feed, the seller status and the unread count settle.
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('messages and notifications are separate header buttons', (
    tester,
  ) async {
    await _pumpHome(tester, _HomeGateway());

    expect(
      find.byIcon(Icons.chat_bubble_outline_rounded),
      findsOneWidget,
      reason: 'the message button carries the conversation entry point',
    );
    expect(
      find.byIcon(Icons.notifications_none_rounded),
      findsOneWidget,
      reason: 'the bell now means notifications, not messages',
    );
  });

  testWidgets('both buttons stay put when the feed scrolls', (tester) async {
    await _pumpHome(tester, _HomeGateway());

    final messagesY = tester
        .getTopLeft(find.byIcon(Icons.chat_bubble_outline_rounded))
        .dy;
    final bellY = tester
        .getTopLeft(find.byIcon(Icons.notifications_none_rounded))
        .dy;

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.byIcon(Icons.chat_bubble_outline_rounded)).dy,
      messagesY,
    );
    expect(
      tester.getTopLeft(find.byIcon(Icons.notifications_none_rounded)).dy,
      bellY,
    );
  });

  testWidgets('the search bar is trimmed but still wide enough to use', (
    tester,
  ) async {
    await _pumpHome(tester, _HomeGateway());

    final field = find.byType(HomeSearchField);
    final width = tester.getSize(field).width;

    // Trimmed from 46 tall, yet still the widest thing in the header.
    expect(tester.getSize(field).height, 40);
    expect(
      width,
      greaterThan(200),
      reason: 'the bar must not be squeezed into a stub by the two buttons',
    );
    expect(find.text('Search Crops or farms'), findsOneWidget);
  });

  testWidgets('both buttons still fit beside the bar on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpHome(tester, _HomeGateway());

    // Geometry, not a whole-screen overflow assertion: the "Available now" row
    // below overflows at 320dp under the test font (every glyph is a full em
    // square), which is unrelated to the header.
    final bellRight = tester
        .getTopRight(find.byIcon(Icons.notifications_none_rounded))
        .dx;
    final messagesRight = tester
        .getTopRight(find.byIcon(Icons.chat_bubble_outline_rounded))
        .dx;

    expect(
      bellRight,
      lessThanOrEqualTo(304.5),
      reason: 'the bell must sit inside the 16dp header padding',
    );
    expect(
      messagesRight,
      lessThan(bellRight),
      reason: 'messages sit to the left of notifications',
    );
    expect(
      tester.getSize(find.byType(HomeSearchField)).width,
      greaterThan(150),
      reason: 'the bar must not be squeezed into a stub by the two buttons',
    );
  });

  testWidgets('the header icons have no plate behind them', (tester) async {
    await _pumpHome(tester, _HomeGateway());

    for (final icon in [
      find.byIcon(Icons.chat_bubble_outline_rounded),
      find.byIcon(Icons.notifications_none_rounded),
    ]) {
      final glyph = tester.widget<Icon>(icon);
      expect(
        glyph.color,
        Colors.white,
        reason: 'the glyph sits directly on the green header now',
      );

      // A white CircleBorder Material would be the leftover plate. The only
      // Material allowed here is the transparent one InkWell needs to paint.
      final materials = find
          .descendant(of: icon, matching: find.byType(Material))
          .evaluate()
          .map((e) => (e.widget as Material).type)
          .toList();
      expect(
        materials,
        isNot(contains(MaterialType.canvas)),
        reason: 'no opaque plate behind a header icon',
      );
    }
  });

  testWidgets('the two header icons sit close together', (tester) async {
    await _pumpHome(tester, _HomeGateway());

    final messages = find.byIcon(Icons.chat_bubble_outline_rounded);
    final bell = find.byIcon(Icons.notifications_none_rounded);

    // These are the 40x40 tap boxes, not the 22px glyphs: SizedBox forces
    // tight constraints so the Icon's box is the whole button. The gap between
    // the boxes is the SizedBox(4) in the header row.
    final boxGap = tester.getTopLeft(bell).dx - tester.getTopRight(messages).dx;
    expect(
      boxGap,
      moreOrLessEquals(4, epsilon: 0.1),
      reason: 'the two buttons should be tucked together',
    );

    // ...and the glyphs inside still clear each other, 9px of padding per box.
    expect(tester.widget<Icon>(messages).size, 22);
    expect(tester.widget<Icon>(bell).size, 22);
    expect(
      tester.getSize(messages).width,
      40,
      reason: 'tap target stays comfortable even though the plate is gone',
    );
  });

  testWidgets('the support FAB icon is white on the green button', (
    tester,
  ) async {
    await _pumpHome(tester, _HomeGateway());

    final fab = tester.widget<Icon>(find.byIcon(Icons.support_agent));
    expect(
      fab.color,
      Colors.white,
      reason: 'grey disappeared into the green background',
    );
  });

  testWidgets('an unread badge never blocks the message button', (
    tester,
  ) async {
    // A wide 99+ badge is the worst case for overlapping the glyph.
    await _pumpHome(tester, _HomeGateway()..inbox = [_thread(unread: 250)]);

    expect(find.text('99+'), findsOneWidget);

    // Directional: the badge text lives *inside* an IgnorePointer, so this
    // cannot be satisfied by one of the unrelated IgnorePointers in the tree.
    expect(
      find.descendant(
        of: find.byType(IgnorePointer),
        matching: find.text('99+'),
      ),
      findsOneWidget,
      reason: 'the badge is decoration and must not absorb the tap',
    );

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(MessagesInboxScreen), findsOneWidget);
  });

  testWidgets('no badge when every thread is read', (tester) async {
    await _pumpHome(tester, _HomeGateway()..inbox = [_thread(unread: 0)]);

    expect(find.text('0'), findsNothing);
  });

  testWidgets('the badge totals unread across every thread', (tester) async {
    await _pumpHome(
      tester,
      _HomeGateway()
        ..inbox = [
          _thread(unread: 2),
          _thread(unread: 3, other: 'Maria Santos'),
        ],
    );

    // 2 + 3 unread, not "the first thread's 2".
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('a large unread count is capped at 99+', (tester) async {
    await _pumpHome(tester, _HomeGateway()..inbox = [_thread(unread: 120)]);

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('120'), findsNothing);
  });

  testWidgets('the message button opens the inbox', (tester) async {
    await _pumpHome(tester, _HomeGateway()..inbox = [_thread(unread: 1)]);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MessagesInboxScreen), findsOneWidget);
    expect(
      find.text('React A'),
      findsOneWidget,
      reason: 'the inbox must open on the real thread list',
    );
  });

  testWidgets('the bell opens the notifications screen, not the inbox', (
    tester,
  ) async {
    await _pumpHome(tester, _HomeGateway()..inbox = [_thread(unread: 1)]);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byType(MessagesInboxScreen), findsNothing);
    expect(find.text('Nothing new yet'), findsOneWidget);
  });

  testWidgets('the support FAB uses the customer support mark', (tester) async {
    await _pumpHome(tester, _HomeGateway());

    expect(find.byIcon(Icons.support_agent), findsOneWidget);
    expect(
      find.byIcon(Icons.chat_bubble_outline),
      findsNothing,
      reason: 'the old chat bubble is now the messages button, not support',
    );
  });

  testWidgets(
    'the header copy stays role-agnostic for a seller who also buys',
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
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            gateway: api,
            notificationGateway: _HomeNotifications(),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.text('Messages from buyers'),
        findsNothing,
        reason: 'a farmer can be a buyer in one thread and a seller in another',
      );
    },
  );

  testWidgets('a failed inbox call leaves the header usable with no badge', (
    tester,
  ) async {
    await _pumpHome(tester, _HomeGateway()..inboxError = Exception('offline'));

    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'an unread-count failure must not break the Home screen',
    );
  });

  testWidgets('the bell badge counts unread notifications', (tester) async {
    await _pumpHome(tester, _HomeGateway(), _HomeNotifications()..unread = 3);

    expect(find.text('3'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(IgnorePointer), matching: find.text('3')),
      findsOneWidget,
      reason: 'the bell badge is decoration and must not absorb the tap',
    );
  });

  testWidgets('no bell badge when every notification is read', (tester) async {
    await _pumpHome(tester, _HomeGateway(), _HomeNotifications());

    expect(
      find.text('0'),
      findsNothing,
      reason: 'a read inbox must not paint a badge over the bell',
    );
  });

  testWidgets('the two badges count their own inboxes', (tester) async {
    // Chat has 1 unread thread, notifications have 5 unread rows. If the bell
    // were reusing the messages total, this would show "1" instead of "5".
    await _pumpHome(
      tester,
      _HomeGateway()..inbox = [_thread(unread: 1)],
      _HomeNotifications()..unread = 5,
    );

    expect(find.text('5'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a large notification count is capped at 99+', (tester) async {
    await _pumpHome(tester, _HomeGateway(), _HomeNotifications()..unread = 120);

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('120'), findsNothing);
  });

  testWidgets('a failed notification count leaves the header usable', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      _HomeGateway(),
      _HomeNotifications()..error = Exception('offline'),
    );

    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'a failing unread-count must not break the Home screen',
    );
  });

  testWidgets('the bell badge is refreshed after the inbox is closed', (
    tester,
  ) async {
    final notifications = _HomeNotifications()..unread = 4;
    await _pumpHome(tester, _HomeGateway(), notifications);

    expect(find.text('4'), findsOneWidget);

    // What "Mark all read" in the inbox does to the server count.
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(NotificationsScreen.markAllReadKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    Navigator.of(tester.element(find.byType(NotificationsScreen))).pop();
    await tester.pumpAndSettle();

    expect(
      find.text('4'),
      findsNothing,
      reason: 'the header must recount when the inbox pops',
    );
  });
}
