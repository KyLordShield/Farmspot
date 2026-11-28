import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/services/session_state.dart';
import 'package:farmspot_app/widgets/message_farmer_button.dart';

void main() {
  setUp(() => SessionState.instance.applyUser({'USR_ID': 'BUY001'}));
  testWidgets('hides for own profile and missing farmer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Column(children: [
      MessageFarmerButton(farmerId: 'FMR001', userId: 'BUY001'),
      MessageFarmerButton(farmerId: '', userId: 'OTHER1'),
    ])));
    expect(find.text('Message Farmer'), findsNothing);
  });
  testWidgets('prevents duplicate taps and recovers after an error', (tester) async {
    final pending = Completer<Conversation>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MessageFarmerButton(
      farmerId: 'FMR001', userId: 'SELL01', startConversation: (id) {
        expect(id, 'FMR001'); calls++; return pending.future;
      },
    ))));
    await tester.tap(find.text('Message Farmer')); await tester.pump();
    expect(find.text('Opening...'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(calls, 1);
    pending.completeError(Exception('Farmer unavailable'));
    await tester.pump(); await tester.pump();
    expect(find.text('Farmer unavailable'), findsOneWidget);
    expect(find.text('Message Farmer'), findsOneWidget);
  });
}
