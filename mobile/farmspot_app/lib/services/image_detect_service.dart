import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cross_file/cross_file.dart';

/// Talks to the Python YOLO service (ml_service/app.py).
class ImageDetectService {
  static const String _baseUrl = 'http://127.0.0.1:8001';

  /// Sends a photo and returns every crop the model found in it (multiple
  /// crops per image are expected), each with its confidence. One entry per
  /// unique crop name — the best-scoring box wins. Empty list if nothing
  /// confident was found (or the service is unreachable).
  static Future<List<DetectedCrop>> detectCrops(XFile photo) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/detect'),
    );
    request.files.add(
      await http.MultipartFile.fromPath('file', photo.path, filename: 'crop.jpg'),
    );

    try {
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode != 200) return const [];

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
      return const []; // connection refused, Python not running, etc.
    }
  }
}

/// One confident crop guess from the model.
class DetectedCrop {
  DetectedCrop({required this.name, required this.confidence});

  final String name;
  final double confidence;
}