import 'package:cross_file/cross_file.dart';

/// Mutable scratchpad shared across the farm setup wizard screens.
class FarmSetupData {
  String name = '';
  String description = '';
  String barangay = '';
  String? locationAddress;
  double? latitude;
  double? longitude;
  List<XFile> photos = [];
  XFile? verificationDocument;
  XFile? farmCertificate;

  // Screening text stays in wizard memory. Admins review the original photos.
  String verificationDocumentText = '';
  String farmCertificateText = '';

  bool get hasDetails =>
      name.trim().isNotEmpty &&
      description.trim().isNotEmpty &&
      barangay.trim().isNotEmpty;

  bool get hasPhotos => photos.isNotEmpty;

  bool get hasLocation => latitude != null && longitude != null;

  bool get isReadyToSubmit => hasDetails && hasLocation && hasPhotos;
}
