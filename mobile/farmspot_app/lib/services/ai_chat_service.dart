import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// One turn in the assistant conversation.
class AiTurn {
  const AiTurn(this.role, this.content);

  /// 'user' or 'assistant'.
  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Any failure the user is meant to read.
///
/// A dedicated type because the default `Exception` stringifies as
/// `Exception: <message>`, and interpolating one straight into a chat bubble
/// would show the user that prefix. [toString] returns the message alone.
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the chat screen needs from the assistant. Declared as an interface so
/// widget tests can hand the screen a fake instead of calling Groq — the same
/// reason the messaging screen talks to a MessagesGateway.
abstract class AiGateway {
  /// Sends the conversation and returns the assistant's reply.
  Future<String> replyTo(List<AiTurn> history);
}

/// Talks to the app's own Laravel endpoint, which holds the provider key.
///
/// The app never calls Groq directly. That keeps the key server-side and lets
/// the server enforce the token limits the free tier imposes.
class AiChatService implements AiGateway {
  static const String baseUrl = AuthService.baseUrl;

  static final AiChatService instance = AiChatService();

  /// Matches the server's own window, so the client never sends a history the
  /// backend would trim anyway. Eight turns is four exchanges — enough to
  /// hold the thread, small enough to stay well inside the free daily budget.
  static const int historyWindow = 8;

  /// A little longer than the server's 30s provider timeout, so the server's
  /// own error message wins the race instead of a bare client timeout.
  static const Duration _timeout = Duration(seconds: 35);

  @override
  Future<String> replyTo(List<AiTurn> history) async {
    final window = history.length <= historyWindow
        ? history
        : history.sublist(history.length - historyWindow);

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/ai/chat'),
            headers: await _headers(),
            body: jsonEncode({
              'messages': window.map((turn) => turn.toJson()).toList(),
            }),
          )
          .timeout(_timeout);
      return _reply(response);
    } on TimeoutException {
      throw const AiException(
          'The assistant took too long to answer. Try again.');
    } catch (_) {
      throw const AiException(
          'Could not reach the server. Check your connection.');
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

  /// Surfaces the server's own message. It already distinguishes a throttled
  /// provider from a missing key, so the user sees something specific instead
  /// of a generic failure.
  String _reply(http.Response response) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AiException('The server sent an unexpected response.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final reply = body['reply'] as String?;
      if (reply == null || reply.trim().isEmpty) {
        throw const AiException('The assistant did not return an answer.');
      }
      return reply;
    }

    throw AiException((body['message'] as String?) ??
        'The assistant is unavailable right now.');
  }
}

/// The live conversation, held in memory only.
///
/// Kept outside the screen's State on purpose: the app pushes tabs with
/// pushReplacement, so a State-held list would be destroyed every time the
/// user taps a nav tab and the thread would vanish mid-conversation. Living
/// here means the chat survives navigation but is still gone once the app
/// closes — no history is ever written to disk or the database.
class AiChatSession {
  static final AiChatSession instance = AiChatSession();

  final List<AiTurn> history = [];

  void clear() => history.clear();
}
