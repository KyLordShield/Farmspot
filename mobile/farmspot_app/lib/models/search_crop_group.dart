/// One crop found in a photo (or otherwise detected), rendered as its own
/// results section. The [title] is the English-facing name shown to buyers;
/// [terms] are every spelling the search should match (Tagalog + English
/// synonyms) so e.g. "kamatis" matches listings titled "Tomato".
class SearchCropGroup {
  const SearchCropGroup({
    required this.title,
    required this.terms,
    this.yoloClass,
  });

  final String title;
  final List<String> terms;

  /// Index of the detecting model's class, when this group is one the model
  /// can actually produce. Lets callers match on a stable integer instead of
  /// on spelling, so renaming a term can never break detection.
  final int? yoloClass;

  /// Lowercases and drops every character that is not a letter or digit, so
  /// "Bok Choy", "bok_choy", "bok-choy" and "BOKCHOY" all collapse to the same
  /// key. Without this, a seller who typed "bokchoy" was invisible to a group
  /// whose terms only listed "bok choy".
  static String normalize(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Common Tagalog <-> English crop pairings, keyed by the NORMALIZED label
  /// the model emits. Keep the key normalized, but write the terms however a
  /// real seller is likely to type them - terms are matched with SQL LIKE, so
  /// they need the spacing people actually use.
  static const Map<String, SearchCropGroup> _known = {
    'kamatis': SearchCropGroup(
        title: 'Tomato',
        terms: ['kamatis', 'tomato', 'tomatoes'],
        yoloClass: 0),
    'tomato': SearchCropGroup(
        title: 'Tomato',
        terms: ['tomato', 'tomatoes', 'kamatis'],
        yoloClass: 0),
    'lettuce': SearchCropGroup(
        title: 'Lettuce',
        terms: ['lettuce', 'letchuce'],
        yoloClass: 1),
    'cabbage': SearchCropGroup(
        title: 'Cabbage',
        terms: ['cabbage', 'repolyo'],
        yoloClass: 2),
    'cucumber': SearchCropGroup(
        title: 'Cucumber',
        terms: ['cucumber', 'pipino'],
        yoloClass: 3),
    'chili': SearchCropGroup(
        title: 'Chili',
        terms: [
          'chili',
          'chilli',
          'chili pepper',
          'chilipepper',
          'sili'
        ],
        yoloClass: 4),
    'chilli': SearchCropGroup(
        title: 'Chili',
        terms: ['chilli', 'chili', 'sili'],
        yoloClass: 4),
    'sili': SearchCropGroup(
        title: 'Chili', terms: ['sili', 'chili', 'chilli'], yoloClass: 4),
    'greenbean': SearchCropGroup(
        title: 'Green beans',
        terms: [
          'green beans',
          'greenbean',
          'green bean',
          'string beans',
          'sitaw',
          'yardlong bean'
        ],
        yoloClass: 5),
    'chayote': SearchCropGroup(
        title: 'Chayote', terms: ['chayote', 'sayote'], yoloClass: 6),
    'sayote': SearchCropGroup(
        title: 'Chayote', terms: ['sayote', 'chayote'], yoloClass: 6),
    'bokchoy': SearchCropGroup(
        title: 'Bok choy',
        terms: ['bok choy', 'bokchoy', 'pechay', 'pak choi', 'pakchoi'],
        yoloClass: 7),
    'pechay': SearchCropGroup(
        title: 'Bok choy',
        terms: [
          'pechay',
          'bok choy',
          'bokchoy',
          'pak choi',
          'pakchoi'
        ],
        yoloClass: 7),

    // Retained so older/hand-typed labels and the not-yet-trained crops keep
    // resolving exactly as they did before.
    'repolyo': SearchCropGroup(
        title: 'Cabbage', terms: ['repolyo', 'cabbage'], yoloClass: 2),
    'ampalaya': SearchCropGroup(
        title: 'Bitter gourd',
        terms: ['ampalaya', 'bitter gourd', 'bitter melon']),
    'pipino': SearchCropGroup(
        title: 'Cucumber', terms: ['pipino', 'cucumber'], yoloClass: 3),
    // Display name deliberately stays "String beans" rather than being merged
    // into "Green beans": sitaw/yardlong is what sellers here call it, and
    // changing the heading would alter existing single-crop searches.
    'sitaw': SearchCropGroup(
        title: 'String beans',
        terms: [
          'sitaw',
          'string beans',
          'stringbeans',
          'yardlong bean',
          'green beans'
        ],
        yoloClass: 5),
    'swordbean': SearchCropGroup(
        title: 'Sword bean',
        terms: [
          'sword bean',
          'swordbean',
          'bataw',
          'hyacinth bean',
          'hyacinthbean'
        ]),
    'bataw': SearchCropGroup(
        title: 'Hyacinth bean',
        terms: [
          'bataw',
          'hyacinth bean',
          'hyacinthbean',
          'sword bean'
        ]),
    'squash': SearchCropGroup(
        title: 'Squash', terms: ['squash', 'kalabasa']),
  };

  /// Builds the search group for a detected label. Known labels use their
  /// English pairing, anything else is shown title-cased and searched as-is.
  /// Lookup is normalized, so "Bok_Choy", "bokchoy" and "bok choy" all land on
  /// the same group.
  static SearchCropGroup resolve(String label) {
    final key = normalize(label);
    final known = _known[key];
    if (known != null) return known;

    final t = label.trim();
    return SearchCropGroup(
      title: t.isEmpty ? t : t[0].toUpperCase() + t.substring(1),
      terms: [t],
    );
  }

  /// True when [label] normalizes onto the same thing as [other]. Used by tests
  /// and by anything that needs spelling-insensitive comparison.
  static bool sameCrop(String a, String b) => normalize(a) == normalize(b);
}