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

/// One navigation button the server attached to a reply.
///
/// The server decides which screen ids exist; [screen] is never a route or a
/// URL, just a stable name the app maps to a known page. Unknown names are
/// dropped by the screen, so an old or over-eager server cannot push a blank
/// route into the navigator.
class AiAction {
  const AiAction({
    required this.id,
    required this.label,
    required this.screen,
    this.params = const {},
  });

  final String id;
  final String label;
  final String screen;
  final Map<String, dynamic> params;

  /// The search term for a `search_crop` action, if one was sent.
  String? get query {
    final value = params['query'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Returns null for anything the UI cannot render, so one malformed entry
  /// cannot take the whole reply down with it.
  static AiAction? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final rawId = raw['id'];
    final rawLabel = raw['label'];
    final rawScreen = raw['screen'];
    final id = rawId is String ? rawId.trim() : '';
    final label = rawLabel is String ? rawLabel.trim() : '';
    final screen = rawScreen is String ? rawScreen.trim() : '';
    if (id.isEmpty || label.isEmpty || screen.isEmpty) return null;

    final params = <String, dynamic>{};
    final rawParams = raw['params'];
    if (rawParams is Map) {
      rawParams.forEach((key, value) {
        if (key is String) params[key] = value;
      });
    }

    return AiAction(id: id, label: label, screen: screen, params: params);
  }
}

/// A reply and the buttons that belong under it.
class AiReply {
  const AiReply({required this.text, this.actions = const []});

  final String text;
  final List<AiAction> actions;
}

/// What the chat screen needs from the assistant. Declared as an interface so
/// widget tests can hand the screen a fake instead of calling Groq — the same
/// reason the messaging screen talks to a MessagesGateway.
abstract class AiGateway {
  /// Sends the conversation and returns the assistant's reply.
  Future<String> replyTo(List<AiTurn> history);

  /// Like [replyTo], but also carries the server's navigation buttons.
  ///
  /// The default keeps older fakes working: a gateway that only knows how to
  /// return text simply has no actions.
  Future<AiReply> replyWithActions(List<AiTurn> history) async =>
      AiReply(text: await replyTo(history));
}

/// Removes markdown markers from an assistant reply.
///
/// The system prompt already forbids markdown, because a chat bubble renders
/// plain text. This is the backstop for when the model ignores that anyway:
/// without it a stray "**Add Crop**" is shown to the user with the asterisks
/// still on screen, which reads as a bug in the app rather than in the answer.
///
/// Deliberately narrow. It removes emphasis, code, heading and link syntax and
/// leaves the words and the line structure alone, so numbered steps and plain
/// dashes survive. A lone asterisk with no partner is left untouched, because
/// stripping it would mangle ordinary text that happens to contain one.
String stripMarkdown(String text) {
  var out = text;

  // [label](url) -> label. Done before the emphasis rules so the URL's own
  // asterisks and underscores cannot be mistaken for emphasis.
  out = out.replaceAllMapped(
    RegExp(r'\[([^\]\n]*)\]\(([^)\n]*)\)'),
    (m) => m.group(1) ?? '',
  );

  // Fenced and inline code, with an unterminated fence caught by [\s\S]*?.
  // replaceAllMapped rather than replaceAll: a string replacement does not
  // expand $1, it writes the literal characters.
  out = out.replaceAllMapped(
    RegExp(r'```[a-zA-Z0-9]*\n?([\s\S]*?)\n?```'),
    (m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(
    RegExp(r'`([^`\n]*)`'),
    (m) => m.group(1) ?? '',
  );

  // Headings: "### Title" -> "Title", keeping the line break.
  out = out.replaceAll(RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true), '');

  // Emphasis. The pair has to close on the same line, and a lone "*" or "_"
  // is left alone, so "5 * 3" and "snake_case_name" survive untouched.
  out = out.replaceAllMapped(
    RegExp(r'\*\*([^*\n]+)\*\*'),
    (m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(
    RegExp(r'__([^_\n]+)__'),
    (m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(
    RegExp(r'(?<![\w*])\*([^*\n]+)\*(?![\w*])'),
    (m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(
    RegExp(r'(?<![\w_])_([^_\n]+)_(?![\w_])'),
    (m) => m.group(1) ?? '',
  );

  // A bullet or horizontal rule that is now the first thing on its line reads
  // as debris, since the bubble has no margin to hang a bullet on.
  out = out.replaceAll(RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true), '');

  return out
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      // A paragraph break is kept, but a fence that was lifted out of the
      // middle of a reply can leave two of them back to back.
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Talks to the app's own Laravel endpoint, which holds the provider key.
///
/// The app never calls Groq directly. That keeps the key server-side and lets
/// the server enforce the token limits the free tier imposes.
class AiChatService implements AiGateway {
  static final String baseUrl = AuthService.baseUrl;

  static final AiChatService instance = AiChatService();

  /// Matches the server's own window, so the client never sends a history the
  /// backend would trim anyway. Eight turns is four exchanges — enough to
  /// hold the thread, small enough to stay well inside the free daily budget.
  static const int historyWindow = 8;

  /// A little longer than the server's 30s provider timeout, so the server's
  /// own error message wins the race instead of a bare client timeout.
  static const Duration _timeout = Duration(seconds: 35);

  @override
  Future<String> replyTo(List<AiTurn> history) async =>
      (await replyWithActions(history)).text;

  @override
  Future<AiReply> replyWithActions(List<AiTurn> history) async {
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
  AiReply _reply(http.Response response) {
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
      // Stripped here rather than in the bubble so a caller that reads the
      // reply for anything else sees the same clean text the user does.
      final clean = stripMarkdown(reply);

      final actions = <AiAction>[];
      final rawActions = body['actions'];
      if (rawActions is List) {
        for (final raw in rawActions) {
          final action = AiAction.fromJson(raw);
          if (action != null) actions.add(action);
        }
      }

      return AiReply(
        text: clean.isEmpty ? reply.trim() : clean,
        actions: List.unmodifiable(actions),
      );
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
