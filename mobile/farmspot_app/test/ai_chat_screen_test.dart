import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/screens/ai_chat_screen.dart';
import 'package:farmspot_app/services/ai_chat_service.dart';
import 'package:farmspot_app/services/auth_service.dart';

/// Stands in for the backend so the chat can be exercised without a server or
/// a provider key.
class _FakeGateway implements AiGateway {
  /// Every history the screen sent, so we can assert on what was forwarded.
  final List<List<AiTurn>> calls = [];

  String reply = 'Ang kamatis, puno na.';
  Object? error;

  /// When set, the call parks here instead of resolving, so a test can observe
  /// the in-flight state. Uses a Completer rather than a delay because the
  /// test clock will not advance a real timer on its own.
  Completer<void>? gate;

  @override
  Future<String> replyTo(List<AiTurn> history) async {
    calls.add(List.of(history));
    await gate?.future;
    if (error != null) throw error!;
    return reply;
  }
}

void main() {
  late _FakeGateway gateway;

  setUp(() {
    // The conversation lives in a process-wide session so it survives the
    // app's pushReplacement tab navigation. Tests must start from empty.
    AiChatSession.instance.clear();
    gateway = _FakeGateway();
  });

  Future<void> pumpChat(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AiChatScreen(gateway: gateway),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester, String question) async {
    await tester.enterText(find.byType(TextField), question);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
  }

  testWidgets('opens on the assistant greeting', (tester) async {
    await pumpChat(tester);

    expect(find.textContaining('FarmSpot ai assist'), findsOneWidget);
    expect(find.text('Via Farmspot'), findsOneWidget);
    // Nothing is sent just by opening the screen.
    expect(gateway.calls, isEmpty);
  });

  group('the context pill does not invent or echo a subject', () {
    // It used to read a fixed "Cabbage Inquiry", so every thread was labelled
    // as a question about one crop. Showing the user's first question instead
    // was worse: it echoed their message back at the top, and a long one
    // overflowed the row and pushed the layout off screen.
    testWidgets('names the assistant, not a crop and not the question',
        (tester) async {
      await pumpChat(tester);

      expect(
        tester.widget<Text>(find.byKey(AiChatScreen.topicPillKey)).data,
        'Assistant',
      );
      expect(find.textContaining('Cabbage'), findsNothing);
    });

    testWidgets('stays a fixed label after the first question', (tester) async {
      await pumpChat(tester);

      await ask(tester, 'How do I add a crop?');
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(AiChatScreen.topicPillKey)).data,
        'Assistant',
      );
      // The question is not duplicated anywhere in the header.
      expect(find.text('How do I add a crop?'), findsOneWidget);
    });

    testWidgets('a very long first question does not overflow the header',
        (tester) async {
      await pumpChat(tester);

      await ask(
        tester,
        'Kumusta po ang tanan nga mga klase sa traditional na pagsusaka sa '
        'kasalukuyan ay climate change pati na rin ang lupa nga naaabot ng '
        'bakal na umaatras na araw-araw bago pa man mag-ulan ng panahon nga '
        'abihon ang mga magsasaka sa buong Pilipinas lalo na sa mga probinsiya',
      );
      await tester.pumpAndSettle();

      // A RenderFlex overflow is what used to break this header.
      expect(tester.takeException(), isNull);
      expect(find.text('Via Farmspot'), findsOneWidget);
    });
  });

  testWidgets('shows the question, the typing dots, then the reply',
      (tester) async {
    gateway.gate = Completer<void>();
    await pumpChat(tester);

    await ask(tester, 'Kumusta ang kamatis?');
    await tester.pump();

    expect(find.text('Kumusta ang kamatis?'), findsOneWidget);
    // Still working: the three-dot indicator stands in for the reply.
    expect(find.text('Ang kamatis, puno na.'), findsNothing);

    gateway.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Ang kamatis, puno na.'), findsOneWidget);
  });

  testWidgets('forwards the question and the conversation so far',
      (tester) async {
    await pumpChat(tester);

    await ask(tester, 'first');
    await tester.pumpAndSettle();
    await ask(tester, 'second');
    await tester.pumpAndSettle();

    expect(gateway.calls.first.map((t) => t.content), ['first']);
    expect(gateway.calls.last.map((t) => t.content),
        ['first', 'Ang kamatis, puno na.', 'second']);
    expect(gateway.calls.last.first.role, 'user');
  });

  testWidgets('clears the input after sending', (tester) async {
    await pumpChat(tester);

    await ask(tester, 'hello there');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('an empty question is not sent', (tester) async {
    await pumpChat(tester);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(gateway.calls, isEmpty);
  });

  testWidgets('a failure shows the message and offers a retry', (tester) async {
    gateway.error = AiException('The assistant is busy right now.');
    await pumpChat(tester);

    await ask(tester, 'kamatis');
    await tester.pumpAndSettle();

    expect(find.text('The assistant is busy right now.'), findsOneWidget);
    expect(find.text('Tap to retry'), findsOneWidget);
  });

  testWidgets('a failed question is pulled back out of the sent history',
      (tester) async {
    gateway.error = AiException('The assistant is having trouble right now.');
    await pumpChat(tester);

    await ask(tester, 'never answered');
    await tester.pumpAndSettle();

    // Otherwise the next request would carry a question with no answer, and
    // the model would try to respond to two things at once.
    expect(AiChatSession.instance.history, isEmpty);
  });

  testWidgets('retrying re-sends the question and clears the error',
      (tester) async {
    gateway.error = AiException('The assistant is busy right now.');
    await pumpChat(tester);

    await ask(tester, 'pechay');
    await tester.pumpAndSettle();
    expect(find.text('Tap to retry'), findsOneWidget);

    gateway.error = null;
    gateway.reply = 'Patuloy ang pagtatanim ng pechay.';
    await tester.tap(find.text('Tap to retry'));
    await tester.pumpAndSettle();

    expect(find.text('temporary trouble'), findsNothing);
    expect(find.text('Patuloy ang pagtatanim ng pechay.'), findsOneWidget);
    // Re-asked, not asked twice.
    expect(gateway.calls.length, 2);
    expect(AiChatSession.instance.history.map((t) => t.content),
        ['pechay', 'Patuloy ang pagtatanim ng pechay.']);
  });

  testWidgets('a second tap cannot send while the assistant is working',
      (tester) async {
    gateway.gate = Completer<void>();
    await pumpChat(tester);

    await ask(tester, 'one');
    await tester.pump();
    // Send is guarded while _typing, so a double tap is not doubled up.
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(gateway.calls.length, 1);

    gateway.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the conversation survives leaving and reopening the screen',
      (tester) async {
    await pumpChat(tester);
    await ask(tester, 'sabi ko na');
    await tester.pumpAndSettle();

    // The app pushes tabs with pushReplacement, so a State-held transcript
    // would be destroyed here. The session outlives the widget.
    await pumpChat(tester);

    expect(find.text('sabi ko na'), findsOneWidget);
    expect(find.text('Ang kamatis, puno na.'), findsOneWidget);
  });

  // ------------------------------------------------ suggested questions

  test('the starter questions cover own data, app help and farming', () {
    // A purely functional list would make the assistant look like a status
    // page, so it has to span all three of its jobs.
    final questions = AiChatScreen.suggestions;

    expect(questions.where((q) => q.contains('my farm status')), isNotEmpty);
    expect(questions.where((q) => q.startsWith('How do I')), isNotEmpty);
    expect(questions.where((q) => q.contains('plant')), isNotEmpty);
  });

  testWidgets('offers starter questions on an empty conversation',
      (tester) async {
    await pumpChat(tester);

    expect(find.text('Try asking'), findsOneWidget);
    // Only the first few chips fit at this width; the scroll test below covers
    // the ones past the fold.
    expect(find.byKey(AiChatScreen.suggestionStripKey), findsOneWidget);
    expect(find.text(AiChatScreen.suggestions.first), findsOneWidget);
  });

  testWidgets('the starter strip scrolls to the later questions', (tester) async {
    await pumpChat(tester);

    final last = AiChatScreen.suggestions.last;
    // Only a couple of chips fit a phone, so the rest have to be reachable by
    // scrolling rather than being laid out off-screen.
    expect(find.text(last), findsNothing);

    await tester.scrollUntilVisible(
      find.text(last),
      150,
      scrollable: find.descendant(
        of: find.byKey(AiChatScreen.suggestionStripKey),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(last), findsOneWidget);
  });

  testWidgets('tapping a starter question asks it', (tester) async {
    await pumpChat(tester);
    final question = AiChatScreen.suggestions.first;

    await tester.tap(find.text(question));
    await tester.pumpAndSettle();

    expect(gateway.calls.last.map((t) => t.content), [question]);
    expect(find.text('Ang kamatis, puno na.'), findsOneWidget);
  });

  testWidgets('the starter questions retire once the user asks something',
      (tester) async {
    await pumpChat(tester);
    expect(find.text('Try asking'), findsOneWidget);

    await ask(tester, 'my own question');
    await tester.pumpAndSettle();

    // They would just crowd the transcript from here on.
    expect(find.text('Try asking'), findsNothing);
    expect(find.text('How do I become a seller?'), findsNothing);
  });

  testWidgets('a failed starter question also retires the chips',
      (tester) async {
    gateway.error = AiException('The assistant is busy right now.');
    await pumpChat(tester);

    await tester.tap(find.text(AiChatScreen.suggestions.first));
    await tester.pumpAndSettle();

    // The question was asked, so the list has served its purpose even though
    // the answer failed.
    expect(find.text('Try asking'), findsNothing);
    expect(find.text('Tap to retry'), findsOneWidget);
  });

  // ------------------------------------------------------- session lifetime

  test('logging out does not leak the transcript to the next user', () async {
    SharedPreferences.setMockInitialValues({});
    AiChatSession.instance.history.addAll(const [
      AiTurn('user', 'Nagtanong ako ng ibang user'),
      AiTurn('assistant', 'Sige, ito ang sagot...'),
    ]);

    // No token is stored, so this never touches the network.
    await AuthService.logout();

    expect(AiChatSession.instance.history, isEmpty);
  });
}

