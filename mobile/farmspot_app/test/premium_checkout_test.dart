import 'package:farmspot_app/legal/legal.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/models/premium_checkout.dart';
import 'package:farmspot_app/services/premium_checkout_service.dart';
import 'package:farmspot_app/screens/premium/premium_checkout_screen.dart';
import 'package:farmspot_app/widgets/lottie_loader.dart';

const pending = PremiumCheckout(
  id: 'order',
  status: 'PENDING',
  url: 'https://checkout.paymongo.com/test',
  amount: 9900,
);
const paid = PremiumCheckout(
  id: 'order',
  status: 'PAID',
  url: 'https://checkout.paymongo.com/test',
  amount: 9900,
  paymentReference: 'pay_test',
  premiumUntil: '2026-11-25T00:00:00Z',
);

class Gateway implements PremiumCheckoutGateway {
  PremiumCheckout result = pending;
  Completer<PremiumCheckout>? waiting;
  int verifies = 0;
  @override
  Future<PremiumCheckout> create() async => pending;
  @override
  Future<PremiumCheckout> verify(String id) async {
    verifies++;
    return waiting?.future ?? result;
  }
}

void main() {
  setUpAll(() async {
    await LegalService.catalog();
  });
  testWidgets(
    'opening checkout does not grant access; pending then verified payment refreshes account',
    (tester) async {
      final gateway = Gateway();
      int refreshed = 0, opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumCheckoutScreen(
            gateway: gateway,
            savePaymentAgreement: () async {},
            openCheckout: (_) async {
              opened++;
              return true;
            },
            refreshAccount: () async {
              refreshed++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue to PayMongo'));
      await tester.tap(find.text('Continue to PayMongo'));
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(
        find.textContaining('Please review and accept the payment terms'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      final policyScroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('legal-reader-scroll')),
          )
          .controller!;
      policyScroll.jumpTo(policyScroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('legal-reader-agree')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue to PayMongo'));
      await tester.tap(find.text('Continue to PayMongo'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(refreshed, 0);
      await tester.ensureVisible(find.text('Check payment'));
      await tester.ensureVisible(find.text('Check payment'));
      await tester.tap(find.text('Check payment'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Payment is not confirmed yet'),
        findsOneWidget,
      );
      expect(refreshed, 0);
      gateway.result = paid;
      await tester.ensureVisible(find.text('Check payment'));
      await tester.ensureVisible(find.text('Check payment'));
      await tester.tap(find.text('Check payment'));
      await tester.pumpAndSettle();
      expect(refreshed, 1);
      expect(find.text('Premium is active'), findsOneWidget);
      expect(find.textContaining('pay_test'), findsOneWidget);
    },
  );
  testWidgets(
    'verification uses branded loader, prevents repeated taps and recovers from failure',
    (tester) async {
      final gateway = Gateway()..waiting = Completer<PremiumCheckout>();
      await tester.pumpWidget(
        MaterialApp(home: PremiumCheckoutScreen(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check payment'));
      await tester.ensureVisible(find.text('Check payment'));
      await tester.tap(find.text('Check payment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FarmLottieLoading), findsOneWidget);
      expect(gateway.verifies, 1);
      gateway.waiting!.completeError(Exception('Please retry.'));
      await tester.pumpAndSettle();
      expect(find.byType(FarmLottieLoading), findsNothing);
      expect(find.text('Please retry.'), findsOneWidget);
      expect(find.text('Premium is active'), findsNothing);
    },
  );
  testWidgets('paid order can retry account refresh without another checkout', (
    tester,
  ) async {
    final gateway = Gateway()..result = paid;
    var allow = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PremiumCheckoutScreen(
          gateway: gateway,
          refreshAccount: () async => allow,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Check payment'));
    await tester.tap(find.text('Check payment'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Payment confirmed. Tap Check payment again'),
      findsOneWidget,
    );
    allow = true;
    await tester.ensureVisible(find.text('Check payment'));
    await tester.tap(find.text('Check payment'));
    await tester.pumpAndSettle();
    expect(find.text('Premium is active'), findsOneWidget);
  });
}
