import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/models/app_notification.dart';
import 'package:farmspot_app/screens/notifications_screen.dart';
import 'package:farmspot_app/services/notification_service.dart';

/// Stands in for the backend so the inbox can be exercised without a server.
/// Records what the screen asked for, which is how the mark-read and paging
/// tests assert the calls actually happened rather than just that the UI moved.
class _FakeNotifications implements NotificationsGateway {
  final Map<int, List<AppNotification>> pages = {};
  final List<String> markedRead = [];
  final List<int> requestedPages = [];

  int unread = 0;
  int markAllCalls = 0;
  Object? error;
  Object? markAllError;

  void addPage(int page, List<AppNotification> rows) {
    pages[page] = rows;
  }

  @override
  Future<NotificationPage> fetchPage(int page) async {
    requestedPages.add(page);
    if (error != null) throw error!;
    final rows = pages[page] ?? const [];
    return NotificationPage(
      items: rows,
      unreadCount: unread,
      currentPage: page,
      lastPage: pages.keys.isEmpty
          ? 1
          : pages.keys.reduce((a, b) => a > b ? a : b),
      total: pages.values.fold(0, (sum, rows) => sum + rows.length),
    );
  }

  @override
  Future<int> fetchUnreadCount() async {
    if (error != null) throw error!;
    return unread;
  }

  @override
  Future<AppNotification> markAsRead(String id) async {
    markedRead.add(id);
    return AppNotification.fromJson(_json(id: id, isRead: true));
  }

  @override
  Future<int> markAllAsRead() async {
    markAllCalls++;
    if (markAllError != null) throw markAllError!;
    unread = 0;
    return 0;
  }
}

Map<String, dynamic> _json({
  String id = 'NOT001',
  String type = 'LISTING_EXPIRING_SOON',
  String title = 'Listing expiring soon',
  String body = 'Your Carrot listing expires tomorrow.',
  Object? refId = 'LST0001',
  bool isRead = false,
}) {
  return {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'ref_id': refId,
    'is_read': isRead,
    'created_at': DateTime.now().toIso8601String(),
  };
}

AppNotification _row({
  String id = 'NOT001',
  String type = 'LISTING_EXPIRING_SOON',
  String title = 'Listing expiring soon',
  String body = 'Your Carrot listing expires tomorrow.',
  bool isRead = false,
  Object? refId = 'LST0001',
}) {
  return AppNotification.fromJson(
    _json(
      id: id,
      type: type,
      title: title,
      body: body,
      isRead: isRead,
      refId: refId,
    ),
  );
}

