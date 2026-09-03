class AppConstants {
  static const String companyName = 'startGOLD';
  static const String appName = 'startGOLD';

  // Login Screen Content
  static const String loginTitle = 'Welcome Back';
  static const String loginSubtitle =
      'Login to start saving in 24K Pure Gold';

  // OTP Screen Content
  static const String otpTitle = 'Verify to Secure\nYour Assets';
  static const String otpSubtitle =
      'We have dispatched a security code to protect your digital vault.';

  // MPIN Screen Content
  // Default (app unlock / login)
  static const String mpinTitle = 'Quick Login With MPIN';
  static const String mpinSubtitle =
      'Use your MPIN for fast and secure access to your account';

  // MPIN — Withdrawal context
  static const String mpinWithdrawalTitle = 'Authorized Withdrawal';
  static const String mpinWithdrawalSubtitle =
      'Confirm this withdrawal quickly and securely using your MPIN.';

  // MPIN — Biometric setup context
  static const String mpinBiometricTitle = 'Secure Biometric Setup';
  static const String mpinBiometricSubtitle =
      'Verify using your MPIN to enable biometric login with secure access';

  // Home Screen Content
  static const String homeWelcomeSubtitle = 'Ready to grow your wealth today?';
  static const String welcome = 'Welcome';
  static const String portfolioTitle = 'Total Portfolio';
  static const String portfolioInvested = 'Total Saved';
  static const String portfolioValue = 'Current Value';
  static const String portfolioReturns = 'Total Returns';
  static const String joinBannerTitle = 'Start Building Wealth';
  static const String joinBannerSubtitle =
      'Join thousands of smart savers saving in Pure Gold every day.';
  static const String joinBannerCTA = 'Create Your First AutoGold';
  static const String sectionHeaderArtisanal = 'Artisanal Curations';
  static const String exploreAll = 'Explore All';
  static const String lastUpdated = 'Last updated';
  static const String instantSavingTitle = 'Instant Saving';

  // Withdrawal Flow
  static const String withdrawTitle = 'Withdraw Funds';
  static const String sellGold = 'Sell Gold';
  static const String sellSilver = 'Sell Silver';
  static const String availableBalance = 'Available Balance';
  static const String enterAmount = 'Enter Amount';
  static const String withdrawNow = 'Withdraw Now';
  static const String kycRequired = 'KYC Verification Required';
  static const String kycRequiredDesc =
      'Please complete your KYC to enable withdrawals.';
  static const String selectBank = 'Select Bank Account / UPI';
  static const String addUPI = 'Add New UPI ID';
  static const String confirmWithdrawal = 'Confirm Withdrawal';
  static const String rateLocked = 'Rate Locked for';
  static const String seconds = 'sec';

  // Withdrawal Limits
  static const double minWithdrawalGrams = 0.001;
  static const double maxWithdrawalGrams = 100.0;
  static const int amountDecimalLimit = 4;
  static const String insufficientBalance = 'Insufficient balance';
  static const String minWithdrawalError = 'Minimum withdrawal is 0.001g';
  static const String maxWithdrawalError = 'Maximum withdrawal is 100g';
  static const String enterValidAmount = 'Enter a valid amount';
}
