// Fake data for the FarmSpot Business (Premium) UI preview.
// Names and places reflect Sitio Maraag / Sudlon, Cebu City.

const List<String> kPremiumCrops = [
  'Pechay',
  'Tomato',
  'Cabbage',
  'Lettuce',
  'Eggplant',
  'Okra',
  'Ampalaya',
  'String Beans',
];

const List<String> kBusinessTypes = [
  'Restaurant',
  'Carinderia',
  'Caterer',
  'Reseller',
  'Hotel',
  'Other',
];

/// Placeholder renewal date shown when Premium is active.
const String kPremiumRenewsOn = 'Nov 24, 2026';

class MockAlertRule {
  final String id;
  final String crop;
  final double radiusKm;
  bool enabled;

  MockAlertRule({
    required this.id,
    required this.crop,
    required this.radiusKm,
    this.enabled = true,
  });
}

class MockSavedFarm {
  final String id;
  final String name;
  final String barangay;
  final double distanceKm;
  final List<String> availableCrops;
  final int respondsInMin;
  final Set<String> watchingCrops;

  const MockSavedFarm({
    required this.id,
    required this.name,
    required this.barangay,
    required this.distanceKm,
    required this.availableCrops,
    required this.respondsInMin,
    this.watchingCrops = const {},
  });

  MockSavedFarm copyWith({Set<String>? watchingCrops}) {
    return MockSavedFarm(
      id: id,
      name: name,
      barangay: barangay,
      distanceKm: distanceKm,
      availableCrops: availableCrops,
      respondsInMin: respondsInMin,
      watchingCrops: watchingCrops ?? this.watchingCrops,
    );
  }
}

class MockBuyRequest {
  final String id;
  final String crop;
  final double quantityKg;
  final String frequency; // one-time | weekly
  final int responseCount;
  final double radiusKm;
  final String note;

  const MockBuyRequest({
    required this.id,
    required this.crop,
    required this.quantityKg,
    required this.frequency,
    required this.responseCount,
    this.radiusKm = 8,
    this.note = '',
  });
}

class MockFarmerResponse {
  final String farmName;
  final double distanceKm;
  final String note;

  const MockFarmerResponse({
    required this.farmName,
    required this.distanceKm,
    required this.note,
  });
}

class MockBuyerRequestCard {
  final String id;
  final String businessName;
  final bool verified;
  final String crop;
  final double quantityKg;
  final String frequency;
  final double distanceKm;

  const MockBuyerRequestCard({
    required this.id,
    required this.businessName,
    required this.verified,
    required this.crop,
    required this.quantityKg,
    required this.frequency,
    required this.distanceKm,
  });
}

class MockTripStop {
  final int number;
  final String farmName;
  final List<String> crops;
  final int etaMinutes;
  final String phone;

  const MockTripStop({
    required this.number,
    required this.farmName,
    required this.crops,
    required this.etaMinutes,
    required this.phone,
  });
}

class MockSourcingTrip {
  final List<MockTripStop> stops;
  final List<String> unavailableCrops;
  final int totalMinutes;

  const MockSourcingTrip({
    required this.stops,
    required this.unavailableCrops,
    required this.totalMinutes,
  });
}

class MockEarlyAlert {
  final String crop;
  final int farmCount;
  final double withinKm;
  final String listingHint;

  const MockEarlyAlert({
    required this.crop,
    required this.farmCount,
    required this.withinKm,
    required this.listingHint,
  });
}

/// Mutable preview copies so toggles on screens feel interactive.
final List<MockAlertRule> mockAlertRules = [
  MockAlertRule(id: 'a1', crop: 'Pechay', radiusKm: 8, enabled: true),
  MockAlertRule(id: 'a2', crop: 'Tomato', radiusKm: 12, enabled: true),
  MockAlertRule(id: 'a3', crop: 'Cabbage', radiusKm: 5, enabled: false),
];

