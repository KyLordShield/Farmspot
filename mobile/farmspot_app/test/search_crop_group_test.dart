import 'package:farmspot_app/models/search_crop_group.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simulates what Laravel does with a search term:
/// `WHERE LST_CROP_ICON LIKE '%term%'`
/// A listing whose seller typed [sellerTyped] is only found if some term in the
/// group appears inside it.
bool likeMatches(String haystack, String needle) =>
    haystack.toLowerCase().contains(needle.toLowerCase());

bool foundFor(SearchCropGroup g, String sellerTyped) =>
    g.terms.any((t) => likeMatches(sellerTyped, t));

void main() {
  group('normalize collapses spelling', () {
    test('strip case, spaces, underscores and hyphens', () {
      const variants = [
        'bok choy',
        'Bok Choy',
        'bok_choy',
        'bok-choy',
        'BOKCHOY',
        '  Bok   Choy  ',
      ];
      final keys = variants.map(SearchCropGroup.normalize).toSet();
      expect(keys.length, 1, reason: 'all variants must normalize identically');
      expect(keys.first, 'bokchoy');
    });

    test('sameCrop is spelling-insensitive', () {
      expect(SearchCropGroup.sameCrop('Bok Choy', 'bokchoy'), isTrue);
      expect(SearchCropGroup.sameCrop('GREEN_BEAN', 'green bean'), isTrue);
      expect(SearchCropGroup.sameCrop('lettuce', 'cucumber'), isFalse);
    });
  });

  group('every model label resolves to a real group', () {
    test('the 8 crops the model can output', () {
      const labels = {
        'kamatis': 0,
        'lettuce': 1,
        'cabbage': 2,
        'cucumber': 3,
        'chili': 4,
        'green_bean': 5,
        'chayote': 6,
        'bok_choy': 7,
      };
      labels.forEach((label, cls) {
        final g = SearchCropGroup.resolve(label);
        expect(g.yoloClass, cls, reason: '$label should map to class $cls');
        expect(g.title, isNotEmpty);
        expect(g.terms, isNotEmpty);
      });
    });

    test('label casing and punctuation do not matter', () {
      for (final variant in ['bok_choy', 'Bok Choy', 'bokchoy', 'BOK-CHOY']) {
        expect(
          SearchCropGroup.resolve(variant).yoloClass,
          7,
          reason: 'variant "$variant" must resolve to bok choy',
        );
      }
      expect(SearchCropGroup.resolve('GREEN_BEAN').yoloClass, 5);
      expect(SearchCropGroup.resolve('Green Bean').yoloClass, 5);
    });
  });

  group('regression: seller spelling must be searchable', () {
    test('"bokchoy" finds a listing the seller typed as "bokchoy"', () {
      final g = SearchCropGroup.resolve('bok_choy');
      expect(
        foundFor(g, 'bokchoy'),
        isTrue,
        reason: 'this is the bug that was reported: no term matched "bokchoy"',
      );
    });

    test('other compact spellings are also reachable', () {
      final g = SearchCropGroup.resolve('bok_choy');
      for (final typed in ['Bok Choy', 'bokchoy', 'BokChoy', 'Pechay',
          'pak choi', 'Pakchoi']) {
        expect(foundFor(g, typed), isTrue, reason: 'should match "$typed"');
      }
    });

    test('green bean and string bean variants', () {
      final g = SearchCropGroup.resolve('green_bean');
      for (final typed in ['Green Beans', 'greenbean', 'green bean',
          'Sitaw', 'String Beans', 'Yardlong Bean']) {
        expect(foundFor(g, typed), isTrue, reason: 'should match "$typed"');
      }
    });

    test('unrelated crops are NOT cross-matched', () {
      final g = SearchCropGroup.resolve('bok_choy');
      expect(foundFor(g, 'Tomato'), isFalse);
      expect(foundFor(g, 'Cucumber'), isFalse);
    });
  });

  group('pre-existing behaviour preserved', () {
    test('labels that worked before still resolve', () {
      const expectations = {
        'kamatis': 'Tomato',
        'tomato': 'Tomato',
        'repolyo': 'Cabbage',
        'cabbage': 'Cabbage',
        'ampalaya': 'Bitter gourd',
        'pipino': 'Cucumber',
        'cucumber': 'Cucumber',
        'sayote': 'Chayote',
        'chayote': 'Chayote',
        'sitaw': 'String beans',
        'green_bean': 'Green beans',
        'green bean': 'Green beans',
        'bataw': 'Hyacinth bean',
        'sword_bean': 'Sword bean',
        'sili': 'Chili',
        'chili': 'Chili',
        'pechay': 'Bok choy',
        'bok_choy': 'Bok choy',
        'lettuce': 'Lettuce',
        'squash': 'Squash',
      };
      expectations.forEach((label, title) {
        expect(
          SearchCropGroup.resolve(label).title,
          title,
          reason: 'label "$label" must still show as "$title"',
        );
      });
    });

    test('unknown labels fall through title-cased', () {
      final g = SearchCropGroup.resolve('dragonfruit');
      expect(g.title, 'Dragonfruit');
      expect(g.terms, ['dragonfruit']);
    });

    test('empty label does not throw', () {
      expect(SearchCropGroup.resolve('').terms, ['']);
    });
  });
}