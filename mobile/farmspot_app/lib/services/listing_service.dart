import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;

import '../models/crop_category.dart';
import '../models/listing.dart';
import 'auth_service.dart';

class ListingService {
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  /// Fetches the browse feed. Returns the list on success, or throws
  /// an Exception with a user-friendly message on failure.
  static Future<List<Listing>> fetchListings({String? search}) async {
    try {
      final uri = Uri.parse('$baseUrl/listings').replace(
        queryParameters: (search != null && search.trim().isNotEmpty)
            ? {'search': search.trim()}
            : null,
      );
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final listings = data['listings'] as List;
        return listings
            .map((json) => Listing.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Failed to load listings.');
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  /// Fetches a single listing's detail by ID.
  static Future<Listing> fetchListing(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/listings/$id'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Listing.fromJson(data['listing'] as Map<String, dynamic>);
      }

      throw Exception('Listing not found.');
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  /// Fetches all crop categories (GET /api/crop-categories). Public endpoint.
  /// Returns the list on success, or throws an Exception on failure.
  static Future<List<CropCategory>> fetchCropCategories() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/crop-categories'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final categories = data['categories'] as List;
        return categories
            .map((json) => CropCategory.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Failed to load crop categories.');
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  /// Fetches the authenticated farmer's OWN listings (GET /api/my-listings) —
  /// any status/availability, unlike the buyer feed. Requires a token.
  /// Returns the list on success, or throws an Exception on failure.
  static Future<List<Listing>> fetchMyListings() async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Not logged in.');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/my-listings'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final listings = data['listings'] as List;
        return listings
            .map((json) => Listing.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Failed to load your listings.');
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  /// Creates a new listing (POST /api/listings). When [photo] is provided it is
  /// sent as multipart/form-data via MultipartFile.fromBytes() (byte-based, so
  /// it works identically on web and mobile — .fromPath() does not on web).
  /// Returns the created Listing on success, or throws an Exception carrying a
  /// user-friendly message (e.g. 403 "Farm not found or does not belong to
  /// you." from Laravel, or the first 422 field error).
  static Future<Listing> createListing({
    required String farmId,
    required String categoryId,
    required String status,
    String? cropIcon,
    DateTime? harvestDate,
    XFile? photo,
  }) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Not logged in.');

    http.Response response;
    try {
      if (photo != null) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/listings'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'application/json';

        request.fields['farm_id'] = farmId;
        request.fields['category_id'] = categoryId;
        request.fields['status'] = status;
        if (cropIcon != null && cropIcon.trim().isNotEmpty) {
          request.fields['crop_icon'] = cropIcon.trim();
        }
        if (harvestDate != null) {
          request.fields['harvest_date'] = _dateOnly(harvestDate);
        }

        final bytes = await photo.readAsBytes();
        final uploadName = _uploadFileName(photo.name, photo.path);
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: uploadName,
            contentType: _contentTypeFor(uploadName),
          ),
        );

        final streamed = await request.send();
        response = await http.Response.fromStream(streamed);
      } else {
        response = await http.post(
          Uri.parse('$baseUrl/listings'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: {
            'farm_id': farmId,
            'category_id': categoryId,
            'status': status,
            if (cropIcon != null && cropIcon.trim().isNotEmpty)
              'crop_icon': cropIcon.trim(),
            if (harvestDate != null) 'harvest_date': _dateOnly(harvestDate),
          },
        );
      }
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    return _listingResult(response, 'Create listing failed.');
  }

  /// Updates just the LST_STATUS of one of the farmer's own listings
  /// (PATCH /api/listings/{id}/status). Returns the updated Listing on success,
  /// or throws an Exception carrying a user-friendly message.
  static Future<Listing> updateListingStatus({
    required String listingId,
    required String status,
  }) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception('Not logged in.');

    http.Response response;
    try {
      response = await http.patch(
        Uri.parse('$baseUrl/listings/$listingId/status'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: {'status': status},
      );
    } catch (e) {
      throw Exception('Could not reach the server. Check your connection.');
    }

    return _listingResult(response, 'Update listing status failed.');
  }

  /// Parses the {message, listing} shape returned by create/update and throws
  /// a user-friendly Exception for non-success status codes (mirroring this
  /// file's throw-on-failure convention).
  static Listing _listingResult(http.Response response, String fallback) {
    dynamic json;
    try {
      json = jsonDecode(response.body);
    } catch (_) {
      json = null;
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final listing = json is Map ? json['listing'] : null;
      if (listing is Map<String, dynamic>) {
        return Listing.fromJson(listing);
      }
      throw Exception('Unexpected response from the server.');
    }

    final message = json is Map && json['message'] is String
        ? json['message'] as String
        : null;

    if (response.statusCode == 403) {
      throw Exception(message ?? 'You do not have access to this farm.');
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

  static String _dateOnly(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _uploadFileName(String name, String path) {
    if (name.trim().isNotEmpty) return name;
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isNotEmpty) {
      final fromPath = normalized.substring(normalized.lastIndexOf('/') + 1);
      if (fromPath.isNotEmpty) return fromPath;
    }
    // XFile.fromData/web pickers can yield an empty name AND empty path —
    // without a real filename Laravel won't treat the part as a file upload.
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
      default:
        return http.MediaType('application', 'octet-stream');
    }
  }
}