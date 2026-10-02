import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_notification.dart';
import 'auth_service.dart';

/// One page of the inbox plus the pagination envelope the server echoes back.
///
/// The envelope travels with the rows on purpose: the client must not hardcode
/// the page size, because the server owns it (currently 20) and a hardcoded 20
/// would silently drop rows if that ever changes.
class NotificationPage {
  final List<AppNotification> items;

  /// Total unread across every page, not just this one — the badge needs the
  /// total even when the user is looking at page 3.
  final int unreadCount;

  final int currentPage;
  final int lastPage;
  final int total;

  const NotificationPage({
    required this.items,
    required this.unreadCount,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  bool get hasMore => currentPage < lastPage;
}

/// The notification calls a screen needs. Declared as an interface for the same
/// reason [MessagesGateway] is: widget tests hand a screen a fake instead of
/// standing up a server.
abstract class NotificationsGateway {
  /// One page of the inbox, newest first.
  Future<NotificationPage> fetchPage(int page);

  /// Just the badge number. Separate from [fetchPage] because the home screen
  /// needs it on every open and on every pull-to-refresh, and should not have
  /// to download 20 rows of text to learn whether there is anything to show.
  Future<int> fetchUnreadCount();

  /// Marks one notification read and returns the server's copy of the row.
  Future<AppNotification> markAsRead(String id);

  /// Marks everything read and returns how many rows changed.
  Future<int> markAllAsRead();
}

/// The app's notification inbox, over the FarmSpot Laravel backend.
///
/// Deliberately contains no chat: messages live behind their own endpoint and
/// their own unread badge, and the two must never be merged or the bell becomes
/// unreadable.
class NotificationService implements NotificationsGateway {
  static const String baseUrl = AuthService.baseUrl;

  /// Shared instance, so screens default to the real backend while tests pass
  /// their own implementation or their own [client].
  static final NotificationService instance = NotificationService();

  /// Injectable so the contract can be tested without a server — the same seam
  /// [GeocodingService] uses.
  final http.Client _client;

  NotificationService({http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<NotificationPage> fetchPage(int page) async {
    final body = _data(await _get('/notifications?page=$page'));
    final list = body['notifications'] as List? ?? const [];
    return NotificationPage(
      items: list
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
      unreadCount: (body['unread_count'] as num?)?.toInt() ?? 0,
      // Defaults keep a paginator from looping forever if the server omits them.
      currentPage: (body['current_page'] as num?)?.toInt() ?? page,
      lastPage: (body['last_page'] as num?)?.toInt() ?? 1,
      total: (body['total'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<int> fetchUnreadCount() async {
    final body = _data(await _get('/notifications/unread-count'));
    return (body['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<AppNotification> markAsRead(String id) async {
    final body = _data(await _patch('/notifications/$id/read'));
    return AppNotification.fromJson(
      body['notification'] as Map<String, dynamic>,
    );
  }

  @override
  Future<int> markAllAsRead() async {
    final body = _data(await _patch('/notifications/read-all'));
    return (body['marked_read'] as num?)?.toInt() ?? 0;
  }

  Future<http.Response> _get(String path) async {
    try {
      return await _client.get(
        Uri.parse('$baseUrl$path'),
        headers: await _headers(),
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  /// The two read receipts are PATCHes. Laravel routes a PATCH without a
  /// `_method` override the same way as a real verb, so there is no form
  /// workaround here.
  Future<http.Response> _patch(String path) async {
    try {
      return await _client.patch(
        Uri.parse('$baseUrl$path'),
        headers: await _headers(),
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      // Every route here is behind auth:sanctum.
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Unwraps the body, turning a non-2xx response into the server's own
  /// message so the UI can show something specific instead of "failed".
  static Map<String, dynamic> _data(http.Response response) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('The server sent an unexpected response.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(
      (body['message'] as String?) ?? 'Could not load notifications.',
    );
  }
}
