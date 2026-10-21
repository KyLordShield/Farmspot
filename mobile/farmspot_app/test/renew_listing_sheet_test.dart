import 'dart:convert';
import 'dart:typed_data';

import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/widgets/renew_listing_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

// A real 1x1 PNG, so Image.memory can decode the captured preview in the test
// environment instead of throwing an image-codec error.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
  '/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);

Listing _expiredListing({
  String status = 'AVAILABLE_NOW',
  String? harvestDate,
  DateTime? lastRenewedAt,
  int renewalCount = 0,
}) {
  return Listing(
    id: 'LST001',
    cropIcon: 'Tomato',
    status: status,
    expiryDate: DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String(),
    harvestDate: harvestDate,
    lastRenewedAt: lastRenewedAt?.toIso8601String(),
    renewalCount: renewalCount,
    farmId: 'AAAAAA',
    farmName: 'North Field',
  );
}

Future<XFile> _freshPhoto() async =>
    XFile.fromData(_onePixelPng, name: 'fresh.png', mimeType: 'image/png');

void main() {
  testWidgets('renewal needs a captured photo before it can be submitted', (
    tester,
  ) async {
    Listing? renewed;
    String? sentStatus;
    DateTime? sentDate;
    final returned = _expiredListing(
      lastRenewedAt: DateTime.now(),
      renewalCount: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                renewed = await showRenewListingSheet(
                  context,
                  listing: _expiredListing(),
                  capturePhoto: _freshPhoto,
                  renew:
                      ({
                        required String listingId,
                        required List<XFile> photos,
                        required String status,
                        DateTime? harvestDate,
                        int primaryIndex = 0,
                      }) async {
                        expect(listingId, 'LST001');
                        expect(photos, isNotEmpty);
                        expect(await photos.first.length(), greaterThan(0));
                        expect(primaryIndex, 0);
                        sentStatus = status;
                        sentDate = harvestDate;
                        return returned;
                      },
                );
              },
              child: const Text('Open renewal'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open renewal'));
    await tester.pumpAndSettle();

    expect(find.text('Take at least one fresh photo to continue.'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(RenewListingSheet.submitKey))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(RenewListingSheet.captureKey));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ElevatedButton>(find.byKey(RenewListingSheet.submitKey))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(RenewListingSheet.submitKey));
    await tester.pumpAndSettle();

    expect(sentStatus, 'AVAILABLE_NOW');
    expect(sentDate, isNull);
    expect(renewed?.id, 'LST001');
    expect(renewed?.renewalCount, 1);
  });

  testWidgets('soon-to-harvest renewal asks for a date before submitting', (
    tester,
  ) async {
    String? sentStatus;
    DateTime? sentDate;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await showRenewListingSheet(
                  context,
                  listing: _expiredListing(status: 'NOT_AVAILABLE'),
                  capturePhoto: _freshPhoto,
                  renew:
                      ({
                        required String listingId,
                        required List<XFile> photos,
                        required String status,
                        DateTime? harvestDate,
                        int primaryIndex = 0,
                      }) async {
                        expect(photos, isNotEmpty);
                        sentStatus = status;
                        sentDate = harvestDate;
                        return _expiredListing(
                          status: status,
                          harvestDate: harvestDate?.toIso8601String(),
                        );
                      },
                );
              },
              child: const Text('Open renewal'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open renewal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RenewListingSheet.captureKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soon to harvest'));
    await tester.pumpAndSettle();

    // A soon listing without a date is not a complete claim about the crop.
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(RenewListingSheet.submitKey))
          .onPressed,
      isNull,
    );
    expect(find.byKey(RenewListingSheet.dateKey), findsOneWidget);

    await tester.tap(find.byKey(RenewListingSheet.dateKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(RenewListingSheet.submitKey));
    await tester.pumpAndSettle();

    expect(sentStatus, 'SOON_TO_HARVEST');
    expect(sentDate, isNotNull);

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(
      DateTime(sentDate!.year, sentDate!.month, sentDate!.day),
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
    );
  });

  testWidgets('renewal can capture several photos and star the thumbnail', (
    tester,
  ) async {
    List<XFile>? sentPhotos;
    int? sentPrimary;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await showRenewListingSheet(
                  context,
                  listing: _expiredListing(),
                  capturePhoto: _freshPhoto,
                  renew:
                      ({
                        required String listingId,
                        required List<XFile> photos,
                        required String status,
                        DateTime? harvestDate,
                        int primaryIndex = 0,
                      }) async {
                        sentPhotos = photos;
                        sentPrimary = primaryIndex;
                        return _expiredListing();
                      },
                );
              },
              child: const Text('Open renewal'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open renewal'));
    await tester.pumpAndSettle();

    // Two separate camera captures, then the second one is starred as the
    // thumbnail buyers will see.
    await tester.tap(find.byKey(RenewListingSheet.captureKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RenewListingSheet.captureKey));
    await tester.pumpAndSettle();

    expect(find.byKey(RenewListingSheet.photoKey(0)), findsOneWidget);
    expect(find.byKey(RenewListingSheet.photoKey(1)), findsOneWidget);

    await tester.tap(find.byKey(RenewListingSheet.photoKey(1)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(RenewListingSheet.submitKey));
    await tester.pumpAndSettle();

    expect(sentPhotos, hasLength(2));
    expect(sentPrimary, 1);
  });
}
