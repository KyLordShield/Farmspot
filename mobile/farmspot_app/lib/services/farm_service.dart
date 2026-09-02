import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/farm_setup_data.dart';
import 'auth_service.dart';

class FarmService {
  /// Creates a farm from the wizard's collected data. Never throws — returns
  /// a result map with a 'success' bool plus task-specific fields, or an
  /// error map with a user-friendly 'message'.
  static Future<Map<String, dynamic>> createFarm(FarmSetupData data) async {
    final token = await AuthService.getToken();
    if (token == null) {
      return {'success': false, 'message': 'Not logged in.'};
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.baseUrl}/farms'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      request.fields['name'] = data.name;
      request.fields['description'] = data.description;
      request.fields['barangay'] = data.barangay;
      if (data.latitude != null) {
        request.fields['latitude'] = data.latitude.toString();
      }
      if (data.longitude != null) {
        request.fields['longitude'] = data.longitude.toString();
      }

      for (final photo in data.photos) {
        final bytes = await photo.readAsBytes();
        final uploadName = _uploadFileName(photo.name, photo.path);
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos[]',
            bytes,
            filename: uploadName,
            contentType: _contentTypeFor(uploadName),
          ),
        );
      }

      final verificationDocument = data.verificationDocument;
      if (verificationDocument != null) {
        final bytes = await verificationDocument.readAsBytes();
        final uploadName = _uploadFileName(
          verificationDocument.name,
          verificationDocument.path,
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'verification_document',
            bytes,
            filename: uploadName,
            contentType: _contentTypeFor(uploadName),
          ),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final json = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          'farmId': json['farm_id'],
          'photoUrls': json['photo_urls'] ?? const <dynamic>[],
          'verificationDocumentUrl': json['verification_document_url'],
        };
      }

      if (response.statusCode == 403) {
        return {
          'success': false,
          'message': json['message'] ?? 'Seller mode not active.',
        };
      }

      if (response.statusCode == 422) {
        final errors = json['errors'];
        var message = json['message'] is String
            ? json['message'] as String
            : 'Please check your inputs.';
        if (errors is Map) {
          for (final fieldErrors in errors.values) {
            if (fieldErrors is List && fieldErrors.isNotEmpty) {
              message = fieldErrors.first.toString();
              break;
            }
          }
        }
        return {
          'success': false,
          'message': message,
          'fieldErrors': errors is Map
              ? Map<String, dynamic>.from(errors)
              : <String, dynamic>{},
        };
      }

      return {
        'success': false,
        'message':
            json['message'] ?? 'Something went wrong. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Could not reach the server. Check your connection.',
      };
    }
  }

  /// Fetches the authenticated user's own farms (GET /api/farms).
  /// Returns an empty list when not logged in or on any failure — never throws.
  static Future<List<Map<String, dynamic>>> getFarms() async {
    final token = await AuthService.getToken();
    if (token == null) return const [];

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/farms'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) return const [];

      final json = jsonDecode(response.body);
      final farms = json is Map ? json['farms'] : null;
      if (farms is! List) return const [];

      return farms
          .whereType<Map>()
          .map((farm) => Map<String, dynamic>.from(farm))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _uploadFileName(String name, String path) {
    if (name.isNotEmpty) return name;
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  static http.MediaType _contentTypeFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return http.MediaType('image', 'jpeg');
      case 'png':
        return http.MediaType('image', 'png');
      case 'webp':
        return http.MediaType('image', 'webp');
      case 'gif':
        return http.MediaType('image', 'gif');
      case 'heic':
        return http.MediaType('image', 'heic');
      case 'pdf':
        return http.MediaType('application', 'pdf');
      default:
        return http.MediaType('application', 'octet-stream');
    }
  }
}