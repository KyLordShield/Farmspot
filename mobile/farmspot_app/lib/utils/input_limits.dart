/// Keep these aligned with the API's InputLimits validation rules.
abstract final class InputLimits {
  static const cropName = 40;
  static const farmName = 100;
  static const description = 1000;
  static const barangay = 100;
  static const address = 150;
  static const personNamePart = 40;
  static const fullName = personNamePart * 2 + 1;
}
