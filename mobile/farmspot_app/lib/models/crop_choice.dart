class CropChoice {
  final String name;
  final List<String> aliases;
  const CropChoice(this.name, [this.aliases = const []]);
  factory CropChoice.fromJson(Map<String, dynamic> json) => CropChoice(
    json['name'] as String,
    (json['aliases'] as List? ?? []).cast<String>(),
  );
}

/// Suggestions only: never silently convert a buyer's text into a crop.
List<CropChoice> suggestCrops(String input, List<CropChoice> choices) {
  String clean(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final query = clean(input);
  if (query.isEmpty) return choices.take(8).toList();
  final words = input
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  int score(CropChoice choice) {
    var best = 999;
    for (final name in [choice.name, ...choice.aliases]) {
      final term = clean(name);
      if (query == term) return 0;
      if (query.length >= 2 && term.startsWith(query))
        best = best > 1 ? 1 : best;
      if (term.length >= 3 && query.contains(term)) best = best > 2 ? 2 : best;
      if (term.length >= 4) {
        for (final word in [...words, query]) {
          final distance = _editDistance(word, term);
          if (distance <= (term.length >= 8 ? 2 : 1)) {
            final value = 3 + distance;
            if (value < best) best = value;
          }
        }
      }
    }
    return best;
  }

  final matches = [for (final c in choices) (c, score(c))];
  matches.removeWhere((item) => item.$2 == 999);
  matches.sort((a, b) {
    final order = a.$2.compareTo(b.$2);
    return order == 0 ? a.$1.name.compareTo(b.$1.name) : order;
  });
  return matches.take(8).map((item) => item.$1).toList();
}

int _editDistance(String a, String b) {
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final insertion = current[j] + 1;
      final deletion = previous[j + 1] + 1;
      final substitution = previous[j] + (a[i] == b[j] ? 0 : 1);
      current[j + 1] = [
        insertion,
        deletion,
        substitution,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous.last;
}
