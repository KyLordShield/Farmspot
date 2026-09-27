import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for the signed-in user's role.
///
/// The bottom nav is the reason this exists. Every tab screen used to keep its
/// own `bool _isSeller`, default to `false`, and resolve it asynchronously in
/// `initState`. That guaranteed the wrong first frame: a buyer nav (no "My
/// Farm") painted for the length of the `GET /api/user` round trip, then
/// swapped. Tab switches used `pushReplacement`, which threw that state away
/// and repeated the whole cycle, and the screens disagreed — Home and Profile
/// hit the network while Map and Insights read only the disk cache.
///
/// [init] is awaited in `main()` before `runApp`, so the very first frame
/// already has the right role and there is no flash to correct. Screens read
/// [isSeller] synchronously during build and listen to this notifier, so
/// navigation can never re-derive it.
class SessionState extends ChangeNotifier {
  SessionState._();

  static final SessionState instance = SessionState._();

  /// Must stay in sync with the key [AuthService] writes.
  static const String userPrefsKey = 'user_data';

  Map<String, dynamic>? _user;
  bool _initialised = false;

  /// False until [init] has run. Guards against a screen reading [isSeller]
  /// before the cache is seeded.
  bool get isInitialised => _initialised;

  /// The cached user record, or null when signed out.
  Map<String, dynamic>? get user => _user;

  bool get isLoggedIn => _user != null;

  /// Whether seller mode is active (`USR_IS_SELLER == 1`).
  ///
  /// Pure and synchronous — this is the whole point. Reading the role must
  /// never involve a network round trip or an async gap, otherwise the nav
  /// flickers exactly as it used to.
  bool get isSeller {
    final v = _user?['USR_IS_SELLER'];
    if (v == null) return false;
    return v is int ? v == 1 : int.tryParse(v.toString()) == 1;
  }

  /// Seeds the in-memory role from the on-disk cache. Call once, before
  /// `runApp`, so the first build is already correct.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(userPrefsKey);
    _user = _decode(raw);
    _initialised = true;
  }

  /// Applies a user record fetched from, or written to, the cache.
  ///
  /// Only notifies when something actually changed, so a background refresh
  /// that confirms the role we already had does not rebuild the nav.
  void applyUser(Map<String, dynamic>? user) {
    final next = user == null ? null : Map<String, dynamic>.from(user);
    if (_mapsEqual(_user, next)) return;
    _user = next;
    notifyListeners();
  }

  /// Overrides just the seller flag, for when the server confirmed a toggle
  /// but we do not want to wait on a full user refetch to update the nav.
  void setSellerFlag(bool isSeller) {
    if (this.isSeller == isSeller) return;
    _user = {...?_user, 'USR_IS_SELLER': isSeller ? 1 : 0};
    notifyListeners();
  }

  /// Drops all session state on sign-out.
  void clear() {
    if (_user == null) return;
    _user = null;
    notifyListeners();
  }

  /// Test seam: seeds state without touching disk.
  void debugSetUser(Map<String, dynamic>? user) {
    _user = user == null ? null : Map<String, dynamic>.from(user);
    _initialised = true;
    notifyListeners();
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // A corrupt cache must not brick launch; treat it as signed out and let
      // the next fetch repopulate it.
      return null;
    }
  }

  static bool _mapsEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
