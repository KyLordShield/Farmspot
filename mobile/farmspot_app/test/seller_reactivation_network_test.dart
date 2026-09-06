import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/farm_service.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server + real MySQL DB. Drives the exact "Become a Seller"
// toggle flow the Profile screen uses (AuthService.activateSeller /
// deactivateSeller + FarmService.getFarms) and asserts the Case A / Case B
// server decision against real rows.
//
// DB fixtures (pre-seeded via an artisan script; password123 for both):
//   reacta@gmail.com — APPROVED farm, seller flags ON (start of Scenario 2)
//   reactb@gmail.com — REJECTED farm only, flags OFF (Scenario 3)
// Scenario 1 registers its own brand-new account (no Buyer/Farmer rows).
void main() {
  test('Case B: fresh account, never a seller -> wizard, flags stay off',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final error = await AuthService.register(
      name: 'Fresh React',
      email: 'fresh$suffix@gmail.com',
      password: 'password123',
      passwordConfirmation: 'password123',
      mobileNumber: '0917${(suffix % 100000000).toString().padLeft(8, '0')}',
    );
    expect(error, isNull, reason: 'register fresh account');

    final result = await AuthService.activateSeller();

    expect(result.error, isNull);
    expect(result.reactivated, isFalse,
        reason: 'no farm anywhere -> Case B -> wizard');
    expect(await AuthService.isSeller(), isFalse,
        reason: 'USR_IS_SELLER must stay 0 until farm approval');
    expect(await FarmService.getFarms(), isEmpty,
        reason: 'no farm rows created for a first-timer');
  });

  test('Case A: approved seller deactivate -> reactivate -> flags restored, '
      'farm untouched', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
    final loginError = await AuthService.login('reacta@gmail.com', 'password123');
    expect(loginError, isNull);
    await AuthService.fetchUser();

    // Fixture pre-state (idempotent even after a half-failed prior run left
    // the account deactivated): approved farm + seller flags ON.
    if (!await AuthService.isSeller()) {
      final restore = await AuthService.activateSeller();
      expect(restore.error, isNull);
      expect(restore.reactivated, isTrue,
          reason: 'approved farm must always reactivate instantly');
    }
    expect(await AuthService.isSeller(), isTrue);
    final before = await FarmService.getFarms();
    expect(before.where((f) => f['FRM_STATUS'] == 'APPROVED'), isNotEmpty);

    // Bug repro step 1: deactivation works — flags drop, farm stays APPROVED.
    expect(await AuthService.deactivateSeller(), isNull);
    await AuthService.fetchUser();
    expect(await AuthService.isSeller(), isFalse,
        reason: 'seller mode must be off after deactivate');
    final whileOff = await FarmService.getFarms();
    expect(whileOff.where((f) => f['FRM_STATUS'] == 'APPROVED'), isNotEmpty,
        reason: 'deactivate must NOT touch FRM_STATUS');

    // Bug repro step 2 (THE FIX): "Become a Seller" again immediately
    // reactivates — no wizard, flags are back on.
    final result = await AuthService.activateSeller();
    expect(result.error, isNull);
    expect(result.reactivated, isTrue,
        reason: 'APPROVED farm present -> instant reactivation route');
    await AuthService.fetchUser();
    expect(await AuthService.isSeller(), isTrue,
        reason: 'USR_IS_SELLER flipped back to 1');

    // Nothing was re-created or re-reviewed: same farm, still APPROVED.
    final after = await FarmService.getFarms();
    expect(after.map((f) => f['FRM_ID']), before.map((f) => f['FRM_ID']),
        reason: 'same farm rows survive the deactivate/reactivate cycle');
    expect(after.where((f) => f['FRM_STATUS'] == 'APPROVED'), isNotEmpty);
  });

  test('Case B: only REJECTED/PENDING_REVIEW farm -> NOT instant-reactivated',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
    final loginError = await AuthService.login('reactb@gmail.com', 'password123');
    expect(loginError, isNull);
    await AuthService.fetchUser();

    expect(await AuthService.isSeller(), isFalse);
    expect((await FarmService.getFarms()).first['FRM_STATUS'], 'REJECTED');

    final result = await AuthService.activateSeller();

    expect(result.error, isNull);
    expect(result.reactivated, isFalse,
        reason: 'no APPROVED farm -> Case B -> wizard, never instant approval');
    await AuthService.fetchUser();
    expect(await AuthService.isSeller(), isFalse,
        reason: 'REJECTED/PENDING farm grants NO seller flags');
    expect((await FarmService.getFarms()).first['FRM_STATUS'], 'REJECTED');
  });
}