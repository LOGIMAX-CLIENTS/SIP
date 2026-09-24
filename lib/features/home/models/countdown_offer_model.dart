/// Data models for the settings-driven 100-Day Grand Launch Countdown Offer.
///
/// The API returns different payloads based on [customerType]:
///   • `NEW`      → [NewCustomerOffer]  (countdown timer + "Start Investing" CTA)
///   • `EXISTING` → [ExistingCustomerOffer] (progress card + "Add Investment" CTA)
///
/// When [enabled] is `false`, the widget renders `SizedBox.shrink()`.
class CountdownOfferResponse {
  final bool enabled;
  final String? customerType; // "NEW" | "EXISTING"
  final NewCustomerOffer? newOffer;
  final ExistingCustomerOffer? existingOffer;

  CountdownOfferResponse({
    required this.enabled,
    this.customerType,
    this.newOffer,
    this.existingOffer,
  });

  factory CountdownOfferResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return CountdownOfferResponse.disabled();

    final enabled = data['enabled'] == true;
    if (!enabled) return CountdownOfferResponse.disabled();

    final customerType = data['customer_type'] as String?;
    NewCustomerOffer? newOffer;
    ExistingCustomerOffer? existingOffer;

    if (customerType == 'NEW' && data['new_offer'] != null) {
      newOffer = NewCustomerOffer.fromJson(
        data['new_offer'] as Map<String, dynamic>,
      );
    }
    if (customerType == 'EXISTING' && data['existing_offer'] != null) {
      final existingJson =
          Map<String, dynamic>.from(data['existing_offer'] as Map<String, dynamic>);
      // webview_url may come at root data level or top-level json — inject into existing_offer map
      if (!existingJson.containsKey('webview_url')) {
        final rootUrl = data['webview_url'] ?? json['webview_url'];
        if (rootUrl != null) {
          existingJson['webview_url'] = rootUrl;
        }
      }
      existingOffer = ExistingCustomerOffer.fromJson(existingJson);
    }

    return CountdownOfferResponse(
      enabled: enabled,
      customerType: customerType,
      newOffer: newOffer,
      existingOffer: existingOffer,
    );
  }

  factory CountdownOfferResponse.disabled() =>
      CountdownOfferResponse(enabled: false);
}

class NewCustomerOffer {
  final String offerName;
  final String offerStartDate;
  final String offerEndDate;
  final int remainingDays;
  final int remainingHours;
  final int remainingMinutes;
  final int remainingSeconds;
  final int rewardPercentage;
  final int dailyPenaltyPercentage;
  final double benchmarkAmount;
  final int benchmarkPercentage;
  final bool benchmarkEnabled;
  final String ctaText;

  /// API-driven description text for the offer card.
  final String descriptionTitle;
  final String descriptionBody;

  /// URL for the WebView-based "Know More" offer benefits page.
  final String? webviewUrl;

  NewCustomerOffer({
    required this.offerName,
    required this.offerStartDate,
    required this.offerEndDate,
    required this.remainingDays,
    required this.remainingHours,
    required this.remainingMinutes,
    required this.remainingSeconds,
    required this.rewardPercentage,
    required this.dailyPenaltyPercentage,
    required this.benchmarkAmount,
    required this.benchmarkPercentage,
    required this.benchmarkEnabled,
    required this.ctaText,
    required this.descriptionTitle,
    required this.descriptionBody,
    this.webviewUrl,
  });

  factory NewCustomerOffer.fromJson(Map<String, dynamic> json) {
    return NewCustomerOffer(
      offerName: json['offer_name'] as String? ?? 'GRAND LAUNCH',
      offerStartDate: json['offer_start_date'] as String? ?? '',
      offerEndDate: json['offer_end_date'] as String? ?? '',
      remainingDays: (json['remaining_days'] as num?)?.toInt() ?? 0,
      remainingHours: (json['remaining_hours'] as num?)?.toInt() ?? 0,
      remainingMinutes: (json['remaining_minutes'] as num?)?.toInt() ?? 0,
      remainingSeconds: (json['remaining_seconds'] as num?)?.toInt() ?? 0,
      rewardPercentage: (json['reward_percentage'] as num?)?.toInt() ?? 100,
      dailyPenaltyPercentage:
          (json['daily_penalty_percentage'] as num?)?.toInt() ?? 1,
      benchmarkAmount:
          (json['benchmark_amount'] as num?)?.toDouble() ?? 0.0,
      benchmarkPercentage:
          (json['benchmark_percentage'] as num?)?.toInt() ?? 100,
      benchmarkEnabled: json['benchmark_enabled'] == true,
      ctaText: json['cta_text'] as String? ?? 'Start Saving',
      descriptionTitle: json['description_title'] as String? ?? 'Save in Gold,',
      descriptionBody: json['description_body'] as String? ?? 'Get Free Silver Rewards',
      webviewUrl: json['webview_url'] as String?,
    );
  }
}

class ExistingCustomerOffer {
  final String offerName;
  final String silverEarned;
  final int investDays;
  final int daysRemaining;
  final int currentRewardPercentage;
  final String offerEndDate;
  final String ctaText;

  /// URL for the WebView-based "Know More" offer benefits page.
  final String? webviewUrl;

  ExistingCustomerOffer({
    required this.offerName,
    required this.silverEarned,
    required this.investDays,
    required this.daysRemaining,
    required this.currentRewardPercentage,
    required this.offerEndDate,
    required this.ctaText,
    this.webviewUrl,
  });

  factory ExistingCustomerOffer.fromJson(Map<String, dynamic> json) {
    return ExistingCustomerOffer(
      offerName: json['offer_name'] as String? ?? 'GRAND LAUNCH',
      silverEarned: json['silver_earned'] as String? ?? '0.0000',
      investDays: (json['invest_days'] as num?)?.toInt() ?? 0,
      daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
      currentRewardPercentage:
          (json['current_reward_percentage'] as num?)?.toInt() ?? 0,
      offerEndDate: json['offer_end_date'] as String? ?? '',
      ctaText: json['cta_text'] as String? ?? 'Start Saving',
      webviewUrl: json['webview_url'] as String?,
    );
  }
}
