import 'dart:async';
import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/models/crop_category.dart';
import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/screens/seller/add_crop_screen.dart';
import 'package:farmspot_app/screens/seller/edit_farm_screen.dart';
import 'package:farmspot_app/services/image_detect_service.dart';
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
  testWidgets('choosing a detected tomato fills listing details', (
    tester,
  ) async {
    final selectedPhoto = photo(1);
    final moderation = Completer<List<XFile>>();
    final scan = Completer<List<DetectedCrop>>();
    await tester.pumpWidget(
      MaterialApp(
        home: AddCropScreen(
          isFirstCrop: true,
          farmId: 'FARM01',
          loadCategories: () async => [
            CropCategory(
              id: 'LEAFVG',
              name: 'Vegetables',
              cropNames: ['tomato'],
            ),
          ],
          selectPhotos: (_) async => [selectedPhoto],
          moderatePhotos: (_, photos) => moderation.future,
          detectCrops: (photo) {
            expect(photo, same(selectedPhoto));
            return scan.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await showPicker(tester);
    await tester.tap(find.byType(PhotoPlaceholder));
    await tester.pump();
    expect(find.text('Checking your photo'), findsOneWidget);
    moderation.complete([selectedPhoto]);
    await tester.pump();
    expect(find.text('Identifying your crop'), findsOneWidget);
    scan.complete([
      DetectedCrop(name: 'kamatis', confidence: 0.95),
      DetectedCrop(name: 'cucumber', confidence: 0.85),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Which crop are you listing?'), findsOneWidget);
    expect(find.text('Cucumber'), findsOneWidget);
    await tester.tap(find.text('Tomato'));
    await tester.pumpAndSettle();
    expect(find.text('Tomato'), findsOneWidget);
    expect(
      tester.widget<CropPickerTile>(find.byType(CropPickerTile)).selected,
      isTrue,
    );
    final thumbnail = find.byKey(ObjectKey(selectedPhoto));
    await tester.ensureVisible(thumbnail);
    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);

    final description = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.maxLines == 4,
    );
    await tester.scrollUntilVisible(
      description,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(description).controller!;
    expect(
      controller.text,
      'Tomatoes for fresh salads, homemade sauces, and everyday cooking.',
    );
    await tester.enterText(description, '');
    expect(controller.text, isEmpty);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.scrollUntilVisible(
      find.text('Available Now'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Standard listing window · About 5 days'),
      findsOneWidget,
    );

    final soon = find.text('Soon to Harvest');
    await tester.ensureVisible(soon);
    await tester.tap(soon);
    await tester.pumpAndSettle();
    final changeDate = find.text(
      'Suggested date. Tap to adjust for your crop.',
    );
    await tester.scrollUntilVisible(
      changeDate,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(changeDate);
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialEntryMode, DatePickerEntryMode.calendarOnly);
    expect(picker.initialDate, DateUtils.addDaysToDate(picker.firstDate, 14));
    expect(picker.lastDate, DateUtils.addDaysToDate(picker.firstDate, 60));
  });

  testWidgets('the scan estimate is shown for the chosen crop', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddCropScreen(
          isFirstCrop: true,
          farmId: 'FARM01',
          loadCategories: () async => [],
          selectPhotos: (_) async => [photo(1)],
          moderatePhotos: (_, photos) async => photos,
          detectCrops: (_) async => [
            DetectedCrop(
              name: 'kamatis',
              confidence: 0.95,
              shelfLifeDays: 7,
              estimateToken: 'scanned-estimate',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await showPicker(tester);
    await tester.tap(find.byType(PhotoPlaceholder));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Available Now'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Estimated shelf life · About 7 days'),
      findsOneWidget,
    );
    expect(find.textContaining('Standard listing window'), findsNothing);
  });

  for (final keepHarvestDate in [false, true]) {
    testWidgets(
      'ripe photo confirms availability, keep date: $keepHarvestDate',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AddCropScreen(
              isFirstCrop: true,
              farmId: 'FARM01',
              loadCategories: () async => [],
              selectPhotos: (_) async => [photo(1)],
              moderatePhotos: (_, photos) async => photos,
              detectCrops: (_) async => [
                DetectedCrop(
                  name: 'kamatis',
                  confidence: 0.95,
                  condition: 'tomato_ripe',
                  shelfLifeDays: 4,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await showPicker(tester);
        await tester.tap(find.byType(PhotoPlaceholder));
        await tester.pumpAndSettle();

        final soon = find.text('Soon to Harvest');
        await tester.scrollUntilVisible(
          soon,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(soon);
        await tester.pumpAndSettle();
        expect(find.text('This photo looks ripe'), findsOneWidget);
        await tester.tap(
          find.text(keepHarvestDate ? 'Keep harvest date' : 'Available now'),
        );
        await tester.pumpAndSettle();
        final upcomingTile = tester.widget<SelectableOptionTile>(
          find.ancestor(of: soon, matching: find.byType(SelectableOptionTile)),
        );
        expect(upcomingTile.selected, keepHarvestDate);
        if (keepHarvestDate) {
          expect(upcomingTile.subtitle, startsWith('Ready around'));
        } else {
          expect(
            find.text('Estimated shelf life · About 4 days'),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets('new listing can open in-app camera before the form', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddCropScreen(
          isFirstCrop: true,
          farmId: 'FARM01',
          openCameraOnStart: true,
          loadCategories: () async => [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Crop photo'), findsOneWidget);
    expect(find.text('CROP NAME'), findsNothing);
  });

  testWidgets(
    'failed scans keep returning to capture until a crop is detected',
    (tester) async {
      var captures = 0;
      var scans = 0;
      final attempts = List.generate(5, (_) => Completer<List<DetectedCrop>>());
      await tester.pumpWidget(
        MaterialApp(
          home: AddCropScreen(
            isFirstCrop: true,
            farmId: 'FARM01',
            openCameraOnStart: true,
            loadCategories: () async => [],
            selectPhotos: (_) async => [photo(++captures)],
            moderatePhotos: (_, photos) async => photos,
            detectCrops: (_) => attempts[scans++].future,
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < attempts.length; i++) {
        expect(captures, i + 1);
        expect(scans, i + 1);
        expect(find.text('CROP NAME'), findsNothing);
        attempts[i].complete(
          i == attempts.length - 1
              ? [DetectedCrop(name: 'kamatis', confidence: 0.95)]
              : [],
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(captures, 5);
      expect(find.text('Tomato'), findsOneWidget);
      final name = tester.widget<TextField>(find.byType(TextField).first);
      expect(name.readOnly, isTrue);
      expect(find.textContaining('1/5 photos'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(name.controller!.text, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isTrue,
      );
    },
  );

  testWidgets('rejected listing photos never enter the upload gallery', (
    tester,
  ) async {
    var checked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AddCropScreen(
          isFirstCrop: true,
          farmId: 'FARM01',
          loadCategories: () async => [
            CropCategory(id: 'LEAFVG', name: 'Vegetables'),
          ],
          selectPhotos: (_) async => [photo(1)],
          moderatePhotos: (_, photos) async {
            checked += photos.length;
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await showPicker(tester);
    await tester.tap(find.byType(PhotoPlaceholder));
    await tester.pumpAndSettle();
    expect(checked, 1);
    expect(find.textContaining('0/5 photos'), findsOneWidget);
    expect(find.byType(PhotoPlaceholder), findsOneWidget);
  });

  testWidgets('extra photos must show the listing crop', (tester) async {
    final tomato = photo(1);
    final cucumber = photo(2);
    final secondTomato = photo(3);
    await tester.pumpWidget(
      MaterialApp(
        home: AddCropScreen(
          isFirstCrop: true,
          farmId: 'FARM01',
          loadCategories: () async => [],
          selectPhotos: (_) async => [tomato, cucumber, secondTomato],
          moderatePhotos: (_, photos) async => photos,
          detectCrops: (image) async => [
            DetectedCrop(
              name: image == cucumber ? 'cucumber' : 'kamatis',
              confidence: 0.95,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await showPicker(tester);
    await tester.tap(find.byType(PhotoPlaceholder));
    await tester.pumpAndSettle();

    expect(find.byKey(ObjectKey(tomato)), findsOneWidget);
    expect(find.byKey(ObjectKey(cucumber)), findsNothing);
    expect(find.byKey(ObjectKey(secondTomato)), findsOneWidget);
    expect(find.text('2/5 photos'), findsOneWidget);
    expect(find.textContaining('only Tomato'), findsOneWidget);
  });

  testWidgets(
    'new listing clamps selections to five photos and frees a slot on removal',
    (tester) async {
      var slots = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AddCropScreen(
            moderatePhotos: (_, photos) async => photos,
            detectCrops: (_) async => [
              DetectedCrop(name: 'kamatis', confidence: 0.95),
            ],
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
      await tester.tap(find.byIcon(Icons.close).last);
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
            moderatePhotos: (_, photos) async => photos,
            existingListing: listing,
            detectCrops: (_) async => [
              DetectedCrop(name: 'carrot', confidence: 0.95),
            ],
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
          moderatePhotos: (_, photos) async => photos,
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
            moderatePhotos: (_, photos) async => photos,
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
