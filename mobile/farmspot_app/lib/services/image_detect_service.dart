import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cross_file/cross_file.dart';

/// Talks to the Python YOLO service (ml_service/app.py).
class ImageDetectService {
  static const String _baseUrl = 'http://127.0.0.1:8001';

  /// Sends a photo, returns the most-confident crop guess with its confidence,
  /// or null if nothing confident was found (or the service is unreachable).
  static Future<DetectedCrop?> detectCrop(XFile photo) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/detect'),
    );
    request.files.add(
      await http.MultipartFile.fromPath('file', photo.path, filename: 'crop.jpg'),
    );

    try {
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final detections = (data['detections'] as List<dynamic>?) ?? [];
      if (detections.isEmpty) return null;

      // YOLO can return several guesses — trust the strongest.
      detections.sort((a, b) =>
          (b['confidence'] as num).compareTo(a['confidence'] as num));
      return DetectedCrop(
        name: detections.first['name'] as String,
        confidence: (detections.first['confidence'] as num).toDouble(),
      );
    } catch (_) {
      return null; // connection refused, Python not running, etc.
    }
  }
}

/// One confident crop guess from the model.
class DetectedCrop {
  DetectedCrop({required this.name, required this.confidence});

  final String name;
  final double confidence;
}