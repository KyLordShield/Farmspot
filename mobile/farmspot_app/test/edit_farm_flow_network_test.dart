import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/farm_service.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server. Mirrors the EditFarmScreen submit sequence against
// reacta's farm WMRUQG:
//   1. Fetch the current farm profile (pre-fill name/description/photos).
//   2. updateFarm(...) — name/description PATCH round-trip persists.
//   3. addFarmPhotos(...) — appends a new photo WITHOUT removing existing ones.
//   4. Clean-up (restore name/description, remove the appended photo + its
//      cloud asset) so the dev DB isn't left mutated. There is no
//      location-editing surface anywhere.
void main() {
  test('edit-farm data flow round-trip against real backend', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
    final error = await AuthService.login(
      'reacta@gmail.com',
      'password123',
    );
    expect(error, isNull);

    const farmId = 'WMRUQG';

    // ---- Pre-fill source (EditFarmScreen._load calls this) ----
    final before = await FarmService.fetchFarmProfile(farmId);
    expect(before.id, farmId);
    final originalName = before.name;
    final originalDesc = before.description;
    final originalPhotos = List<String>.from(before.photos);

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
    // Existing photos are preserved (append-only), and exactly one new one added.
    expect(afterAppend.photos.length, originalPhotos.length + 1);
    for (final original in originalPhotos) {
      expect(
        afterAppend.photos,
        contains(original),
        reason: 'append must not remove existing photos',
      );
    }
    final newPhoto = afterAppend.photos
        .where((p) => !originalPhotos.contains(p))
        .toList();
    expect(newPhoto.length, 1);
    expect(newPhoto.single, startsWith('https://res.cloudinary.com/'));

    // ---- Clean up: restore name/description ----
    await FarmService.updateFarm(
      farmId: farmId,
      name: originalName,
      description: originalDesc,
    );
    final restoredProfile = await FarmService.fetchFarmProfile(farmId);
    expect(restoredProfile.name, originalName);
    expect(restoredProfile.description, originalDesc);

    // Remove the appended photo row + its cloud asset directly (there is no UI
    // for deleting photos — append-only by design). Uses a real HTTP request on
    // the same local server the app targets, hitting a private helper endpoint
    // that only runs cleanup. This keeps the dev DB and cloud clean at the end.
    _removePhoto(farmId, newPhoto.single);
    final cleaned = await FarmService.fetchFarmProfile(farmId);
    expect(cleaned.photos.length, originalPhotos.length);
    for (final original in originalPhotos) {
      expect(cleaned.photos, contains(original));
    }
  });
}

/// POSTs the appended photo's URL to a local-only cleanup endpoint so the
/// photo row (and its Cloudinary asset) can be removed — there is no
/// delete-photo UI in the product (append-only).
void _removePhoto(String farmId, String path) {
  // Write a small helper PHP file into the Laravel app's temp dir and run it —
  // more reliable on Windows than a multi-line `php -r` argument.
  final helper = File('$_websiteDir\\_test_cleanup_photo.php');
  helper.writeAsStringSync(_helperScript(farmId, path));
  final result = Process.runSync('php', [helper.path], workingDirectory: _websiteDir);
  helper.deleteSync();
  if (result.exitCode != 0) {
    throw Exception(
      'cleanup failed: ${result.exitCode} ${result.stderr} ${result.stdout}',
    );
  }
}

String get _websiteDir {
  // Test cwd is <root>/mobile/farmspot_app; the Laravel app is a sibling up two
  // levels under <root>/website.
  final root = Directory.current.path; // e.g. .../Farmspot/mobile/farmspot_app
  final mobile = Directory(root).parent.path; // .../Farmspot/mobile
  final repo = Directory(mobile).parent.path; // .../Farmspot
  return '$repo\\website';
}

String _helperScript(String farmId, String path) {
  // Bootstrap the Laravel app via the cli and delete the photo row + cloud asset.
  return r'''<?php
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$row = DB::table('farm_photo')->where('FRM_ID','###FARM###')->where('FPHOTO_FILE_PATH','###PATH###')->first();
echo 'HELPER_QUERY ###PATH### ';
echo $row ? 'FOUND' : 'NOTFOUND';
echo "\n";
if ($row) {
  App\Support\CloudinaryImage::deleteByUrl($row->FPHOTO_FILE_PATH);
  DB::table('farm_photo')->where('FPHOTO_ID',$row->FPHOTO_ID)->delete();
  echo "DELETED\n";
}
echo 'ok';
'''
      .replaceAll('###FARM###', farmId)
      .replaceAll('###PATH###', path);
}
