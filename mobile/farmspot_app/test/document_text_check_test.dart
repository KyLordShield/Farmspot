import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/services/document_text_check.dart';

void main() {
  test('random photos and isolated ID text do not qualify', () {
    for (final text in [
      '',
      'ID',
      'A beautiful farm with green plants',
      'NAME Juan Dela Cruz ADDRESS Manila',
    ]) {
      expect(DocumentTextCheck.looksLikeDocument(text, isId: true), isFalse);
    }
  });
  test('ID and permit screening use different document clues', () {
    const id = 'PHILIPPINE IDENTIFICATION NAME Juan Dela Cruz ADDRESS Manila';
    const permit = 'BUSINESS PERMIT OWNER Juan Dela Cruz FARM Manila';
    expect(DocumentTextCheck.looksLikeDocument(id, isId: true), isTrue);
    expect(DocumentTextCheck.looksLikeDocument(permit, isId: false), isTrue);
    expect(DocumentTextCheck.looksLikeDocument(permit, isId: true), isFalse);
    expect(DocumentTextCheck.looksLikeDocument(id, isId: false), isFalse);
  });
  test(
    'name matching tolerates order, case, punctuation and middle initials',
    () {
      expect(
        DocumentTextCheck.matchesName('Juan M. Dela Cruz', 'CRUZ, JUAN DELA'),
        isTrue,
      );
      expect(DocumentTextCheck.matchesName('Juan Peña', 'PENA JUAN'), isTrue);
      expect(
        DocumentTextCheck.matchesName('Juan Cruz', 'JUAN CRUZADO'),
        isFalse,
      );
      expect(DocumentTextCheck.matchesName('Juan Cruz', 'PEDRO CRUZ'), isFalse);
      expect(DocumentTextCheck.matchesName('', 'JUAN CRUZ'), isFalse);
    },
  );
}
