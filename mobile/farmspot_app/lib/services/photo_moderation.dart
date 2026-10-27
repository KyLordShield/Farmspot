import 'package:cross_file/cross_file.dart';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';

/// Device-only screening; this is not server-enforced upload protection.
class PhotoModeration {
  static const double blockThreshold = 0.7;

  static Future<bool> isAllowed(XFile photo) async {
    final result = await NsfwDetector.detectBytesInBackground(
      await photo.readAsBytes(),
      threshold: blockThreshold,
    );
    // Undecodable images and invalid scores must never silently pass.
    if (result == null ||
        !result.score.isFinite ||
        result.score < 0 ||
        result.score > 1) {
      throw StateError('Photo could not be checked');
    }
    return result.score < blockThreshold;
  }
}
