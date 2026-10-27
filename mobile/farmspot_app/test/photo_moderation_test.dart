import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:farmspot_app/services/photo_moderation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';

void main() {
  final photo = XFile.fromData(Uint8List.fromList([1, 2, 3]));

  Future<bool> checkScore(double score) => PhotoModeration.isAllowed(
    photo,
    detect: (_) async =>
        NsfwResult(isNsfw: score >= 0.7, score: score, safeScore: 1 - score),
  );

  test(
    'blocks borderline images previously allowed by the 0.70 cutoff',
    () async {
      expect(await checkScore(0.55), isFalse);
      expect(await checkScore(0.69), isFalse);
      expect(await checkScore(0.95), isFalse);
    },
  );

  test(
    'allows low scores and blocks exactly at the stricter boundary',
    () async {
      expect(await checkScore(0.0), isTrue);
      expect(await checkScore(0.2999), isTrue);
      expect(await checkScore(0.3), isFalse);
      expect(await checkScore(0.4), isFalse);
      expect(await checkScore(1.0), isFalse);
    },
  );

  test(
    'reported scores demonstrate the limits of the 0.30 trial cutoff',
    () async {
      expect(await checkScore(0.3260), isFalse);
      expect(await checkScore(0.0831), isTrue);
    },
  );

  test('undecodable images cannot receive an allow decision', () async {
    await expectLater(
      PhotoModeration.isAllowed(photo, detect: (_) async => null),
      throwsStateError,
    );
  });

  test('invalid model scores fail the check', () async {
    for (final score in [double.nan, double.infinity, -0.1, 1.1]) {
      await expectLater(checkScore(score), throwsStateError);
    }
  });

  test('inference failures propagate for the upload gate to reject', () async {
    await expectLater(
      PhotoModeration.isAllowed(
        photo,
        detect: (_) async => throw StateError('Model unavailable'),
      ),
      throwsStateError,
    );
  });
}
