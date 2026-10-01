import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/models/report.dart';
import 'package:farmspot_app/screens/farm_profile_screen.dart';
import 'package:farmspot_app/screens/in_app_messages_screen.dart';
import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/services/message_service.dart';
import 'package:farmspot_app/services/report_service.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';
import 'package:farmspot_app/widgets/report_sheet.dart';

// ------------------------------------------------------------------ fixtures

/// Recording stand-in for the report endpoint. Every test asserts on [drafts],
/// which is the only way to prove the right *target* was reported — the sheet
/// looks the same whichever one you pick.
class FakeReportsGateway implements ReportsGateway {
  final List<ReportDraft> drafts = [];
  String? error;
  bool duplicate = false;

  @override
  Future<ReportReceipt> submit(ReportDraft draft) async {
    if (error != null) throw Exception(error!);
    drafts.add(draft);
    return ReportReceipt(
      id: 'RPT${drafts.length}',
      status: 'New',
      createdAt: DateTime.now(),
      duplicate: duplicate,
    );
  }
}

class _Messages implements MessagesGateway {
  final List<ChatMessage> stored = [];

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId,
      {String? after}) async =>
      List.of(stored);

  @override
  Future<List<Conversation>> fetchConversations() async => [];

  @override
  Future<ChatMessage> sendMessage(String conversationId, String content) async {
    final saved = ChatMessage(
      id: 'MSGSENT',
      conversationId: conversationId,
      senderId: 'USR0001',
      content: content,
      isMine: true,
      isRead: false,
      createdAt: DateTime.now(),
    );
    stored.add(saved);
    return saved;
  }

  @override
  Future<Conversation> startConversation(String listingId) async =>
      throw UnimplementedError();
}

Map<String, dynamic> conversationJson({
  String role = 'BUYER',
  String otherId = 'USR0002',
  String? otherName = 'React A',
  String? sellerFarmerId = 'FMR0001',
}) {
  return {
    'id': 'CNV0001',
    'listing_id': 'LST0001',
    'seller_farmer_id': sellerFarmerId,
    'my_role': role,
    'unread_count': 0,
    'farm': {'id': 'FRM0001', 'name': 'React A Farm', 'barangay': 'Sudlon II'},
    'other_party': {'id': otherId, 'name': otherName, 'photo': null},
    'listing': {
      'id': 'LST0001',
      'crop_icon': 'carrot',
      'image': null,
      'category': {'id': 'CAT0001', 'name': 'Vegetables'},
      'farm': {'id': 'FRM0001', 'name': 'React A Farm', 'barangay': 'Sudlon II'},
    },
  };
}

ChatMessage aMessage({
  String id = 'MSG0001',
  String content = 'send payment to this gcash number',
  bool isMine = false,
  int minutesAgo = 1,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'CNV0001',
    senderId: isMine ? 'USR0001' : 'USR0002',
    content: content,
    isMine: isMine,
    isRead: isMine,
    createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
  );
}

CropListing aListing({String? listingId = 'LST0001'}) {
  return CropListing(
    cropName: 'carrot',
    farmName: 'React A Farm',
    listingId: listingId,
    farmId: 'FRM0001',
    farmerId: 'FMR0001',
  );
}

FarmProfileData aProfile({String? farmerId = 'FMR0001'}) {
  return FarmProfileData.fromJson({
    'farm': {
      'id': 'FRM0001',
      'name': 'React A Farm',
      'barangay': 'Sudlon II',
      'photos': <String>[],
    },
    'owner': {
      'farmer_id': farmerId,
      'user_id': 'USR0002',
      'name': 'React A',
    },
    'listings': <dynamic>[],
  });
}

// ------------------------------------------------------------------- helpers

/// Give the test a phone-sized surface instead of the 800x600 default.
///
/// The default is too short for two real things: the report links sit below the
/// fold on all three screens, and the sheet's reason list scrolls. Sizing to a
/// phone means these tests exercise the layout a user actually gets rather than
/// a stretched window where nothing needs to scroll.
void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// The report endpoints sit behind `auth:sanctum`, so a token has to exist
/// before the sheet tries to submit.
void _signIn() =>
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});

/// The Scrollable inside the sheet's body list.
///
/// The key sits on the ListView, but scrolling needs the Scrollable it builds,
/// and scoping to descendants keeps it from grabbing one of the pages behind.
/// `.first` matters: a TextField contains a Scrollable of its own for its text,
/// so once the details field is on screen the list has more than one — and the
/// list's is the outermost, hence first in tree order.
Finder _sheetScrollable() => find
    .descendant(
      of: find.byKey(ReportSheet.bodyListKey),
      matching: find.byType(Scrollable),
    )
    .first;

