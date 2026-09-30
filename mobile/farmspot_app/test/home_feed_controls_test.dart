import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/screens/home_screen.dart';
import 'package:farmspot_app/services/message_service.dart';
import 'package:farmspot_app/widgets/home_filter_sheet.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

/// Stands in for the backend so the Home feed can be pumped without a server.
/// Only the inbox call is used by Home.
class _HomeGateway implements MessagesGateway {
  @override
  Future<List<Conversation>> fetchConversations() async => [];

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

/// The controls that were removed from the home feed once the Filter button
/// took over their job, plus the heading that now has to report what is really
/// being shown.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(gateway: _HomeGateway())),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('controls replaced by the Filter button', () {
    testWidgets('the see all link is gone', (tester) async {
      await pumpHome(tester);

      expect(find.text('see all'), findsNothing);
      expect(
        find.byIcon(Icons.arrow_forward),
        findsNothing,
        reason: 'the arrow only existed beside the see all link',
      );
    });

    testWidgets('the seller active-listing banner is gone', (tester) async {
      await pumpHome(tester);

      // Both the counted wording and the fallback. The banner was seller-only,
      // so a buyer session would never have shown it either way.
      expect(find.textContaining('active listing'), findsNothing);
      expect(find.textContaining('You are a seller'), findsNothing);
    });

    testWidgets('the category chip row is gone', (tester) async {
      await pumpHome(tester);

      // The chips duplicated the Filter sheet's category group, and two
      // controls for one setting is how they end up disagreeing.
      expect(find.text('All'), findsNothing);
      expect(find.byType(CategoryChip), findsNothing);
    });

    testWidgets('the Filter button is the only way in', (tester) async {
      await pumpHome(tester);

      expect(find.byKey(HomeFilterButton.buttonKey), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
    });
  });

  group('the feed heading reports what is really applied', () {
    testWidgets('reads Available now when nothing is filtered', (tester) async {
      await pumpHome(tester);

      expect(find.text('Available now'), findsOneWidget);
    });

    testWidgets('stays put on a narrow phone', (tester) async {
      // 320pt is the width where the heading, the Filter button and the see all
      // link used to compete for one row. Removing the link is what this guards.
      // Text scale is left at the default on purpose: at 2x the bottom nav
      // overflows on its own, which would drown out anything about this row.
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpHome(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Available now'), findsOneWidget);
      expect(find.byKey(HomeFilterButton.buttonKey), findsOneWidget);
    });
  });
}
