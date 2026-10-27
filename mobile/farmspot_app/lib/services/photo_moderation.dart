import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';

@immutable
class PhotoModerationResult {
  final double score;
  final int elapsedMilliseconds;

  const PhotoModerationResult({
    required this.score,
    required this.elapsedMilliseconds,
  });

  bool get allowed => score < PhotoModeration.blockThreshold;
}

/// Device-only screening; this is not server-enforced upload protection.
class PhotoModeration {
  // Reject borderline scores as well as strongly flagged photos.
  static const double blockThreshold = 0.3;

  static Future<NsfwResult?> _detect(Uint8List bytes) =>
      NsfwDetector.detectBytesInBackground(bytes, threshold: blockThreshold);

  static Future<bool> isAllowed(
    XFile photo, {
    Future<NsfwResult?> Function(Uint8List) detect = _detect,
  }) async => (await inspect(photo, detect: detect)).allowed;

  static Future<PhotoModerationResult> inspect(
    XFile photo, {
    Future<NsfwResult?> Function(Uint8List) detect = _detect,
  }) async {
    final timer = Stopwatch()..start();
    try {
      final result = await detect(await photo.readAsBytes());
      // Undecodable images and invalid scores must never silently pass.
      if (result == null ||
          !result.score.isFinite ||
          result.score < 0 ||
          result.score > 1) {
        throw StateError('Photo could not be checked');
      }
      final allowed = result.score < blockThreshold;
      if (kDebugMode) {
        // Local diagnostics only: no image data, filenames, or user identifiers.
        debugPrint(
          '[PhotoModeration] score=${result.score.toStringAsFixed(4)} '
          'threshold=$blockThreshold '
          'decision=${allowed ? 'ALLOW' : 'BLOCK'} '
          'elapsedMs=${timer.elapsedMilliseconds}',
        );
      }
      return PhotoModerationResult(
        score: result.score,
        elapsedMilliseconds: timer.elapsedMilliseconds,
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint(
          '[PhotoModeration] check failed; decision=BLOCK '
          'elapsedMs=${timer.elapsedMilliseconds}',
        );
      }
      rethrow;
    } finally {
      timer.stop();
    }
  }
}
