import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/models/crop_category.dart';
import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/screens/seller/add_crop_screen.dart';
import 'package:farmspot_app/screens/seller/edit_farm_screen.dart';
import 'package:farmspot_app/widgets/seller_widgets.dart';
import 'package:farmspot_app/widgets/renew_listing_sheet.dart';

XFile photo(int i) => XFile.fromData(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
  ),
  name: 'photo$i.png',
);
Future<void> showPicker(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byType(PhotoPlaceholder),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'new listing clamps selections to five photos and frees a slot on removal',
    (tester) async {
      var slots = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AddCropScreen(
            isFirstCrop: true,
            farmId: 'FARM01',
            loadCategories: () async => [
              CropCategory(id: 'LEAFVG', name: 'Vegetables'),
            ],
            selectPhotos: (remaining) async {
              slots = remaining;
              return List.generate(7, photo);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await showPicker(tester);
      await tester.tap(find.byType(PhotoPlaceholder));
      await tester.pumpAndSettle();
      expect(slots, 5);
      expect(find.byType(PhotoPlaceholder), findsNothing);
      expect(find.textContaining('5/5 photos'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.byType(PhotoPlaceholder), findsOneWidget);
      expect(find.textContaining('4/5 photos'), findsOneWidget);
    },
  );

  testWidgets(
    'editing a full listing requires removing an existing photo first',
    (tester) async {
      final listing = Listing(
        id: 'LST001',
        cropIcon: 'Carrot',
        status: 'AVAILABLE_NOW',
        categoryId: 'LEAFVG',
        photos: List.generate(
          5,
          (i) => ListingPhoto(
            id: 'P$i',
            url: 'https://example.test/p$i.png',
            isPrimary: i == 0,
          ),
        ),
      );
      var slots = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AddCropScreen(
            existingListing: listing,
            loadCategories: () async => [
              CropCategory(id: 'LEAFVG', name: 'Vegetables'),
            ],
            selectPhotos: (remaining) async {
              slots = remaining;
              return [photo(1), photo(2)];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('listing_photo_edit_P0')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PhotoPlaceholder), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('listing_photo_edit_P0')),
          matching: find.byTooltip('Remove photo'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PhotoPlaceholder), findsOneWidget);
      await tester.tap(find.byType(PhotoPlaceholder));
      await tester.pumpAndSettle();
      expect(slots, 1);
      expect(find.byType(PhotoPlaceholder), findsNothing);
      expect(find.textContaining('5/5 photos'), findsOneWidget);
    },
  );

  testWidgets('farm edit counts retained photos and stops at four', (
    tester,
  ) async {
    final farm = FarmProfileData(
      id: 'FARM01',
      name: 'Farm',
      photos: List.generate(
        4,
        (i) => FarmPhotoEntry(
          id: 'P$i',
          url: 'https://example.test/f$i.png',
          isPrimary: i == 0,
        ),
      ),
    );
    var slots = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EditFarmScreen(
          farmId: farm.id,
          loadFarm: (_) async => farm,
          selectPhotos: (remaining) async {
            slots = remaining;
            return [photo(1), photo(2)];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PhotoPlaceholder), findsNothing);
    final first = find.byKey(const ValueKey('farm_photo_edit_P0'));
    await tester.scrollUntilVisible(
      first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: first, matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PhotoPlaceholder));
    await tester.pumpAndSettle();
    expect(slots, 1);
    expect(find.byType(PhotoPlaceholder), findsNothing);
    expect(find.text('4/4 photos'), findsOneWidget);
  });

  testWidgets('renewal stops offering capture at five fresh photos', (
    tester,
  ) async {
    var captures = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RenewListingSheet(
            listing: Listing(id: 'LST001', status: 'NOT_AVAILABLE'),
            capturePhoto: () async => photo(captures++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      final capture = find.byKey(RenewListingSheet.captureKey);
      await tester.ensureVisible(capture);
      await tester.pumpAndSettle();
      await tester.tap(capture);
      await tester.pumpAndSettle();
    }
    expect(captures, 5);
    expect(find.byKey(RenewListingSheet.captureKey), findsNothing);
    await tester.tap(find.byKey(RenewListingSheet.removePhotoKey(0)));
    await tester.pumpAndSettle();
    expect(find.byKey(RenewListingSheet.captureKey), findsOneWidget);
  });
}
