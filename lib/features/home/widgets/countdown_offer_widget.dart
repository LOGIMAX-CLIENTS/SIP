import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/providers/countdown_offer_provider.dart';
import '../../../shared/widgets/loaders.dart';
import 'countdown_offer_new.dart';
import 'countdown_offer_existing.dart';

/// Orchestrator widget for the 100-Day Grand Launch Countdown Offer.
///
/// Watches [countdownOfferProvider] and renders the appropriate sub-widget
/// based on the API response:
///   • `enabled: false`         → [SizedBox.shrink] (zero visual presence)
///   • `customer_type: "NEW"`   → [CountdownOfferNew]
///   • `customer_type: "EXISTING"` → [CountdownOfferExisting]
///   • Error / unknown          → [SizedBox.shrink] (fail silently)
class CountdownOfferWidget extends ConsumerWidget {
  const CountdownOfferWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offerAsync = ref.watch(countdownOfferProvider);

    return offerAsync.when(
      data: (offer) {
        if (!offer.enabled) return const SizedBox.shrink();

        if (offer.customerType == 'EXISTING' && offer.existingOffer != null) {
          return CountdownOfferExisting(offer: offer.existingOffer!);
        }
        if (offer.customerType == 'NEW' && offer.newOffer != null) {
          return CountdownOfferNew(
            offer: offer.newOffer!,
          );
        }
        return const SizedBox.shrink();
      },
      loading: () => _buildShimmer(),
      error: (_, __) => const SizedBox.shrink(), // Fail silently
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: AppLoaders.sectionLoader(
        height: 240.h,
        width: double.infinity,
        isDark: false,
        borderRadius: 24,
      ),
    );
  }
}
