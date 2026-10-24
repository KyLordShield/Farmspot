import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/models/home_feed_page.dart';
import 'package:farmspot_app/models/home_filters.dart';
import 'package:farmspot_app/premium/premium_state.dart';
import 'package:farmspot_app/screens/home_screen.dart';
import 'package:farmspot_app/screens/profile_screen.dart';
import 'package:farmspot_app/screens/premium/premium_upgrade_screen.dart';
import 'package:farmspot_app/services/home_feed_gateway.dart';
import 'package:farmspot_app/services/message_service.dart';
import 'package:farmspot_app/services/session_state.dart';
import 'package:farmspot_app/widgets/premium_widgets.dart';

Map<String, dynamic> account(
  String id, {
  bool premium = false,
  bool seller = false,
}) => {
  'USR_ID': id,
  'USR_IS_SELLER': seller ? 1 : 0,
  'USR_IS_PREMIUM': premium,
  'USR_PREMIUM_EXPIRES_AT': premium
      ? DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String()
      : null,
};

class _NoMessages implements MessagesGateway {
  @override
  Future<List<Conversation>> fetchConversations() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WaitingFeed implements HomeFeedGateway {
  @override
  Future<HomeFeedPage> fetchFeedPage({
    required int page,
    required int perPage,
    String? search,
    String? category,
    String? availability,
    HomeSortMode sort = HomeSortMode.latest,
    bool personalized = true,
  }) => Completer<HomeFeedPage>().future;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SessionState.instance.debugSetUser(null);
  });
  tearDown(() {
    SessionState.instance.debugSetUser(null);
  });

  test(
    'premium is restored from the account cache and cleared on sign out',
    () async {
      SharedPreferences.setMockInitialValues({
        SessionState.userPrefsKey: jsonEncode(account('A', premium: true)),
      });
      await SessionState.instance.init();
      expect(isPremium.value, isTrue);
      SessionState.instance.clear();
      expect(isPremium.value, isFalse);
      expect(premiumExpiresAt, isNull);
    },
  );

  test('unchanged server account repairs a stale premium notifier', () {
    final user = account('A', premium: true);
    SessionState.instance.applyUser(user);
    isPremium.value = false;
    SessionState.instance.applyUser(user);
    expect(isPremium.value, isTrue);
  });

  testWidgets('active subscribers see plan details without an upgrade offer', (
    tester,
  ) async {
    SessionState.instance.applyUser(account('A', premium: true));
    await tester.pumpWidget(const MaterialApp(home: PremiumUpgradeScreen()));
    expect(find.text('Your subscription'), findsOneWidget);
    expect(find.text('Premium is active'), findsOneWidget);
    expect(find.text('Simulate purchase'), findsNothing);
    expect(find.byType(PremiumBadge), findsNothing);
    SessionState.instance.clear();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('subscriber Profile removes upgrade prompts and locked tags', (
    tester,
  ) async {
    final user = account('A', premium: true);
    SharedPreferences.setMockInitialValues({
      SessionState.userPrefsKey: jsonEncode(user),
    });
    SessionState.instance.applyUser(user);
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pump();
    expect(find.textContaining('Subscription active'), findsOneWidget);
    expect(find.text('See Premium plan'), findsNothing);
    expect(find.byType(PremiumBadge), findsNothing);
    SessionState.instance.clear();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'scheduled checks keep a monthly plan active before its end date',
    (tester) async {
      SessionState.instance.applyUser(account('A', premium: true));
      await tester.pump(const Duration(days: 1));
      expect(isPremium.value, isTrue);
      SessionState.instance.clear();
    },
  );

  test('switching to another account cannot inherit premium', () {
    SessionState.instance.applyUser(account('A', premium: true));
    homeAlertDismissed.value = true;
    SessionState.instance.applyUser(account('B'));
    expect(isPremium.value, isFalse);
    expect(homeAlertDismissed.value, isFalse);
  });

  test('an expired server entitlement is never shown as active', () {
    SessionState.instance.applyUser({
      ...account('A', premium: true),
      'USR_PREMIUM_EXPIRES_AT': DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toUtc()
          .toIso8601String(),
    });
    expect(isPremium.value, isFalse);
  });

  testWidgets(
    'Home tools are hidden for a free seller and appear after activation',
    (tester) async {
      SessionState.instance.applyUser(account('A', seller: true));
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(gateway: _NoMessages(), feedGateway: _WaitingFeed()),
        ),
      );
      await tester.pump();
      expect(find.byType(BusinessToolsQuickCard), findsNothing);
      SessionState.instance.applyUser(
        account('A', seller: true, premium: true),
      );
      await tester.pump();
      expect(find.byType(BusinessToolsQuickCard), findsOneWidget);
      SessionState.instance.clear();
      await tester.pump();
      expect(find.byType(BusinessToolsQuickCard), findsNothing);
      SessionState.instance.clear();
      SessionState.instance.clear();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
