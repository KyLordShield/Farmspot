/// Typical estimates for newly listed produce. The countdown comes from
/// the server's saved deadline, including for listings created before this policy.
String? cropShelfLife(String? name) {
  final key = name?.trim().toLowerCase().replaceAll(RegExp(r'[_ -]+'), ' ');
  return switch (key) {
    'kamatis' || 'tomato' || 'tomatoes' => 'About 5 days',
    'lettuce' ||
    'cucumber' ||
    'cucumbers' ||
    'pipino' ||
    'bok choy' ||
    'pechay' ||
    'pak choi' => 'About 7 days',
    'green bean' || 'green beans' || 'baguio beans' => 'About 8 days',
    'carrot' || 'carrots' => 'About 10 days',
    'chili' ||
    'chilis' ||
    'chilies' ||
    'chilli' ||
    'chillies' ||
    'sili' ||
    'cabbage' ||
    'cabbages' ||
    'repolyo' => 'About 21 days',
    'chayote' || 'chayotes' || 'sayote' => 'About 30 days',
    _ => null,
  };
}

String? shelfLifeRemaining(String status, DateTime? deadline) {
  if (status != 'AVAILABLE_NOW' || deadline == null) return null;
  final hours = deadline.difference(DateTime.now()).inMinutes / 60;
  if (hours <= 0) return null;
  if (hours < 24) return 'Estimated shelf life · Less than 1 day left';
  final days = (hours / 24).ceil();
  return 'Estimated shelf life · $days days left';
}
