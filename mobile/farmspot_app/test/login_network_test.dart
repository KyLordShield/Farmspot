import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server. Verifies the fixed login path: after logout + login,
// login() fetches the authoritative user via GET /api/user, so isSeller() is
// true immediately afterwards for an approved seller (no Profile visit needed).
void main() {
  test('logout -> login -> isSeller = true for approved seller (real network)',
      () async {
    SharedPreferences.setMockInitialValues({});

    await AuthService.logout();

    final error = await AuthService.login(
      'libando@gmail.com',
      'password123',
    );
    expect(error, isNull);

    final result = await AuthService.isSeller();
    expect(result, true);
  });
}
