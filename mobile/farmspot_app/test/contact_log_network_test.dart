import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (no testWidgets) so real network is allowed against the
// local Laravel server. Verifies the fire-and-forget contact log (Call/SMS):
// each tap inserts a contact_log row, the method is recorded, and failures are
// swallowed silently so the dialer/SMS launch is never affected.
void main() {
  Future<int> contactsMade() async {
    final token = await AuthService.getToken();
    expect(token, isNotNull);
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/user/stats'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    expect(response.statusCode, 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['contacts_made'] as num?)?.toInt() ?? 0;
  }

  test('Call and SMS each insert a contact_log row (via /user/stats)',
      () async {
    SharedPreferences.setMockInitialValues({});

    await AuthService.logout();
    final error = await AuthService.login('reacta@gmail.com', 'password123');
    expect(error, isNull);

    // Grab a real listing id from the buyer feed.
    final listings = await ListingService.fetchListings();
    expect(listings, isNotEmpty);
    final listingId = listings.first.id;
    expect(listingId, isNotEmpty);

    final before = await contactsMade();

    // Both are awaited here only so the test can assert the row landed; in the
    // app they are fired without await so the tel:/sms: launch never waits.
    await ListingService.logContact(listingId: listingId, method: 'CALL');
    await ListingService.logContact(listingId: listingId, method: 'SMS');

    final after = await contactsMade();
    expect(after, before + 2,
        reason: 'each Call/SMS tap must insert one contact_log row');
  });

  test('logContact is silent on failure (unknown listing, still returns)',
      () async {
    SharedPreferences.setMockInitialValues({});

    await AuthService.logout();
    final error = await AuthService.login('reacta@gmail.com', 'password123');
    expect(error, isNull);

    // Must not throw and must complete, even though the listing doesn't exist.
    await ListingService.logContact(listingId: 'BOGUSX', method: 'CALL');
    await ListingService.logContact(listingId: 'BOGUSX', method: 'PIGEON');
  });
}