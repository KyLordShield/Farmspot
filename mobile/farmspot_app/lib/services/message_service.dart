import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/conversation.dart';
import 'auth_service.dart';

/// The messaging calls a screen needs. Declared as an interface so widget tests
/// can hand a screen a fake instead of standing up a server — the same reason
/// FarmSetupLocationScreen takes an injectable geocoding service.
abstract class MessagesGateway {
  /// Starts — or returns the existing — thread with the seller of a listing.
  /// Safe to call every time the "Message Seller" button is tapped.
  Future<Conversation> startConversation(String listingId);

  /// The signed-in user's inbox, newest activity first.
  Future<List<Conversation>> fetchConversations();

  /// Reads a thread. Passing [after] returns only messages newer than that id,
  /// which is what makes polling cheap; the server also marks the thread read,
  /// so opening a chat is what clears its unread badge.
  Future<List<ChatMessage>> fetchMessages(String conversationId, {String? after});

  /// Posts a message and returns the stored row, so the bubble the user just
  /// typed renders from the server's copy (real id and timestamp) rather than a
  /// local guess.
  Future<ChatMessage> sendMessage(String conversationId, String content);
}

/// In-app buyer <-> seller messaging over the app's own Laravel backend.
///
/// Delivery is plain REST with polling: the chat screen re-reads the thread
/// every few seconds while it is open, asking only for messages newer than the
/// last one it holds. No WebSocket server, no second process to keep alive.
class MessageService implements MessagesGateway {
  static const String baseUrl = AuthService.baseUrl;

  /// Shared instance, so screens can default to the real backend while tests
  /// pass their own implementation.
  static final MessageService instance = MessageService();

  @override
  Future<Conversation> startConversation(String listingId) async {
    final response = await _post('/conversations', {'LST_ID': listingId});
    return Conversation.fromJson(
        _data(response)['conversation'] as Map<String, dynamic>);
  }

  @override
  Future<List<Conversation>> fetchConversations() async {
    final response = await _get('/conversations');
    final list = _data(response)['conversations'] as List? ?? const [];
    return list
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId,
      {String? after}) async {
    final query = after == null || after.isEmpty ? '' : '?after=$after';
    final response = await _get('/conversations/$conversationId/messages$query');
    final list = _data(response)['messages'] as List? ?? const [];
    return list
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ChatMessage> sendMessage(String conversationId, String content) async {
    final response = await _post('/conversations/$conversationId/messages', {
      'content': content,
    });
    return ChatMessage.fromJson(
        _data(response)['message'] as Map<String, dynamic>);
  }

  Future<http.Response> _get(String path) async {
    try {
      return await http.get(
        Uri.parse('$baseUrl$path'),
        headers: await _headers(),
      );
    } catch (_) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await http.post(
        Uri.parse('$baseUrl$path'),
        headers: await _headers(),
        body: jsonEncode(body),
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

    // A 422 carries per-field errors; surface the first one as the message.
    final errors = body['errors'] as Map?;
    if (errors != null && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) {
        throw Exception(first.first.toString());
      }
    }
    throw Exception((body['message'] as String?) ?? 'Could not load messages.');
  }
}