Future<void> _pumpInbox(WidgetTester tester, _FakeNotifications api) async {
  await tester.pumpWidget(MaterialApp(home: NotificationsScreen(gateway: api)));
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('an empty inbox renders the honest empty state', (tester) async {
    await _pumpInbox(tester, _FakeNotifications());

    expect(find.text('Nothing new yet'), findsOneWidget);
    expect(
      find.byKey(NotificationsScreen.markAllReadKey),
      findsNothing,
      reason: 'there is nothing to clear on an empty inbox',
    );
  });

  testWidgets('rows render the server title and body', (tester) async {
    final api = _FakeNotifications()
      ..addPage(1, [
        _row(id: 'NOT001', title: 'Carrot expires tomorrow'),
        _row(
          id: 'NOT002',
          type: 'REPORT_UPDATE',
          title: 'Report answered',
          body: 'A moderator replied to your report.',
          refId: null,
        ),
      ])
      ..unread = 2;

    await _pumpInbox(tester, api);

    expect(find.text('Carrot expires tomorrow'), findsOneWidget);
    expect(find.text('Report answered'), findsOneWidget);
    expect(find.text('A moderator replied to your report.'), findsOneWidget);
  });

  testWidgets('no chat wording leaks into the inbox copy', (tester) async {
    await _pumpInbox(tester, _FakeNotifications());

    // Messages have their own inbox and badge; a chat promise here would send
    // users to a bell that never fills with messages.
    expect(find.textContaining('Replies from buyers'), findsNothing);
    expect(find.textContaining('message'), findsNothing);
  });

  testWidgets('tapping an unread row marks it read', (tester) async {
    final api = _FakeNotifications()
      ..addPage(1, [
        _row(id: 'NOT001', title: 'Carrot expires tomorrow'),
        _row(id: 'NOT002', title: 'Already read', isRead: true),
      ])
      ..unread = 1;

    await _pumpInbox(tester, api);
    expect(
      find.byKey(NotificationsScreen.unreadDotKey),
      findsOneWidget,
      reason: 'only the unread row carries the dot',
    );

    await tester.tap(find.text('Carrot expires tomorrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.markedRead, ['NOT001']);
    expect(find.byKey(NotificationsScreen.unreadDotKey), findsNothing);
  });

  testWidgets('an already read row is not re-sent to the server', (
    tester,
  ) async {
    final api = _FakeNotifications()
      ..addPage(1, [_row(id: 'NOT002', title: 'Already read', isRead: true)]);

    await _pumpInbox(tester, api);
    await tester.tap(find.text('Already read'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.markedRead, isEmpty);
  });

  testWidgets('a row with no destination still counts as read', (tester) async {
    // REPORT_UPDATE has no screen to open yet, so the tap must still clear the
    // badge rather than leave it stuck forever.
    final api = _FakeNotifications()
      ..addPage(1, [
        _row(
          id: 'NOT009',
          type: 'REPORT_UPDATE',
          title: 'Report answered',
          refId: 'RPT001',
        ),
      ])
      ..unread = 1;

    await _pumpInbox(tester, api);
    await tester.tap(find.text('Report answered'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.markedRead, ['NOT009']);
    expect(
      find.byType(NotificationsScreen),
      findsOneWidget,
      reason: 'nothing to navigate to, so the inbox stays open',
    );
  });

  testWidgets('a listing row reports a listing that cannot be loaded', (
    tester,
  ) async {
    final api = _FakeNotifications()
      ..addPage(1, [_row(title: 'Carrot expires tomorrow')])
      ..unread = 1;

    await _pumpInbox(tester, api);
    await tester.tap(find.text('Carrot expires tomorrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The backend is not reachable from a widget test, which is exactly the
    // "listing is gone" case: the tap reports it instead of throwing.
    expect(api.markedRead, ['NOT001']);
    expect(find.text('That listing is no longer available.'), findsOneWidget);
  });

  testWidgets('mark all read clears every row and the action', (tester) async {
    final api = _FakeNotifications()
      ..addPage(1, [
        _row(id: 'NOT001', title: 'One'),
        _row(id: 'NOT002', title: 'Two'),
      ])
      ..unread = 2;

    await _pumpInbox(tester, api);
    expect(find.byKey(NotificationsScreen.unreadDotKey), findsNWidgets(2));

    await tester.tap(find.byKey(NotificationsScreen.markAllReadKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.markAllCalls, 1);
    expect(find.byKey(NotificationsScreen.unreadDotKey), findsNothing);
    expect(find.byKey(NotificationsScreen.markAllReadKey), findsNothing);
  });

  testWidgets('a failed mark-all puts the unread rows back', (tester) async {
    final api = _FakeNotifications()
      ..addPage(1, [_row(id: 'NOT001', title: 'One')])
      ..unread = 1
      ..markAllError = Exception('offline');

    await _pumpInbox(tester, api);
    await tester.tap(find.byKey(NotificationsScreen.markAllReadKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(NotificationsScreen.unreadDotKey),
      findsOneWidget,
      reason: 'the server still disagrees, so the row must stay unread',
    );
    expect(find.text('Could not mark notifications as read.'), findsOneWidget);
  });

  testWidgets('scrolling near the bottom fetches the next page', (
    tester,
  ) async {
    final api = _FakeNotifications()
      ..addPage(1, [
        for (var i = 1; i <= 12; i++)
          _row(id: 'NOT${i.toString().padLeft(3, '0')}', title: 'Row $i'),
      ])
      ..addPage(2, [
        for (var i = 13; i <= 15; i++)
          _row(id: 'NOT${i.toString().padLeft(3, '0')}', title: 'Row $i'),
      ])
      ..unread = 3;

    await _pumpInbox(tester, api);
    expect(find.text('Row 1'), findsOneWidget);
    expect(api.requestedPages, [1]);

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.requestedPages, contains(2));

    // Page two lands below the old scroll extent, so the viewport has to travel
    // again to reach its last row.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Row 15'),
      findsOneWidget,
      reason: 'the last row of page two must be reachable',
    );
  });

  testWidgets('a failed first page offers a retry', (tester) async {
    final api = _FakeNotifications()..error = Exception('offline');

    await _pumpInbox(tester, api);

    expect(find.text("Couldn't load notifications"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    api.error = null;
    api.addPage(1, [_row(title: 'Back online')]);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Back online'), findsOneWidget);
  });
}
