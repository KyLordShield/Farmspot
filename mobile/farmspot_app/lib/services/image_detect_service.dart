import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:cross_file/cross_file.dart';

import 'api_config.dart';

/// How long one scan may take end to end.
///
/// Long enough to cover the detector waking up from cold (the service sleeps
/// when idle, and waking it costs roughly 40s) plus the inference itself, and
/// short enough that the user is not left staring at the spinner for minutes.
const Duration _detectTimeout = Duration(seconds: 90);

/// Talks to the Python YOLO service (ml_service/app.py).
class ImageDetectService {
  static final String _baseUrl = ApiConfig.imageDetectBaseUrl;

  /// Sends a photo and returns every crop the model found in it (multiple
  /// crops per image are expected), each with its confidence. One entry per
  /// unique crop name — the best-scoring box wins.
  ///
  /// An empty list means the service answered normally and found nothing
  /// confident — i.e. "this is not a crop photo". It does NOT mean "the scan
  /// failed": failure is reported by throwing [ImageDetectException], so the
  /// caller can tell the two apart instead of telling the user to retake a
  /// photo that was perfectly fine.
  static Future<List<DetectedCrop>> detectCrops(XFile photo) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/detect'),
    );
    request.headers['Accept'] = 'application/json';
    request.files.add(
      await http.MultipartFile.fromPath('file', photo.path, filename: 'crop.jpg'),
    );

    final http.Response response;
    try {
      response = await _send(request).timeout(_detectTimeout);
    } on TimeoutException {
      throw ImageDetectException(
        'The crop scanner is taking too long to answer. Please try again.',
      );
    } catch (_) {
      // Connection refused, DNS failure, TLS problem, connection reset mid
      // upload — anything below the HTTP layer.
      throw ImageDetectException(
        'Could not reach the crop scanner. Check your connection and try again.',
      );
    }

    if (response.statusCode != 200) {
      throw ImageDetectException(
        'The crop scanner is unavailable right now '
        '(error ${response.statusCode}). Try again in a few minutes.',
      );
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final detections = (data['detections'] as List<dynamic>?) ?? [];

      // Fold many boxes into one entry per crop name, keeping the strongest
      // confidence. The backend already filters to real crops (class 0).
      final bestByName = <String, DetectedCrop>{};
      for (final d in detections) {
        final name = d['name'] as String;
        final confidence = (d['confidence'] as num).toDouble();
        final existing = bestByName[name];
        if (existing == null || confidence > existing.confidence) {
          bestByName[name] = DetectedCrop(name: name, confidence: confidence);
        }
      }

      final crops = bestByName.values.toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      return crops;
    } catch (_) {
      // A 200 that is not the documented JSON shape is a broken service, not
      // "no crop here" — the two must not be reported to the user alike.
      throw ImageDetectException(
        'The crop scanner sent an unexpected response. Please try again.',
      );
    }
  }

  /// Uploads [request] and reads its body, so the caller can put one timeout
  /// around the whole exchange — upload, server-side inference and download.
  static Future<http.Response> _send(http.MultipartRequest request) async {
    final streamed = await request.send();
    return http.Response.fromStream(streamed);
  }
}

/// The scan could not be completed: the service was unreachable, timed out,
/// answered with an error, or answered with something unreadable.
///
/// Carries the sentence to show the user. It is deliberately not an HTTP or
/// socket detail — the screen just displays [message].
class ImageDetectException implements Exception {
  ImageDetectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One confident crop guess from the model.
class DetectedCrop {
  DetectedCrop({required this.name, required this.confidence});

  final String name;
  final double confidence;
}
