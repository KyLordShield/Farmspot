import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;

import '../models/farm_profile.dart';
import '../models/farm_setup_data.dart';
import '../models/farm_stats.dart';
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
          'frm_status': json['frm_status'] ?? 'APPROVED',
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

  /// Fetches a farm's public profile (GET /api/farms/{id}/profile) — the
  /// farm's details + photos plus ALL of its listings (any status, ordered by
  /// status priority). Public route, no token needed. Throws an Exception with
  /// a user-friendly message on failure (matching ListingService's convention).
  static Future<FarmProfileData> fetchFarmProfile(String farmId) async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse('${AuthService.baseUrl}/farms/$farmId/profile'),
        headers: {'Accept': 'application/json'},
      );
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 404) {
      throw Exception('Farm not found.');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to load farm profile.');
    }

    final json = jsonDecode(response.body);
    return FarmProfileData.fromJson(json as Map<String, dynamic>);
  }

  /// Fetches the authenticated seller's own farm performance totals
  /// (GET /api/farms/{id}/stats, auth + ownership required). Same error-handling
  /// pattern as [fetchFarmProfile]: throws an Exception with a user-friendly
  /// message on failure.
  static Future<FarmStats> fetchFarmStats(String farmId) async {
    final token = await AuthService.getToken();
    if (token == null) {
      throw Exception('Not logged in.');
    }

    http.Response response;
    try {
      response = await http.get(
        Uri.parse('${AuthService.baseUrl}/farms/$farmId/stats'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 404) {
      throw Exception('Farm not found.');
    }
    if (response.statusCode == 403) {
      throw Exception('You do not own this farm.');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to load farm stats.');
    }

    final json = jsonDecode(response.body);
    return FarmStats.fromJson(json as Map<String, dynamic>);
  }

  /// Logs a farm-profile visit for the currently logged-in user
  /// (POST /api/farms/{id}/log-visit). Fire-and-forget by design: silently a
  /// no-op when not logged in, and failed visits never block or surface in the
  /// UI — a failed visit log must not affect the buyer's experience.
  static Future<void> logFarmVisit(String farmId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return;

      await http.post(
        Uri.parse('${AuthService.baseUrl}/farms/$farmId/log-visit'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    } catch (_) {
      // Ignored by design.
    }
  }

  /// Fetches the authenticated user's own farms (GET /api/farms).
  /// Returns an empty list when not logged in or on any failure — never throws.
  static Future<List<Map<String, dynamic>>> getFarms() async {    final token = await AuthService.getToken();
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

  /// Edits the authenticated seller's own farm (PATCH /api/farms/{id}).
  /// JSON-only — only the provided fields are sent, an absent one is left
  /// untouched on the server. Location is locked post-approval and is never
  /// sent here (the endpoint rejects any non-empty location field). Returns
  /// normally on success, or throws an Exception carrying a user-friendly
  /// message, matching this file's fetchFarmProfile/fetchFarmStats convention.
  static Future<void> updateFarm({
    required String farmId,
    String? name,
    String? description,
  }) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Not logged in.');

    http.Response response;
    try {
      response = await http.patch(
        Uri.parse('${AuthService.baseUrl}/farms/$farmId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: {
          // Only fields explicitly provided (non-null) are sent — an absent
          // one is left untouched. An empty string is still sent so a caller
          // can deliberately clear the description back to blank.
          if (name != null) 'name': name.trim(),
          if (description != null) 'description': description.trim(),
        },
      );
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    _throwForError(response, 'Update farm failed.');
  }

  /// Appends new photos to the authenticated seller's own farm
  /// (POST /api/farms/{id}/photos). This is a separate call from the JSON
  /// PATCH because PHP only parses multipart uploads on POST — the same
  /// bytes-based MultipartFile.fromBytes() pattern the farm wizard uses.
  /// Existing photos are never removed (append-only). Returns normally on
  /// success, or throws an Exception with a user-friendly message.
  static Future<void> addFarmPhotos({
    required String farmId,
    required List<XFile> photos,
  }) async {
    if (photos.isEmpty) return;
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Not logged in.');

    http.Response response;
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.baseUrl}/farms/$farmId/photos'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      for (final photo in photos) {
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

      final streamed = await request.send();
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    _throwForError(response, 'Add farm photos failed.');
  }

  /// Shared failure handling for the farm PATCH / photo-append endpoints:
  /// 403/404/422 map to their messages, else the fallback — throws an
  /// Exception so callers get a friendly message (never a raw http code).
  static void _throwForError(http.Response response, String fallback) {
    if (response.statusCode == 200) return;

    dynamic json;
    try {
      json = jsonDecode(response.body);
    } catch (_) {
      json = null;
    }
    final message = json is Map && json['message'] is String
        ? json['message'] as String
        : null;

    if (response.statusCode == 403) {
      throw Exception(message ?? 'You do not own this farm.');
    }
    if (response.statusCode == 404) {
      throw Exception(message ?? 'Farm not found.');
    }
    if (response.statusCode == 422) {
      final errors = json is Map ? json['errors'] : null;
      if (errors is Map) {
        for (final fieldErrors in errors.values) {
          if (fieldErrors is List && fieldErrors.isNotEmpty) {
            throw Exception(fieldErrors.first.toString());
          }
        }
      }
      throw Exception(message ?? 'Please check your inputs.');
    }

    throw Exception(message ?? fallback);
  }

  static String _uploadFileName(String name, String path) {
    if (name.isNotEmpty) return name;
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isNotEmpty) {
      final fromPath = normalized.substring(normalized.lastIndexOf('/') + 1);
      if (fromPath.isNotEmpty) return fromPath;
    }
    // XFile.fromData/web pickers can yield an empty name AND empty path —
    // without a real filename Laravel won't treat the part as a file upload,
    // so the backend's "photos" field would appear missing entirely.
    return 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
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