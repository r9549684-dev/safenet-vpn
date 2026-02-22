class ByeDPIProfile {
  final int splitPosition;
  final String desyncMode;
  final int fakeTTL;

  const ByeDPIProfile({
    required this.splitPosition,
    required this.desyncMode,
    required this.fakeTTL,
  });
}

class ByeDPIProfiles {
  static const Map<String, ByeDPIProfile> byCountry = {
    'TR': ByeDPIProfile(splitPosition: 2, desyncMode: 'fake',     fakeTTL: 8),
    'EG': ByeDPIProfile(splitPosition: 3, desyncMode: 'disorder', fakeTTL: 6),
    'AE': ByeDPIProfile(splitPosition: 1, desyncMode: 'fake',     fakeTTL: 5),
    'SA': ByeDPIProfile(splitPosition: 1, desyncMode: 'fake',     fakeTTL: 5),
    'IR': ByeDPIProfile(splitPosition: 2, desyncMode: 'split',    fakeTTL: 10),
    'RU': ByeDPIProfile(splitPosition: 2, desyncMode: 'fake',     fakeTTL: 8),
  };

  static ByeDPIProfile getProfile(String countryCode) {
    return byCountry[countryCode.toUpperCase()] ??
        const ByeDPIProfile(splitPosition: 2, desyncMode: 'fake', fakeTTL: 8);
  }
}
