import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/legal/legal.dart';
import 'package:farmspot_app/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> fixture({bool published = false}) => {
  'version': 'test-v1',
  'published': published,
  'operator_name': published ? 'Test Operator' : null,
  'contact_email': published ? 'test@example.test' : null,
  'retention_policy': published ? 'Test' : null,
  'refund_policy': published ? 'Test' : null,
  'draft_notice': 'Draft for review; not published.',
  'documents': [
    for (final id in ['terms', 'privacy', 'seller', 'verification'])
      {
        'id': id,
        'title': LegalLinks.titles[id],
        'sections': [
          {'heading': 'A short section', 'text': 'Readable policy text.'},
        ],
      },
  ],
};

void main() {
  for (final label in [
    'I agree to the Terms of Service and acknowledge the Privacy Policy.',
    'I consent to ID and permit processing for seller verification.',
    'I agree to the Premium payment terms and acknowledge the Privacy Policy.',
  ]) {
    testWidgets(
      'agreement checkbox stays left of its label without duplicate links: $label',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 640),
                textScaler: TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LegalRegistrationConsent(
                    policies: LegalCatalog(fixture(published: true)),
                    agreementLabel: label,
                    onChanged: (_, value) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.byType(Checkbox)).dx,
          lessThan(tester.getTopLeft(find.text(label)).dx),
        );
        expect(find.byType(LegalLinks), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(LegalReaderDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      },
    );
  }

  testWidgets(
    'verification agreement modal uses the specific document consent',
    (tester) async {
      const label =
          'I consent to ID and permit processing for seller verification.';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LegalRegistrationConsent(
              policies: LegalCatalog(fixture(published: true)),
              documents: const ['verification'],
              agreementLabel: label,
              onChanged: (_, value) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(LegalReaderDialog),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(LegalReaderDialog),
          matching: find.text('Terms of Service'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'long policy requires reaching the end and cancel never checks agreement',
    (tester) async {
      final data = fixture(published: true);
      (data['documents'] as List).first['sections'] = List.generate(
        18,
        (i) => {
          'heading': 'Section $i',
          'text': 'Please read these conditions carefully. ' * 8,
        },
      );
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LegalRegistrationConsent(
              policies: LegalCatalog(data),
              onChanged: (_, value) => accepted = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.byType(LegalReaderDialog), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('legal-reader-agree')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('legal-reader-scroll')),
          )
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('legal-reader-agree')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('legal-reader-agree')));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
    },
  );
  testWidgets('policy modal fits a small phone with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => LegalService.review(context, [
                  'terms',
                ], policies: LegalCatalog(fixture(published: true))),
                child: const Text('Read'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft pages are readable and do not show acceptance controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LegalScreen(
          documentId: 'privacy',
          policies: LegalCatalog(fixture()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Readable policy text.'), findsOneWidget);
    expect(find.textContaining('Draft for review'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });
  testWidgets('registration drafts never require agreement', (tester) async {
    LegalCatalog? loaded;
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LegalRegistrationConsent(
            policies: LegalCatalog(fixture()),
            onChanged: (catalog, value) {
              loaded = catalog;
              accepted = value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loaded!.published, isFalse);
    expect(accepted, isFalse);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Terms of Service'), findsNothing);
    expect(find.text('Privacy Policy'), findsNothing);
  });
  testWidgets(
    'published registration agreement is unchecked until explicitly selected',
    (tester) async {
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LegalRegistrationConsent(
              policies: LegalCatalog(fixture(published: true)),
              onChanged: (_, value) => accepted = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('legal-reader-scroll')),
          )
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('legal-reader-agree')));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(accepted, isFalse);
    },
  );
  test(
    'registration only sends legal fields when explicitly provided',
    () async {
      for (final includeLegal in [false, true]) {
        final client = MockClient((request) async {
          expect(request.bodyFields.containsKey('legal_version'), includeLegal);
          if (includeLegal) expect(request.bodyFields['terms_accepted'], '1');
          return http.Response(
            jsonEncode({
              'message': 'Test validation',
              'errors': {
                'USR_EMAIL': ['Test'],
              },
            }),
            422,
          );
        });
        await AuthService.attemptRegister(
          name: 'Test Person',
          email: 'test@example.test',
          password: 'password123',
          passwordConfirmation: 'password123',
          mobileNumber: '09123456789',
          client: client,
          legalAcceptance: includeLegal
              ? {
                  'legal_version': 'test-v1',
                  'terms_accepted': '1',
                  'privacy_acknowledged': '1',
                }
              : null,
        );
      }
    },
  );
  test('publication requires the missing business policies to be filled', () {
    final incomplete = fixture(published: true)..['contact_email'] = null;
    expect(LegalCatalog(incomplete).published, isFalse);
  });
}
