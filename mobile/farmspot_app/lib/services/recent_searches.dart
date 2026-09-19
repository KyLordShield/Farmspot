import 'package:shared_preferences/shared_preferences.dart';

/// Stores the buyer's recent real search terms on the device only
/// (shared_preferences). Explicitly NOT a backend concern — this never touches
/// search_log or the analytics feature in any way.
class RecentSearches {
  static const _key = 'recent_searches';

  /// Most recent first, capped at this many entries.
  static const int maxEntries = 5;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  /// Puts [term] at the front. Duplicates (case-insensitive) are removed so a
  /// term appears once; the newest casing wins. Older entries beyond the cap
  /// are dropped.
  static Future<void> add(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_key) ?? <String>[];
    entries.removeWhere((e) => e.toLowerCase() == trimmed.toLowerCase());
    entries.insert(0, trimmed);
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    await prefs.setStringList(_key, entries);
  }
}