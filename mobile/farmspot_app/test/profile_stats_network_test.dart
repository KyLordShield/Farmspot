import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/farm_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (no testWidgets) so real network is allowed against the
// local Laravel server. Proves AuthService.fetchUserStats() — the exact call
// the Profile screen's stats row uses — returns real counts that move when the
// user generates activity: +1 per search, +1 per farm visit, +1 per contact.
void main() {
  test('fetchUserStats reflects real search/visit/contact activity', () async {
    SharedPreferences.setMockInitialValues({});

    await AuthService.logout();
    final error = await AuthService.login('reacta@gmail.com', 'password123');
    expect(error, isNull);

    final before = await AuthService.fetchUserStats();
    expect(before, isNotNull);
    expect(before!['searches'], isA<int>());
    expect(before['farms_visited'], isA<int>());
    expect(before['contacts_made'], isA<int>());

    final token = await AuthService.getToken();
    expect(token, isNotNull);

    // +1 search: GET /listings?search= with a valid token logs a row.
    final searchResp = await http.get(
      Uri.parse('${AuthService.baseUrl}/listings?search=carrot'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    expect(searchResp.statusCode, 200);

    // +1 farm visit: fire-and-forget visit log.
    await FarmService.logFarmVisit('QUAOMR');

    // +1 contact: log a CALL against a real listing from the feed.
    final listings = await ListingService.fetchListings();
    expect(listings, isNotEmpty);
    await ListingService.logContact(
      listingId: listings.first.id,
      method: 'CALL',
    );

    final after = await AuthService.fetchUserStats();
    expect(after, isNotNull);
    expect(after!['searches'], before['searches'] + 1);
    expect(after['farms_visited'], before['farms_visited'] + 1);
    expect(after['contacts_made'], before['contacts_made'] + 1);
  });
}