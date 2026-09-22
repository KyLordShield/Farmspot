/// One crop found in a photo (or otherwise detected), rendered as its own
/// results section. The [title] is the English-facing name shown to buyers;
/// [terms] are every spelling the search should match (Tagalog + English
/// synonyms) so e.g. "kamatis" matches listings titled "Tomato".
class SearchCropGroup {
  const SearchCropGroup({required this.title, required this.terms});

  final String title;
  final List<String> terms;

  /// Common Tagalog <-> English crop pairings, keyed by the label the YOLO
  /// model emits (lowercased). Unknown labels pass through title-cased.
  static const Map<String, SearchCropGroup> _known = {
    'kamatis': SearchCropGroup(title: 'Tomato', terms: ['kamatis', 'tomato']),
    'repolyo': SearchCropGroup(
        title: 'Cabbage', terms: ['repolyo', 'cabbage']),
    'ampalaya': SearchCropGroup(
        title: 'Bitter gourd',
        terms: ['ampalaya', 'bitter gourd', 'bitter melon']),
    'pipino': SearchCropGroup(
        title: 'Cucumber', terms: ['pipino', 'cucumber']),
    'sayote': SearchCropGroup(
        title: 'Chayote', terms: ['sayote', 'chayote']),
    'sitaw': SearchCropGroup(
        title: 'String beans',
        terms: ['sitaw', 'string beans', 'yardlong bean']),
    'bataw': SearchCropGroup(
        title: 'Hyacinth bean',
        terms: ['bataw', 'hyacinth bean']),
    'sili': SearchCropGroup(
        title: 'Chili', terms: ['sili', 'chili', 'chilli']),
    'pechay': SearchCropGroup(
        title: 'Bok choy', terms: ['pechay', 'bok choy', 'pak choi']),
  };

  /// Builds the search group for a detected label: known labels use their
  /// English pairing, anything else is shown title-cased and searched as-is.
  static SearchCropGroup resolve(String label) {
    final key = label.trim().toLowerCase();
    final known = _known[key];
    if (known != null) return known;
    final t = label.trim();
    return SearchCropGroup(
      title: t.isEmpty ? t : t[0].toUpperCase() + t.substring(1),
      terms: [t],
    );
  }
}