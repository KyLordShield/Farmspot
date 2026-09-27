import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/conversation.dart';
import 'package:farmspot_app/screens/in_app_messages_screen.dart';
import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/services/message_service.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

/// Records what the detail screen asked the backend for, so the "Message
/// Seller" hand-off is verified without a server.
class _RecordingGateway implements MessagesGateway {
  int starts = 0;
  String? startError;
  String? lastListingId;

  @override
  Future<Conversation> startConversation(String listingId) async {
    starts++;
    lastListingId = listingId;
    if (startError != null) throw Exception(startError!);
    return Conversation.fromJson({
      'id': 'CNV0001',
      'listing_id': listingId,
      'buyer_id': 'BUY0001',
      'seller_farmer_id': 'FMR0001',
      'farm_id': 'FRM0001',
      'last_message': null,
      'last_message_at': null,
      'created_at': DateTime.now().toIso8601String(),
      'unread_count': 0,
      'my_role': 'BUYER',
      'farm': {'id': 'FRM0001', 'name': 'Test Farm', 'barangay': 'Sudlon II'},
      'other_party': {'id': 'USR0002', 'name': 'React A', 'photo': null},
      'listing': {
        'id': listingId,
        'crop_icon': 'Cabbage',
        'image': null,
        'category': {'id': 'CAT0001', 'name': 'Vegetables'},
        'farm': {
          'id': 'FRM0001',
          'name': 'Test Farm',
          'barangay': 'Sudlon II'
        },
      },
    });
  }

  @override
  Future<List<Conversation>> fetchConversations() async => [];

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId,
      {String? after}) async =>
      [];

  @override
  Future<ChatMessage> sendMessage(String conversationId, String content) async =>
      throw UnimplementedError();
}

// Widget-level check of the detail-screen name/image fix. Combined with
// home_feed_mapping_test (which proves live backend rows map into exactly this
// CropListing shape via toCropListing), this verifies the full path:
// real listing -> toggle -> detail renders name + photo; photo-less -> icon.
void main() {
  testWidgets('detail screen shows real crop name + photo, other fields intact',
      (tester) async {
    final listing = CropListing(
      cropName: 'Cabbage',
      farmName: 'Test Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: '0.4 km away',
      contactNumber: '09870000000',
      imageUrl: 'https://example.invalid/photo.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    // Real crop name as the headline (old static "Crop name:" label gone).
    expect(find.text('Cabbage'), findsOneWidget);
    expect(find.text('Crop name:'), findsNothing);

    // Already-working fields untouched.
    expect(find.text('Test Farm'), findsOneWidget);
    expect(find.text('Vegetables'), findsOneWidget);
    expect(find.textContaining('Call Seller'), findsOneWidget);
    expect(find.text('Message Seller'), findsOneWidget);
    expect(find.text('Sudlon II'), findsOneWidget);
    expect(find.text('Posted '), findsOneWidget);

    // Photo renders (Image.network; offline test env falls back gracefully).
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('photo-less listing shows placeholder icon instead of breaking',
      (tester) async {
    final listing = CropListing(
      cropName: 'Kangkong',
      farmName: 'Test Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: '0.4 km away',
      contactNumber: '09870000000',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    expect(find.text('Kangkong'), findsOneWidget);
    expect(find.byIcon(Icons.eco), findsOneWidget); // placeholder icon
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Call Seller'), findsOneWidget);
    expect(find.text('Message Seller'), findsOneWidget);
  });

  testWidgets('Message Seller opens the real thread for that listing',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    final gateway = _RecordingGateway();
    final listing = CropListing(
      cropName: 'Cabbage',
      farmName: 'Test Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      barangay: 'Sudlon II',
      listingId: 'LST0001',
    );

    await tester.pumpWidget(MaterialApp(
      home: ProductDetailScreen(listing: listing, gateway: gateway),
    ));
    await tester.pump();

    await tester.tap(find.text('Message Seller'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gateway.starts, 1,
        reason: 'the thread is created/fetched before navigating');
    expect(gateway.lastListingId, 'LST0001');
    expect(find.byType(InAppMessagesScreen), findsOneWidget);
    expect(find.text('React A'), findsOneWidget,
        reason: 'the chat screen shows the other party from the server');
  });

  testWidgets('a failed thread creation explains itself instead of opening a chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    final gateway = _RecordingGateway()..startError = 'No network';
    final listing = CropListing(
      cropName: 'Cabbage',
      farmName: 'Test Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      barangay: 'Sudlon II',
      listingId: 'LST0001',
    );

    await tester.pumpWidget(MaterialApp(
      home: ProductDetailScreen(listing: listing, gateway: gateway),
    ));
    await tester.pump();

    await tester.tap(find.text('Message Seller'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No network'), findsOneWidget);
    expect(find.byType(InAppMessagesScreen), findsNothing);
  });

  testWidgets('a listing with no id cannot be messaged', (tester) async {
    final gateway = _RecordingGateway();
    final listing = CropListing(
      cropName: 'Cabbage',
      farmName: 'Test Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      barangay: 'Sudlon II',
    );

    await tester.pumpWidget(MaterialApp(
      home: ProductDetailScreen(listing: listing, gateway: gateway),
    ));
    await tester.pump();

    await tester.tap(find.text('Message Seller'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gateway.starts, 0,
        reason: 'legacy rows without a listing id have no thread to open');
    expect(find.textContaining('cannot be messaged'), findsOneWidget);
  });
}