/// Offline suggestions, not a restriction on manually entered addresses.
/// Cebu City: https://psa.gov.ph/classification/psgc/barangays/0730600000
/// Other cities: https://region7.ntc.gov.ph/elementor-2962/regional-profile/area-of-responsibility/cebu/
/// Checked 2026-11-22. Names are displayed without population/designation data.
abstract final class AddressAreas {
  static const _barangays = {
    'Cebu City': [
      'Adlaon',
      'Agsungot',
      'Apas',
      'Babag',
      'Basak Pardo',
      'Bacayan',
      'Banilad',
      'Basak San Nicolas',
      'Binaliw',
      'Bonbon',
      'Budla-an',
      'Buhisan',
      'Bulacao',
      'Buot-Taup Pardo',
      'Busay',
      'Calamba',
      'Cambinocot',
      'Capitol Site',
      'Carreta',
      'Central',
      'Cogon Ramos',
      'Cogon Pardo',
      'Day-as',
      'Duljo',
      'Ermita',
      'Guadalupe',
      'Guba',
      'Hippodromo',
      'Inayawan',
      'Kalubihan',
      'Kalunasan',
      'Kamagayan',
      'Camputhaw',
      'Kasambagan',
      'Kinasang-an Pardo',
      'Labangon',
      'Lahug',
      'Lorega',
      'Lusaran',
      'Luz',
      'Mabini',
      'Mabolo',
      'Malubog',
      'Mambaling',
      'Pahina Central',
      'Pahina San Nicolas',
      'Pamutan',
      'Pardo',
      'Pari-an',
      'Paril',
      'Pasil',
      'Pit-os',
      'Pulangbato',
      'Pung-ol-Sibugay',
      'Punta Princesa',
      'Quiot Pardo',
      'Sambag I',
      'Sambag II',
      'San Antonio',
      'San Jose',
      'San Nicolas Central',
      'San Roque',
      'Santa Cruz',
      'Sawang Calero',
      'Sinsin',
      'Sirao',
      'Suba Pob.',
      'Sudlon I',
      'Sapangdaku',
      'T. Padilla',
      'Tabunan',
      'Tagbao',
      'Talamban',
      'Taptap',
      'Tejero',
      'Tinago',
      'Tisa',
      'To-ong Pardo',
      'Zapatera',
      'Sudlon II',
    ],
    'Lapu-Lapu City': [
      'Agus',
      'Babag',
      'Bankal',
      'Baring',
      'Basak',
      'Buaya',
      'Calawisan',
      'Canjulao',
      'Caw-oy',
      'Cawhagan',
      'Caubian',
      'Gun-ob',
      'Ibo',
      'Looc',
      'Mactan',
      'Maribago',
      'Marigondon',
      'Pajac',
      'Pajo',
      'Pangan-an',
      'Poblacion',
      'Punta Engaño',
      'Pusok',
      'Sabang',
      'Santa Rosa',
      'Subabasbas',
      'Talima',
      'Tingo',
      'Tungasan',
      'San Vicente',
    ],
    'Mandaue City': [
      'Alang-alang',
      'Bakilid',
      'Banilad',
      'Basak',
      'Cabancalan',
      'Cambaro',
      'Canduman',
      'Casili',
      'Casuntingan',
      'Centro',
      'Cubacub',
      'Guizo',
      'Ibabao-Estancia',
      'Jagobiao',
      'Labogon',
      'Looc',
      'Maguikay',
      'Mantuyong',
      'Opao',
      'Pakna-an',
      'Pagsabungan',
      'Subangdaku',
      'Tabok',
      'Tawason',
      'Tingub',
      'Tipolo',
      'Umapad',
    ],
  };

  static final List<String> all = List.unmodifiable(
    [
      for (final city in _barangays.entries)
        for (final barangay in city.value) '$barangay, ${city.key}, Cebu',
    ]..sort(),
  );

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ñ]+'), ' ').trim();

  static List<String> search(String query) {
    final words = _normalize(query).split(' ').where((word) => word.isNotEmpty);
    return all.where((area) {
      final normalized = _normalize(area);
      return words.every(normalized.contains);
    }).toList();
  }

  static List<String> suggestions(String address) {
    final parts = address.split(',');
    for (var start = 0; start < parts.length; start++) {
      final query = parts.sublist(start).join(',').trim();
      if (query.isEmpty) continue;
      final matches = search(query);
      if (matches.isNotEmpty) return matches;
    }
    return const [];
  }

  static String _placeKey(String value) => _normalize(value)
      .split(' ')
      .where((word) => !['city', 'barangay', 'brgy'].contains(word))
      .join(' ');

  static String? resolve(String input) {
    final key = _placeKey(input);
    final matches = all
        .where(
          (area) => [
            area,
            area.substring(0, area.lastIndexOf(',')),
            area.split(',').first,
          ].any((form) => _placeKey(form) == key),
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  /// Highly urbanized cities are indexed without Cebu as their province.
  static String mapQuery(String input) {
    final area = resolve(input);
    if (area == null) return input;
    final parts = area.split(', ');
    final city = parts[1] == 'Cebu City'
        ? parts[1]
        : parts[1].replaceAll(' City', '');
    return '${parts.first}, $city, Philippines';
  }

  static bool matchesMapResult(String input, String displayName) {
    final area = resolve(input);
    if (area == null) return true;
    final parts = area.split(', ');
    final result = ' ${_placeKey(displayName)} ';
    return result.contains(' ${_placeKey(parts.first)} ') &&
        result.contains(' ${_placeKey(parts[1])} ');
  }

  /// Keep house/street details when changing the selected barangay.
  static String withArea(String address, String area) {
    final current = address.trim();
    if (current.isEmpty) return area;
    for (final oldArea in all) {
      if (current.toLowerCase().endsWith(oldArea.toLowerCase())) {
        final prefix = current
            .substring(0, current.length - oldArea.length)
            .replaceFirst(RegExp(r'[,\s]+$'), '');
        return prefix.isEmpty ? area : '$prefix, $area';
      }
    }
    // A partially typed area should be completed rather than duplicated.
    final parts = current.split(',');
    for (var start = 0; start < parts.length; start++) {
      final suffix = parts.sublist(start).join(',').trim();
      if (suffix.isNotEmpty && search(suffix).isNotEmpty) {
        final prefix = parts.take(start).join(',').trim();
        return prefix.isEmpty ? area : '$prefix, $area';
      }
    }
    return '$current, $area';
  }
}