/// Tap a reason, scrolling it into view first.
///
/// Scrolling rather than enlarging the window because the list genuinely does
/// scroll on a phone: eight reasons plus a details field do not fit on one
/// screen, and that is correct behaviour to be testing against.
///
/// The tap goes through the InkWell's own onTap rather than a coordinate tap.
/// The last reachable option can come to rest under the "Send report" footer,
/// which sits outside the scrolling list — a coordinate tap there would hit the
/// button and quietly test the wrong thing.
Future<void> _tapReason(WidgetTester tester, String code) async {
  final option = find.byKey(ReportSheet.reasonOptionKey(code));
  await tester.scrollUntilVisible(option, 100, scrollable: _sheetScrollable());
  await tester.pump();
  tester.widget<InkWell>(option).onTap!();
  await tester.pump();
}

/// Bring the details field into view before typing into it.
Future<void> _revealDetails(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(ReportSheet.detailsFieldKey),
    120,
    scrollable: _sheetScrollable(),
  );
  await tester.pump();
}

/// Advance a fixed number of frames instead of `pumpAndSettle`.
///
/// The chat screen re-polls every few seconds while it is open, so
/// `pumpAndSettle` never reaches a quiet frame there and just times out. A
/// bounded run is enough for a sheet transition and its futures to resolve.
Future<void> _settleModal(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pick a reason, type details, submit, and let the sheet close.
Future<void> _fileReport(
  WidgetTester tester, {
  required String reasonCode,
  String details = '',
}) async {
  await _tapReason(tester, reasonCode);
  if (details.isNotEmpty) {
    await _revealDetails(tester);
    await tester.enterText(find.byKey(ReportSheet.detailsFieldKey), details);
    await tester.pump();
  }
  // The submit row lives outside the scroll view, so it is always reachable.
  await tester.tap(find.byKey(ReportSheet.submitButtonKey));
  await _settleModal(tester);
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  CropListing? listing,
  FakeReportsGateway? reports,
}) async {
  _signIn();
  _usePhone(tester);
  await tester.pumpWidget(MaterialApp(
    home: ProductDetailScreen(
      listing: listing ?? aListing(),
      gateway: _Messages(),
      reportsGateway: reports ?? FakeReportsGateway(),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _Messages api,
  required FakeReportsGateway reports,
  Conversation? conversation,
}) async {
  _signIn();
  _usePhone(tester);
  await tester.pumpWidget(MaterialApp(
    home: InAppMessagesScreen(
      conversation: conversation ?? Conversation.fromJson(conversationJson()),
      gateway: api,
      reportsGateway: reports,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpFarm(
  WidgetTester tester, {
  FarmProfileData? profile,
  FakeReportsGateway? reports,
}) async {
  _signIn();
  _usePhone(tester);
  await tester.pumpWidget(MaterialApp(
    home: FarmProfileScreen(
      farmId: 'FRM0001',
      initialData: profile ?? aProfile(),
      reportsGateway: reports ?? FakeReportsGateway(),
    ),
  ));
  await tester.pump();
}

/// Open the sheet through the real `showReportSheet`, on top of a plain page.
///
/// Not pumped directly as a page body: submitting pops the sheet's modal route
/// and shows a snack bar, and neither happens if the sheet is the root route.
/// Going through the entry point the app actually uses means the post-submit
/// behaviour is exercised for real.
Future<void> _pumpSheet(
  WidgetTester tester,
  FakeReportsGateway reports, {
  ReportTargetType type = ReportTargetType.listing,
  String targetId = 'LST0001',
  String subject = 'this listing',
  ReportReason? initialReason,
}) async {
  _signIn();
  _usePhone(tester);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showReportSheet(
              context,
              targetType: type,
              targetId: targetId,
              subjectName: subject,
              initialReason: initialReason,
              gateway: reports,
            ),
            child: const Text('open sheet'),
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open sheet'));
  await tester.pumpAndSettle();
  expect(find.byKey(ReportSheet.titleKey), findsOneWidget,
      reason: 'the sheet should be open');
}

void main() {
  group('report model', () {
    test('target codes match the backend enum', () {
      expect(ReportTargetType.listing.code, 'LISTING');
      expect(ReportTargetType.message.code, 'MESSAGE');
      expect(ReportTargetType.farmer.code, 'FARMER');
      expect(ReportTargetType.user.code, 'USER');
      expect(ReportTargetType.fromCode('FARMER'), ReportTargetType.farmer);
      expect(ReportTargetType.fromCode('NOPE'), isNull);
    });

    test('every reason code is one the backend accepts', () {
      // A hard-coded mirror of Report::REASONS on the server. If the two drift,
      // the sheet will offer a reason that always 422s.
      const allowed = {
        'MISLEADING_INFO',
        'FAKE_LISTING',
        'HARASSMENT',
        'INAPPROPRIATE_CONTENT',
        'FRAUD_OR_SCAM',
        'SPAM',
        'UNSAFE_BEHAVIOR',
        'OTHER',
      };

      expect(
        ReportReason.all.map((r) => r.code).toSet(),
        allowed,
        reason: 'reason taxonomy must stay in sync with Report::REASONS',
      );
    });

    test('"Something else" is the last resort, not the first tap', () {
      expect(ReportReason.all.last, ReportReason.other);
    });

    test('the draft serialises to the exact POST body', () {
      final json = const ReportDraft(
        targetType: ReportTargetType.message,
        targetId: 'MSG0001',
        reason: ReportReason.fraudOrScam,
        details: '  asked for money  ',
      ).toJson();

      expect(json, {
        'target_type': 'MESSAGE',
        'target_id': 'MSG0001',
        'reason': 'FRAUD_OR_SCAM',
        // Trimmed: a details field of pure spaces should not reach the queue as
        // a sentence a moderator has to read.
        'details': 'asked for money',
      });
    });

    test('details past the server limit block the submit', () {
      final ok = ReportDraft(
        targetType: ReportTargetType.listing,
        targetId: 'LST0001',
        reason: ReportReason.other,
        details: 'x' * ReportDraft.maxDetails,
      );
      final tooLong = ReportDraft(
        targetType: ReportTargetType.listing,
        targetId: 'LST0001',
        reason: ReportReason.other,
        details: 'x' * (ReportDraft.maxDetails + 1),
      );

      expect(ok.canSubmit, isTrue);
      expect(tooLong.canSubmit, isFalse);
      expect(tooLong.detailsTooLong, isTrue);
    });

    test('a draft with no target cannot be submitted', () {
      expect(
        const ReportDraft(
          targetType: ReportTargetType.listing,
          targetId: '   ',
          reason: ReportReason.other,
        ).canSubmit,
        isFalse,
      );
    });

    test('a receipt can say the report was already on file', () {
      final fresh = ReportReceipt.fromJson(
        {'id': 'RPT001', 'status': 'New'},
        duplicate: false,
      );
      final repeat = ReportReceipt.fromJson(
        {'id': 'RPT001', 'status': 'Reviewing'},
        duplicate: true,
      );

      expect(fresh.duplicate, isFalse);
      expect(repeat.duplicate, isTrue);
    });

    test('a numeric id is read as text instead of crashing', () {
      // This is the shape the server really sends: report.RPT_ID is this
      // schema's only auto-increment, so it arrives as a JSON number while
      // every other id in the API is a string. A hard `as String` cast threw
      // "type 'int' is not a subtype of type 'String'" — and because the
      // report was already saved by then, the sheet reported a failure for a
      // report that was sitting safely in the moderator's queue, and a retry
      // took the duplicate path and failed identically.
      final receipt = ReportReceipt.fromJson(
        {'id': 7, 'status': 'New', 'created_at': '2026-10-01T17:12:30Z'},
        duplicate: false,
      );

      expect(receipt.id, '7');
      expect(receipt.status, 'New');
      expect(receipt.createdAt, isNotNull);
    });

    test('a receipt survives nulls and wrongly typed fields', () {
      // A response that omits fields, or sends the wrong type, must not throw
      // on its way to the UI. The id is coerced; a date that is not a date
      // simply reads as unknown.
      final receipt = ReportReceipt.fromJson(
        {'id': 12, 'status': null, 'created_at': 'not-a-date'},
        duplicate: true,
      );

      expect(receipt.id, '12');
      expect(receipt.status, isNull);
      expect(receipt.createdAt, isNull);
      expect(receipt.duplicate, isTrue);
    });
  });

  group('report sheet', () {
    testWidgets('submit stays disabled until a reason is chosen',
        (tester) async {
      await _pumpSheet(tester, FakeReportsGateway());

      final button = find.byKey(ReportSheet.submitButtonKey);
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

      await _tapReason(tester, 'SPAM');
      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    });

    testWidgets('it files the chosen reason and details', (tester) async {
      final reports = FakeReportsGateway();
      await _pumpSheet(tester, reports, subject: 'this carrot listing');

      await _fileReport(
        tester,
        reasonCode: 'MISLEADING_INFO',
        details: 'the photo is a different vegetable',
      );

      expect(reports.drafts, hasLength(1));
      expect(reports.drafts.single.targetType, ReportTargetType.listing);
      expect(reports.drafts.single.targetId, 'LST0001');
      expect(reports.drafts.single.reason, ReportReason.misleadingInfo);
      expect(reports.drafts.single.details, 'the photo is a different vegetable');
    });

    testWidgets('it says nothing is hidden automatically', (tester) async {
      // The honest framing: a report is a queue entry, not a takedown. Stating
      // it up front stops people reporting and expecting the listing to vanish.
      await _pumpSheet(tester, FakeReportsGateway());

      expect(find.text('Nothing is hidden automatically.'), findsOneWidget);
    });

    testWidgets('every reason is offered and each explains itself',
        (tester) async {
      await _pumpSheet(tester, FakeReportsGateway());

      for (final reason in ReportReason.all) {
        await _tapReason(tester, reason.code);
        // The hint is what makes the choice mean something to a moderator, so
        // the specific reasons must actually carry one.
        if (reason != ReportReason.other) {
          expect(find.text(reason.hint!), findsOneWidget);
        }
      }
    });

    testWidgets('a duplicate report gets different wording from a new one',
        (tester) async {
      final reports = FakeReportsGateway()..duplicate = true;
      await _pumpSheet(tester, reports);

      await _fileReport(tester, reasonCode: 'SPAM');

      // A 200 means the team already has this complaint. Saying "report sent"
      // would imply a fresh one was opened when none was.
      expect(find.textContaining('already reported'), findsOneWidget);
    });

    testWidgets('a failure keeps the sheet open with the text intact',
        (tester) async {
      final reports = FakeReportsGateway()..error = 'Could not reach the server.';
      await _pumpSheet(tester, reports);

      await _tapReason(tester, 'SPAM');
      await _revealDetails(tester);
      await tester.enterText(
          find.byKey(ReportSheet.detailsFieldKey), 'thirty messages in a row');
      await tester.pump();
      await tester.tap(find.byKey(ReportSheet.submitButtonKey));
      await _settleModal(tester);

      // Losing a written explanation to a failed upload would be the worst
      // outcome of this flow, so the sheet stays put with everything in it.
      await tester.scrollUntilVisible(
          find.byKey(ReportSheet.errorKey), 100, scrollable: _sheetScrollable());
      await tester.pump();
      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.byKey(ReportSheet.submitButtonKey), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(ReportSheet.detailsFieldKey))
            .controller
            ?.text,
        'thirty messages in a row',
      );
    });

    testWidgets('the counter shows how much room is left', (tester) async {
      await _pumpSheet(tester, FakeReportsGateway());

      await _revealDetails(tester);
      await tester.enterText(find.byKey(ReportSheet.detailsFieldKey), 'hello');
      await tester.pump();

      expect(find.text('5 / ${ReportDraft.maxDetails}'), findsOneWidget);
    });

    testWidgets('a pre-selected reason is submitted without another tap',
        (tester) async {
      // The chat long-press pre-selects the scam reason, so a user who agrees
      // must be able to send immediately.
      final reports = FakeReportsGateway();
      await _pumpSheet(
        tester,
        reports,
        type: ReportTargetType.message,
        targetId: 'MSG0001',
        subject: 'this message',
        initialReason: ReportReason.fraudOrScam,
      );

      final button = find.byKey(ReportSheet.submitButtonKey);
      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await _settleModal(tester);

      expect(reports.drafts.single.reason, ReportReason.fraudOrScam);
    });
  });

  group('product detail: report the listing', () {
    testWidgets('offers a report link below the contact buttons',
        (tester) async {
      await _pumpDetail(tester);

      final link = find.byKey(ProductDetailScreen.reportListingKey);
      expect(link, findsOneWidget);
      expect(find.text('Report this listing'), findsOneWidget);

      // Below the primary actions, never competing with them.
      final callY = tester.getTopLeft(find.textContaining('Call Seller')).dy;
      final reportY = tester.getTopLeft(find.text('Report this listing')).dy;
      expect(reportY, greaterThan(callY));
    });

    testWidgets('files a LISTING report for this listing', (tester) async {
      final reports = FakeReportsGateway();
      await _pumpDetail(tester, reports: reports);

      await tester.ensureVisible(
          find.byKey(ProductDetailScreen.reportListingKey));
      await tester.pump();
      await tester.tap(find.byKey(ProductDetailScreen.reportListingKey));
      await _settleModal(tester);
      await _fileReport(tester, reasonCode: 'FAKE_LISTING', details: 'no such crop');

      expect(reports.drafts.single.targetType, ReportTargetType.listing);
      expect(reports.drafts.single.targetId, 'LST0001');
      expect(reports.drafts.single.reason, ReportReason.fakeListing);
    });

    testWidgets('hides the link for a listing with no real id', (tester) async {
      // Seeded or mocked listings have no LST_ID and the server validates
      // size:6, so a link there could only ever fail.
      await _pumpDetail(tester, listing: aListing(listingId: null));

      expect(find.byKey(ProductDetailScreen.reportListingKey), findsNothing);
    });
  });

  group('chat: report a message', () {
    testWidgets('long-pressing a received message files a MESSAGE report',
        (tester) async {
      final api = _Messages()..stored.add(aMessage());
      final reports = FakeReportsGateway();
      await _pumpChat(tester, api: api, reports: reports);

      await tester.longPress(
          find.byKey(InAppMessagesScreen.bubbleKey('MSG0001')));
      await _settleModal(tester);
      await _fileReport(tester, reasonCode: 'FRAUD_OR_SCAM');

      expect(reports.drafts.single.targetType, ReportTargetType.message);
      expect(reports.drafts.single.targetId, 'MSG0001');
      expect(reports.drafts.single.reason, ReportReason.fraudOrScam);
    });

    testWidgets('the reported message is the one that was long-pressed',
        (tester) async {
      final api = _Messages()
        ..stored.add(aMessage(id: 'MSGAAAA', content: 'first', minutesAgo: 2))
        ..stored.add(aMessage(id: 'MSGBBBB', content: 'second', minutesAgo: 1));
      final reports = FakeReportsGateway();
      await _pumpChat(tester, api: api, reports: reports);

      await tester.ensureVisible(
          find.byKey(InAppMessagesScreen.bubbleKey('MSGBBBB')));
      await tester.pump();
      // Invoked directly rather than as a gesture: the newest bubble sits
      // against the composer, so a coordinate long-press can land on the input
      // bar instead. The first test above covers the real gesture.
      tester
          .widget<GestureDetector>(
              find.byKey(InAppMessagesScreen.bubbleKey('MSGBBBB')))
          .onLongPress!();
      await _settleModal(tester);
      await _fileReport(tester, reasonCode: 'SPAM');

      // Picking the wrong message would put an innocent sentence in front of
      // a moderator, so the id has to be the pressed one.
      expect(reports.drafts.single.targetId, 'MSGBBBB');
    });

    testWidgets('your own message cannot be reported', (tester) async {
      final api = _Messages()..stored.add(aMessage(id: 'MSGMINE', isMine: true));
      final reports = FakeReportsGateway();
      await _pumpChat(tester, api: api, reports: reports);

      await tester.longPress(
          find.byKey(InAppMessagesScreen.bubbleKey('MSGMINE')));
      await _settleModal(tester);

      // The server refuses a report on your own message, so there is nothing
      // to offer. Inert beats a menu item that can only produce an error.
      expect(find.byKey(ReportSheet.titleKey), findsNothing);
      expect(reports.drafts, isEmpty);
    });
  });

  group('chat: report the other person', () {
    testWidgets('a buyer reporting a seller targets the farmer', (tester) async {
      final reports = FakeReportsGateway();
      await _pumpChat(tester, api: _Messages(), reports: reports);

      await tester.tap(find.byKey(InAppMessagesScreen.reportCounterpartyKey));
      await _settleModal(tester);
      await _fileReport(tester, reasonCode: 'HARASSMENT');

      // A scammer seller is a different report from a compromised account, and
      // the farmer id is the one a moderator can act on across their history.
      expect(reports.drafts.single.targetType, ReportTargetType.farmer);
      expect(reports.drafts.single.targetId, 'FMR0001');
    });

    testWidgets('a seller reporting a buyer targets the user account',
        (tester) async {
      final reports = FakeReportsGateway();
      await _pumpChat(
        tester,
        api: _Messages(),
        reports: reports,
        conversation: Conversation.fromJson(
          conversationJson(role: 'SELLER', otherName: 'Maria'),
        ),
      );

      await tester.tap(find.byKey(InAppMessagesScreen.reportCounterpartyKey));
      await _settleModal(tester);
      await _fileReport(tester, reasonCode: 'SPAM');

      // A buyer has no farmer record, so the account is the only thing there is.
      expect(reports.drafts.single.targetType, ReportTargetType.user);
      expect(reports.drafts.single.targetId, 'USR0002');
    });

    testWidgets('a buyer falls back to the account when no farmer id is sent',
        (tester) async {
      final reports = FakeReportsGateway();
      await _pumpChat(
        tester,
        api: _Messages(),
        reports: reports,
        conversation:
            Conversation.fromJson(conversationJson(sellerFarmerId: null)),
      );

      await tester.tap(find.byKey(InAppMessagesScreen.reportCounterpartyKey));
      await _settleModal(tester);
      await _fileReport(tester, reasonCode: 'OTHER');

      expect(reports.drafts.single.targetType, ReportTargetType.user);
      expect(reports.drafts.single.targetId, 'USR0002');
    });

    testWidgets('the header action is hidden with no counterparty id',
        (tester) async {
      await _pumpChat(
        tester,
        api: _Messages(),
        reports: FakeReportsGateway(),
        conversation: Conversation.fromJson(
          conversationJson(sellerFarmerId: null, otherId: ''),
        ),
      );

      // Nothing to report means no button, rather than one that errors.
      expect(find.byKey(InAppMessagesScreen.reportCounterpartyKey), findsNothing);
    });

    test('counterparty target resolution is unit-testable', () {
      expect(
        Conversation.fromJson(conversationJson()).counterpartyReportTarget?.type,
        ReportTargetType.farmer,
      );
      expect(
        Conversation.fromJson(conversationJson(role: 'SELLER'))
            .counterpartyReportTarget
            ?.type,
        ReportTargetType.user,
      );
      expect(
        Conversation.fromJson(conversationJson(otherId: '', sellerFarmerId: null))
            .counterpartyReportTarget,
        isNull,
      );
    });
  });

  group('farm profile: report the farmer', () {
    testWidgets('offers a report link for the farm owner', (tester) async {
      await _pumpFarm(tester);

      expect(find.byKey(FarmProfileScreen.reportFarmKey), findsOneWidget);
      expect(find.text('Report this farm'), findsOneWidget);
    });

    testWidgets('files a FARMER report against the owner', (tester) async {
      final reports = FakeReportsGateway();
      await _pumpFarm(tester, reports: reports);

      await tester.tap(find.byKey(FarmProfileScreen.reportFarmKey));
      await _settleModal(tester);
      await _fileReport(tester, reasonCode: 'UNSAFE_BEHAVIOR');

      // The farmer, not the farm and not the account: a person with a selling
      // history a moderator can act on.
      expect(reports.drafts.single.targetType, ReportTargetType.farmer);
      expect(reports.drafts.single.targetId, 'FMR0001');
    });

    testWidgets('hides the link when the owner cannot be resolved',
        (tester) async {
      await _pumpFarm(tester, profile: aProfile(farmerId: null));

      // An unlinked farmer has no FMR_ID to report.
      expect(find.byKey(FarmProfileScreen.reportFarmKey), findsNothing);
    });

    test('the profile exposes the owner ids the sheet needs', () {
      final profile = aProfile();

      expect(profile.ownerFarmerId, 'FMR0001');
      expect(profile.ownerUserId, 'USR0002');
      expect(profile.canReportOwner, isTrue);
      expect(profile.reportSubjectName, 'React A');
      expect(aProfile(farmerId: null).canReportOwner, isFalse);
    });
  });

  group('listing model', () {
    test('carries the farmer id through to the card shape', () {
      // ProductDetailScreen receives a CropListing, not a Listing, so the id
      // has to survive the conversion or the report is unreachable.
      final card = Listing.fromJson({
        'id': 'LST0001',
        'status': 'AVAILABLE_NOW',
        'crop_icon': 'carrot',
        'farmer': {
          'id': 'FMR0001',
          'name': 'React A',
          'mobile_number': '09171234567',
        },
      }).toCropListing();

      expect(card.farmerId, 'FMR0001');
      expect(card.listingId, 'LST0001');
    });
  });
}
