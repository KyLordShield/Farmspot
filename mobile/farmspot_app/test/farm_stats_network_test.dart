import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/farm_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (no testWidgets) so real network is allowed against the
// local Laravel server. Proves GET /api/farms/{id}/stats — surfaced on
// MyFarmScreen via FarmService.fetchFarmStats() — counts the farm OWNER's real
// rows (farm_visit_log rows for the farm, contact_log rows for listings on the
// farm, active listings), and that ownership is enforced (403 for non-owners).
// Assertions are delta-based so they stay correct across repeated runs that
// accumulate rows.
void main() {
  test('farm stats reflect real visit/contact/listing activity for the owner',
      () async {
    SharedPreferences.setMockInitialValues({});

    // reacta is an approved seller who owns WMRUQG ("React Test A's Farm").
    await AuthService.logout();
    final error = await AuthService.login('reacta@gmail.com', 'password123');
    expect(error, isNull);

    final before = await FarmService.fetchFarmStats('WMRUQG');
    expect(before.profileViews, greaterThanOrEqualTo(0));
    expect(before.buyerContacts, greaterThanOrEqualTo(0));
    expect(before.activeListings, greaterThanOrEqualTo(0));

    // +1 active listing: create a real AVAILABLE_NOW listing on the owner's farm.
    final categories = await ListingService.fetchCropCategories();
    expect(categories, isNotEmpty);
    final token = await AuthService.getToken();
    final create = await http.post(
      Uri.parse('${AuthService.baseUrl}/listings'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: {
        'farm_id': 'WMRUQG',
        'category_id': categories.first.id,
        'crop_icon': 'carrot',
        'status': 'AVAILABLE_NOW',
      },
    );
    expect(create.statusCode, 201, reason: create.body);
    final created = jsonDecode(create.body) as Map<String, dynamic>;
    final listingId = (created['listing'] as Map<String, dynamic>)['id'] as String;
    expect(listingId, isNotEmpty);

    final mid = await FarmService.fetchFarmStats('WMRUQG');
    expect(mid.activeListings, before.activeListings + 1,
        reason: 'creating an AVAILABLE_NOW listing bumps Active Listings');
    expect(mid.buyerContacts, before.buyerContacts);
    expect(mid.profileViews, before.profileViews);

    // Switch to a plain buyer (reactb) — NOT the owner.
    await AuthService.logout();
    final buyerError =
        await AuthService.login('reactb@gmail.com', 'password123');
    expect(buyerError, isNull);

    // Ownership enforced: a non-owner gets 403 -> friendly Exception.
    expect(
      FarmService.fetchFarmStats('WMRUQG'),
      throwsA(
        predicate<Exception>(
          (e) => e.toString().contains('You do not own this farm.'),
        ),
      ),
    );

    // Unknown farm -> 404 -> friendly Exception.
    expect(
      FarmService.fetchFarmStats('NOPE!!'),
      throwsA(
        predicate<Exception>((e) => e.toString().contains('Farm not found.')),
      ),
    );

    // Reactb browses reacta's farm: one real visit + one real contact. Awaited
    // here only so the test can assert; the app fires these without await.
    await FarmService.logFarmVisit('WMRUQG');
    await ListingService.logContact(listingId: listingId, method: 'CALL');

    // Back to the owner; both owner counts moved by exactly +1.
    await AuthService.logout();
    final ownerError =
        await AuthService.login('reacta@gmail.com', 'password123');
    expect(ownerError, isNull);

    final after = await FarmService.fetchFarmStats('WMRUQG');
    expect(after.profileViews, mid.profileViews + 1,
        reason: 'a buyer opening the farm profile adds one profile view');
    expect(after.buyerContacts, mid.buyerContacts + 1,
        reason: 'a buyer contacting a listing on the farm adds one contact');
    expect(after.activeListings, mid.activeListings,
        reason: 'contacts/visits never change the active-listings count');
  });
}