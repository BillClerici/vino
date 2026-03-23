class User {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String avatarUrl;
  final String fullName;
  final String timezone;
  final String subscriptionStatus;
  final String subscriptionPlan;
  final bool hasActiveSubscription;
  final bool isInTrial;
  final int trialDaysRemaining;
  final String onboardingStatus;
  final List<SocialAccount> socialAccounts;

  bool get needsOnboarding => onboardingStatus == 'pending' || onboardingStatus == 'later';

  const User({
    required this.id,
    required this.email,
    this.firstName = '',
    this.lastName = '',
    this.avatarUrl = '',
    this.fullName = '',
    this.timezone = 'America/New_York',
    this.subscriptionStatus = 'none',
    this.subscriptionPlan = '',
    this.hasActiveSubscription = false,
    this.isInTrial = false,
    this.trialDaysRemaining = 0,
    this.onboardingStatus = 'pending',
    this.socialAccounts = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      timezone: json['timezone'] as String? ?? 'America/New_York',
      subscriptionStatus: json['subscription_status'] as String? ?? 'none',
      subscriptionPlan: json['subscription_plan'] as String? ?? '',
      hasActiveSubscription: json['has_active_subscription'] as bool? ?? false,
      isInTrial: json['is_in_trial'] as bool? ?? false,
      trialDaysRemaining: json['trial_days_remaining'] as int? ?? 0,
      onboardingStatus: json['onboarding_status'] as String? ?? 'pending',
      socialAccounts: (json['social_accounts'] as List<dynamic>?)
              ?.map((e) => SocialAccount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class SocialAccount {
  final String id;
  final String provider;
  final String providerUid;

  const SocialAccount({
    required this.id,
    required this.provider,
    required this.providerUid,
  });

  factory SocialAccount.fromJson(Map<String, dynamic> json) {
    return SocialAccount(
      id: json['id'] as String,
      provider: json['provider'] as String,
      providerUid: json['provider_uid'] as String,
    );
  }
}
