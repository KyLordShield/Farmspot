import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/farm_service.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server. Mirrors the EditFarmScreen submit sequence against
// the libando demo farm XZYQNH:
//   1. Fetch the current farm profile (pre-fill name/description/photos).
//   2. updateFarm(...) — name/description PATCH round-trip persists.
//   3. addFarmPhotos(...) — appends a new photo WITHOUT removing existing ones.
//   4. setFarmPrimaryPhoto(...) — the appended photo becomes the cover.
//   5. removeFarmPhoto(...) — deletes it again (back to the pre-test photo set).
//   6. Restore name/description + the original cover so the dev DB isn't left
//      mutated. There is no location-editing surface anywhere.
void main() {
  test('edit-farm data flow round-trip against real backend', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
    final error = await AuthService.login(
      'libando@gmail.com',
      'password123',
    );
    expect(error, isNull);

    const farmId = 'XZYQNH';

    // ---- Pre-fill source (EditFarmScreen._load calls this) ----
    final before = await FarmService.fetchFarmProfile(farmId);
    expect(before.id, farmId);
    final originalName = before.name;
    final originalDesc = before.description;
    final originalPhotos = List<String>.from(before.photoUrls);
    final originalCoverId = _primaryId(before.photos);

    // ---- Edit name/description (JSON PATCH) ----
    const newName = 'React A Farm EDITED';
    const newDesc = 'Updated description via PATCH';
    await FarmService.updateFarm(
      farmId: farmId,
      name: newName,
      description: newDesc,
    );

    final after = await FarmService.fetchFarmProfile(farmId);
    expect(after.name, newName);
    expect(after.description, newDesc);

    // ---- Append a new photo (multipart POST) ----
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await FarmService.addFarmPhotos(
      farmId: farmId,
      photos: [XFile.fromData(pngBytes, name: 'append.png')],
    );

    final afterAppend = await FarmService.fetchFarmProfile(farmId);
    // Existing photos are preserved, and exactly one new one added.
    expect(afterAppend.photoUrls.length, originalPhotos.length + 1);
    for (final original in originalPhotos) {
      expect(
        afterAppend.photoUrls,
        contains(original),
        reason: 'append must not remove existing photos',
      );
    }
    final appended = afterAppend.photos.firstWhere(
      (p) => !originalPhotos.contains(p.url),
    );
    expect(appended.url, startsWith('https://res.cloudinary.com/'));

    // ---- Make the appended photo the cover (PUT .../primary) ----
    await FarmService.setFarmPrimaryPhoto(
      farmId: farmId,
      photoId: appended.id,
    );
    final afterCover = await FarmService.fetchFarmProfile(farmId);
    final cover = _primaryEntry(afterCover.photos);
    expect(cover?.id, appended.id,
        reason: 'the appended photo must become the cover');
    expect(afterCover.firstPhoto, appended.url,
        reason: 'the cover is the first photo in the payload');

    // ---- Delete the appended photo (DELETE .../photos/{id}) ----
    await FarmService.removeFarmPhoto(
      farmId: farmId,
      photoId: appended.id,
    );
    final afterDelete = await FarmService.fetchFarmProfile(farmId);
    expect(
      afterDelete.photoUrls,
      isNot(contains(appended.url)),
      reason: 'the appended photo must be gone',
    );
    expect(afterDelete.photoUrls.length, originalPhotos.length);

    // Removing the cover must auto-promote another photo, never leave the
    // farm with zero primaries when others remain.
    final newCover = _primaryEntry(afterDelete.photos);
    expect(newCover, isNotNull,
        reason: 'deleting the cover must promote the oldest remaining photo');

    // ---- Clean up: restore name/description and the original cover ----
    await FarmService.updateFarm(
      farmId: farmId,
      name: originalName,
      description: originalDesc,
    );
    if (originalCoverId != null && originalCoverId != newCover?.id) {
      await FarmService.setFarmPrimaryPhoto(
        farmId: farmId,
        photoId: originalCoverId,
      );
    }
    final restoredProfile = await FarmService.fetchFarmProfile(farmId);
    expect(restoredProfile.name, originalName);
    expect(restoredProfile.description, originalDesc);
    expect(restoredProfile.photoUrls.length, originalPhotos.length);
  });
}

String? _primaryId(Iterable<FarmPhotoEntry> photos) =>
    _primaryEntry(photos)?.id;

FarmPhotoEntry? _primaryEntry(Iterable<FarmPhotoEntry> photos) {
  for (final photo in photos) {
    if (photo.isPrimary) return photo;
  }
  return null;
}
