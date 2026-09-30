import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/services/ai_chat_service.dart';

// The assistant's replies are rendered as plain text in a chat bubble, so any
// markdown the model emits shows up on screen exactly as typed. A user seeing
// "**Add Crop**" with the asterisks still there reads it as a broken app, which
// is why these cases exist rather than relying on the model to behave.
//
// The system prompt tells the model not to use markdown at all. stripMarkdown
// is the backstop for when it does anyway, so it has to be conservative: it
// removes formatting syntax and must never eat the words, the numbers, or an
// ordinary asterisk that was never emphasis to begin with.
void main() {
  group('bold and italic markers are removed', () {
    test('the case that was actually reported: **Add Crop**', () {
      expect(
        stripMarkdown('Tap **Add Crop** to list your produce.'),
        'Tap Add Crop to list your produce.',
      );
    });

    test('double underscores', () {
      expect(stripMarkdown('Go to __Profile__ first.'), 'Go to Profile first.');
    });

    test('single asterisks around a phrase', () {
      expect(stripMarkdown('It is *pending review* now.'),
          'It is pending review now.');
    });

    test('single underscores around a phrase', () {
      expect(stripMarkdown('That is the _only_ way.'),
          'That is the only way.');
    });

    test('several emphasised words in one answer', () {
      expect(
        stripMarkdown('Tap **Add Crop**, pick a **category**, then **Save**.'),
        'Tap Add Crop, pick a category, then Save.',
      );
    });
  });

  group('other markdown is removed', () {
    test('headings lose their hashes', () {
      expect(stripMarkdown('## How to list produce\nTap Add Crop.'),
          'How to list produce\nTap Add Crop.');
    });

    test('inline code loses its backticks', () {
      expect(stripMarkdown('Set `FRM_STATUS` to approved.'),
          'Set FRM_STATUS to approved.');
    });

    test('a fenced block keeps its content', () {
      expect(
        stripMarkdown('Run:\n```\nphp artisan migrate\n```\nThen restart.'),
        'Run:\nphp artisan migrate\nThen restart.',
      );
    });

    test('a markdown link shows only its label', () {
      expect(stripMarkdown('See the [guide](https://x.test/guide) for more.'),
          'See the guide for more.');
    });

    test('leading bullets lose the dash', () {
      expect(stripMarkdown('- Tap Add Crop\n- Pick a category'),
          'Tap Add Crop\nPick a category');
    });
  });

  group('ordinary text survives', () {
    // These are the cases where an over-eager stripper does real damage: the
    // answers most likely to contain a stray symbol stop being readable.
    test('multiplication is not treated as emphasis', () {
      expect(stripMarkdown('That is 5 * 3 kilos.'), 'That is 5 * 3 kilos.');
    });

    test('an underscored word is left alone', () {
      expect(stripMarkdown('The field is farm_name here.'),
          'The field is farm_name here.');
    });

    test('a price with a peso sign and digits is untouched', () {
      expect(stripMarkdown('It sells for 45/kg.'), 'It sells for 45/kg.');
    });

    test('a plain sentence is returned unchanged', () {
      const plain = 'Your farm is approved and pinned on the map.';
      expect(stripMarkdown(plain), plain);
    });

    test('an empty string stays empty', () {
      expect(stripMarkdown(''), '');
    });
  });

  group('numbered steps are the one list that stays', () {
    // The prompt allows plain "1. 2. 3." because a chat bubble has no room for
    // bullets, so the stripper must not eat them.
    test('numbered steps keep their numbers', () {
      expect(
        stripMarkdown('1. Open My Farm\n2. Tap Add Crop\n3. Save.'),
        '1. Open My Farm\n2. Tap Add Crop\n3. Save.',
      );
    });

    test('numbered steps survive alongside bold labels', () {
      expect(
        stripMarkdown('1. Tap **Add Crop**\n2. Choose a category.'),
        '1. Tap Add Crop\n2. Choose a category.',
      );
    });

    test('a full guide answer keeps its one-line-per-step shape', () {
      // The prompt asks for a short lead-in then numbered steps, so this is
      // the shape the sanitizer has to leave completely alone.
      const answer = 'Here is how to add a crop listing.\n'
          '1. Open My Farm from the bottom navigation.\n'
          '2. Tap Add Crop.\n'
          '3. Choose a category and enter the quantity.\n'
          '4. Set your price per kilo, then tap Post.';

      expect(stripMarkdown(answer), answer);
    });
  });

  test('whitespace left behind by the removals is tidied up', () {
    expect(stripMarkdown('Tap   **Add Crop**   now.'), 'Tap Add Crop now.');
    // A blank line is a paragraph break and is worth keeping; only the
    // indentation around a line break is debris.
    expect(stripMarkdown('First line.\n\n   Second line.'),
        'First line.\n\nSecond line.');
  });

  test('several blank lines collapse to one paragraph break', () {
    // A lifted-out code fence can leave the reply with a run of newlines.
    expect(stripMarkdown('One.\n\n\n\nTwo.'), 'One.\n\nTwo.');
  });
}