final List<MockSavedFarm> mockSavedFarms = [
  MockSavedFarm(
    id: 'f1',
    name: 'Maraag Farm',
    barangay: 'Sitio Maraag, Sudlon I',
    distanceKm: 2.4,
    availableCrops: const ['Pechay', 'Lettuce', 'Cabbage'],
    respondsInMin: 15,
    watchingCrops: const {'Pechay'},
  ),
  MockSavedFarm(
    id: 'f2',
    name: 'Lumad Farm',
    barangay: 'Sitio Lumad, Sudlon II',
    distanceKm: 4.1,
    availableCrops: const ['Tomato', 'Eggplant', 'Okra'],
    respondsInMin: 25,
    watchingCrops: const {'Tomato'},
  ),
  MockSavedFarm(
    id: 'f3',
    name: 'Upper Farm',
    barangay: 'Upper Sudlon',
    distanceKm: 6.8,
    availableCrops: const ['Pechay', 'Ampalaya'],
    respondsInMin: 40,
    watchingCrops: const {},
  ),
];

final List<MockBuyRequest> mockBuyRequests = [
  const MockBuyRequest(
    id: 'r1',
    crop: 'Pechay',
    quantityKg: 20,
    frequency: 'weekly',
    responseCount: 3,
  ),
  const MockBuyRequest(
    id: 'r2',
    crop: 'Tomato',
    quantityKg: 15,
    frequency: 'one-time',
    responseCount: 1,
  ),
  const MockBuyRequest(
    id: 'r3',
    crop: 'Cabbage',
    quantityKg: 30,
    frequency: 'weekly',
    responseCount: 4,
  ),
  const MockBuyRequest(
    id: 'r4',
    crop: 'Lettuce',
    quantityKg: 10,
    frequency: 'one-time',
    responseCount: 0,
  ),
];

const List<MockFarmerResponse> mockResponsesForPechay = [
  MockFarmerResponse(
    farmName: 'Maraag Farm',
    distanceKm: 2.4,
    note: 'Can supply 20 kg every Monday morning.',
  ),
  MockFarmerResponse(
    farmName: 'Upper Farm',
    distanceKm: 6.8,
    note: 'Have 12 kg ready now. More next week.',
  ),
  MockFarmerResponse(
    farmName: 'Green Ridge Plot',
    distanceKm: 5.2,
    note: 'Happy to set aside pechay for you.',
  ),
];

const List<MockBuyerRequestCard> mockFarmerBoardRequests = [
  MockBuyerRequestCard(
    id: 'br1',
    businessName: 'Carinderia ni Nanay Rosa',
    verified: true,
    crop: 'Pechay',
    quantityKg: 15,
    frequency: 'weekly',
    distanceKm: 3.2,
  ),
  MockBuyerRequestCard(
    id: 'br2',
    businessName: 'Cafe Sudlon Kitchen',
    verified: true,
    crop: 'Tomato',
    quantityKg: 10,
    frequency: 'one-time',
    distanceKm: 4.8,
  ),
  MockBuyerRequestCard(
    id: 'br3',
    businessName: 'Maraag Catering Co.',
    verified: false,
    crop: 'Cabbage',
    quantityKg: 25,
    frequency: 'weekly',
    distanceKm: 1.9,
  ),
  MockBuyerRequestCard(
    id: 'br4',
    businessName: 'Hotel Cebu Heights',
    verified: true,
    crop: 'Lettuce',
    quantityKg: 8,
    frequency: 'one-time',
    distanceKm: 7.0,
  ),
];

const MockSourcingTrip mockSourcingTrip = MockSourcingTrip(
  stops: [
    MockTripStop(
      number: 1,
      farmName: 'Maraag Farm',
      crops: ['Pechay', 'Lettuce'],
      etaMinutes: 12,
      phone: '0917-555-0101',
    ),
    MockTripStop(
      number: 2,
      farmName: 'Lumad Farm',
      crops: ['Tomato', 'Eggplant'],
      etaMinutes: 18,
      phone: '0918-555-0202',
    ),
    MockTripStop(
      number: 3,
      farmName: 'Upper Farm',
      crops: ['Cabbage'],
      etaMinutes: 10,
      phone: '0920-555-0303',
    ),
  ],
  unavailableCrops: ['Okra'],
  totalMinutes: 40,
);

const MockEarlyAlert mockEarlyAlert = MockEarlyAlert(
  crop: 'Pechay',
  farmCount: 2,
  withinKm: 8,
  listingHint: 'Available Now nearby',
);

/// How many farms near the user grow a given crop (for buy-request helper copy).
int mockFarmsGrowing(String crop) {
  switch (crop.toLowerCase()) {
    case 'pechay':
      return 5;
    case 'tomato':
      return 4;
    case 'cabbage':
      return 3;
    case 'lettuce':
      return 3;
    case 'eggplant':
      return 2;
    default:
      return 2;
  }
}
