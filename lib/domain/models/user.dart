class User {
  final String id;
  final String deviceId;
  final String country;
  final String language;
  final String referralCode;
  final bool isPremium;
  final DateTime? trialEndsAt;
  final int computeCredits;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.deviceId,
    required this.country,
    required this.language,
    required this.referralCode,
    required this.isPremium,
    this.trialEndsAt,
    required this.computeCredits,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id:             j['id'],
    deviceId:       j['device_id'],
    country:        j['country'] ?? 'IR',
    language:       j['language'] ?? 'ru',
    referralCode:   j['referral_code'] ?? '',
    isPremium:      j['is_premium'] ?? false,
    trialEndsAt:    j['trial_ends_at'] != null ? DateTime.parse(j['trial_ends_at']) : null,
    computeCredits: j['compute_credits'] ?? 0,
    createdAt:      DateTime.parse(j['created_at']),
  );

  bool get hasAccess {
    if (isPremium) return true;
    return trialEndsAt?.isAfter(DateTime.now()) ?? false;
  }

  int get trialDaysLeft {
    if (trialEndsAt == null) return 0;
    final d = trialEndsAt!.difference(DateTime.now()).inDays;
    return d.clamp(0, 999);
  }

  bool get isTrialActive => !isPremium && (trialEndsAt?.isAfter(DateTime.now()) ?? false);
}
