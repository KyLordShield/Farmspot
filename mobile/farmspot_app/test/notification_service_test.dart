import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/app_notification.dart';
import 'package:farmspot_app/services/notification_service.dart';

/// Plain `test()` (no widget tree) with a [MockClient], so the four endpoints
/// can be verified against the exact JSON the Laravel controller emits without
/// standing up the server.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  });

  Map<String, dynamic> row({
    String id = 'NOT001',
    String type = 'LISTING_EXPIRING_SOON',
    String title = 'Listing expiring soon',
    String body = 'Your Carrot listing expires tomorrow.',
    Object? refId = 'LST0001',
    bool isRead = false,
    String createdAt = '2026-10-02 09:30:00',
  }) {
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'ref_id': refId,
      'is_read': isRead,
      'created_at': createdAt,
    };
  }

  test('fetchPage reads the rows and the pagination envelope', () async {
    late http.Request captured;
    final service = NotificationService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'notifications': [
              row(id: 'NOT002', type: 'LISTING_EXPIRED', isRead: true),
              row(id: 'NOT001'),
            ],
            'unread_count': 1,
            'current_page': 2,
            'last_page': 3,
            'per_page': 20,
            'total': 53,
          }),
          200,
        );
      }),
    );

    final page = await service.fetchPage(2);

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/notifications');
    expect(captured.url.query, 'page=2');
    expect(
      captured.headers['Authorization'],
      'Bearer test-token',
      reason: 'every notification route is behind auth:sanctum',
    );

    expect(page.items, hasLength(2));
    expect(page.items.first.id, 'NOT002');
    expect(page.items.first.isRead, isTrue);
    expect(page.items.last.isRead, isFalse);
    expect(page.items.last.refId, 'LST0001');
    expect(page.items.last.createdAt, isNotNull);
    expect(page.unreadCount, 1);
    expect(page.currentPage, 2);
    expect(page.lastPage, 3);
    expect(page.total, 53);
    expect(page.hasMore, isTrue);
  });

  test('the last page reports no more pages', () async {
    final service = NotificationService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'notifications': [row()],
            'unread_count': 0,
            'current_page': 3,
            'last_page': 3,
            'per_page': 20,
            'total': 53,
          }),
          200,
        ),
      ),
    );

    final page = await service.fetchPage(3);
    expect(page.hasMore, isFalse);
  });

  test('fetchUnreadCount reads only the count endpoint', () async {
    late http.Request captured;
    final service = NotificationService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'count': 7}), 200);
      }),
    );

    expect(await service.fetchUnreadCount(), 7);
    expect(captured.url.path, '/api/notifications/unread-count');
  });

  test('markAsRead PATCHes the one row and returns the server copy', () async {
    late http.Request captured;
    final service = NotificationService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'message': 'Notification marked as read.',
            'notification': row(isRead: true),
          }),
          200,
        );
      }),
    );

    final updated = await service.markAsRead('NOT001');

    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/notifications/NOT001/read');
    expect(updated.isRead, isTrue);
    expect(updated.id, 'NOT001');
  });

  test('markAllAsRead PATCHes once and returns how many changed', () async {
    var calls = 0;
    late http.Request captured;
    final service = NotificationService(
      client: MockClient((request) async {
        calls++;
        captured = request;
        return http.Response(
          jsonEncode({
            'message': 'Notifications marked as read.',
            'marked_read': 12,
            'count': 0,
          }),
          200,
        );
      }),
    );

    expect(await service.markAllAsRead(), 12);
    expect(calls, 1, reason: 'one UPDATE, not a write per visible row');
    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/notifications/read-all');
  });

  test(
    'a 404 surfaces the server message instead of a generic failure',
    () async {
      final service = NotificationService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Notification not found.'}),
            404,
          ),
        ),
      );

      expect(
        () => service.markAsRead('NOT999'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Notification not found.'),
          ),
        ),
      );
    },
  );

  test('an unreachable server becomes a friendly connection error', () async {
    final service = NotificationService(
      client: MockClient((_) async => throw const SocketExceptionStub()),
    );

    expect(
      () => service.fetchPage(1),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Check your connection'),
        ),
      ),
    );
  });

  test('a row with no ref id is not a deep-link target', () {
    expect(AppNotification.fromJson(row(refId: null)).hasTarget, isFalse);
    expect(AppNotification.fromJson(row(refId: '   ')).hasTarget, isFalse);
    expect(AppNotification.fromJson(row()).hasTarget, isTrue);
  });

  test('asRead only flips the flag', () {
    final original = AppNotification.fromJson(row());
    final read = original.asRead();

    expect(read.isRead, isTrue);
    expect(read.id, original.id);
    expect(read.type, original.type);
    expect(read.refId, original.refId);
    expect(
      original.isRead,
      isFalse,
      reason: 'asRead returns a copy, it must not mutate in place',
    );
  });

  test('a missing created_at is tolerated', () {
    expect(AppNotification.fromJson(row(createdAt: '')).createdAt, isNull);
  });
}

/// Stand-in for a dropped socket, so the test does not need dart:io.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
