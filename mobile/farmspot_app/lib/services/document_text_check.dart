import 'package:cross_file/cross_file.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A local screening aid only. Admin review still determines authenticity.
class DocumentTextCheck {
  static Future<String> read(XFile photo) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      return (await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      )).text;
    } finally {
      await recognizer.close();
    }
  }

  static String normalize(String text) => text
      .toUpperCase()
      .replaceAll('Ñ', 'N')
      .replaceAll('É', 'E')
      .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
      .trim();

  static bool looksLikeDocument(String text, {required bool isId}) {
    final value = ' ${normalize(text)} ';
    final types = isId
        ? [
            'PHILIPPINE IDENTIFICATION',
            'PAMBANSANG PAGKAKAKILANLAN',
            'PHILSYS',
            'PASSPORT',
            'DRIVER LICENSE',
            'DRIVERS LICENSE',
            'DRIVER S LICENSE',
            'UNIFIED MULTI PURPOSE',
            'UMID',
            'SOCIAL SECURITY',
            'SSS',
            'GSIS',
            'POSTAL ID',
            'VOTER',
            'VOTERS',
            'VOTER S',
            'PHILHEALTH',
            'PRC',
            'PROFESSIONAL REGULATION',
            'SENIOR CITIZEN',
            'PWD',
            'PERSON WITH DISABILITY',
            'BUREAU OF INTERNAL REVENUE',
          ]
        : [
            'PERMIT',
            'CERTIFICATE',
            'CERTIFICATION',
            'CLEARANCE',
            'KATIBAYAN',
            'SERTIPIKO',
            'REHISTRO',
          ];
    final fields = isId
        ? [
            'NAME',
            'PANGALAN',
            'SURNAME',
            'APELYIDO',
            'BIRTH',
            'ADDRESS',
            'SEX',
            'EXPIRY',
            'EXPIRATION',
          ]
        : [
            'NAME',
            'OWNER',
            'BUSINESS',
            'FARM',
            'AGRICULTURE',
            'BARANGAY',
            'REGISTRATION',
            'ISSUED',
            'VALID',
          ];
    bool contains(String phrase) => value.contains(' $phrase ');
    return normalize(text).split(' ').length >= 6 &&
        types.any(contains) &&
        fields.any(contains);
  }

  /// Match complete name tokens in any order, tolerating punctuation and
  /// optional middle initials. No fuzzy surname matching or OCR auto-correction.
  static bool matchesName(String name, String text) {
    final parts = normalize(
      name,
    ).split(' ').where((p) => p.isNotEmpty).toList();
    final significant = parts.where((p) => p.length > 1).toList();
    if (significant.length < 2) return false;
    final words = normalize(text).split(' ').toSet();
    return significant.every(words.contains);
  }
}
