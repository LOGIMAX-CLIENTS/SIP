import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/security/session_manager.dart';
import '../core/security/secure_storage_service.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/auth/login/login_screen.dart';
import '../features/auth/otp/otp_screen.dart';
import '../features/mpin/mpin_screen.dart';
import '../features/kyc/screens/pan_verification_screen.dart';
import '../features/instant_saving/instant_saving_screen.dart';
import '../features/daily_savings/daily_savings_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/support/support_screen.dart';
import '../features/referral/referral_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/auth/pin/pin_creation_screen.dart';
import '../features/auth/pin/pin_screen.dart';
import '../features/auth/registration/registration_screen.dart';
import '../features/auth/registration/registration_success_screen.dart';
import '../features/profile/account_details_screen.dart';
import '../features/profile/bank_details_screen.dart';
import '../features/profile/screens/bank_verification_hub_screen.dart';
import '../features/profile/screens/bav_history_screen.dart';
import '../features/profile/screens/penny_verify_history_screen.dart';
import '../features/profile/screens/refund_history_screen.dart';
import '../features/withdrawal/screens/withdrawal_screen.dart';
import '../features/withdrawal/screens/withdrawal_confirmation_screen.dart';
import '../features/withdrawal/screens/upi_selection_screen.dart';
import '../features/withdrawal/screens/withdrawal_success_screen.dart';
import '../features/kyc/screens/kyc_screen.dart' as dynamic_kyc;
import '../features/kyc/widgets/aadhaar_digilocker_webview.dart';
import '../features/kyc/widgets/digilocker_sdk_screen.dart';
import '../features/profile/screens/reverse_penny_drop_screen.dart';
import '../features/instant_saving/screens/payment_methods_screen.dart';
import '../features/history/screens/transaction_history_screen.dart';
import '../features/history/screens/transaction_details_screen.dart';
import '../features/content/screens/content_screen.dart';
import '../features/content/screens/faq_screen.dart';
import '../features/content/screens/contact_us_screen.dart';
import '../features/support/screens/enquiry_form_screen.dart';
import '../features/support/screens/enquiry_list_screen.dart';
import '../features/main/main_screen.dart';
import '../core/services/content_service.dart';
import '../features/mpin/change_mpin_screen.dart';
import '../features/maintenance/maintenance_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/screens/delete_account_screen.dart';
import '../features/referral/referee_list_screen.dart';
import '../features/sip/screens/auto_savings_screen.dart';
import '../features/sip/screens/manage_savings_screen.dart';
import '../features/sip/screens/manage_custom_savings_screen.dart';
import '../features/sip/screens/bank_account_picker_screen.dart';
import '../features/sip/screens/sip_cancel_screen.dart';
import '../features/sip/screens/sip_payment_screen.dart';
import '../features/sip/screens/sip_success_screen.dart';
import '../features/sip/screens/sip_failure_screen.dart';
import '../features/sip/screens/sip_transaction_history_screen.dart';
import '../features/sip/screens/sip_transaction_details_screen.dart';
import '../features/sip/screens/sip_overview_screen.dart';
import '../features/nominee/screens/nominee_screen.dart';
import '../features/invoice/invoice_viewer_screen.dart';
import '../features/jewellery/jewellery_screen.dart';

class AppRouter {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String mpin = '/mpin';
  static const String kyc = '/kyc';
  static const String panVerification = '/pan-verification';
  static const String aadhaarVerification = '/aadhaar-verification';
  static const String digilockerSdk = '/digilocker-sdk';
  static const String reversePennyDrop = '/reverse-penny-drop';
  static const String bankVerification = '/bank-verification';
  static const String instantSaving = '/instant-saving';
  static const String dailySavings = '/daily-savings';
  static const String home = '/home';
  static const String main = '/main';
  static const String profile = '/profile';
  static const String support = '/support';
  static const String referral = '/referral';
  static const String settings = '/settings';
  static const String mpinCreation = '/mpin-creation';
  static const String pinEntry = '/pin-entry';
  static const String registration = '/registration';
  static const String withdrawal = '/withdrawal';
  static const String withdrawalConfirmation = '/withdrawal-confirmation';
  static const String payment = '/payment';
  static const String dynamicKyc = '/kyc-dynamic';
  static const String paymentMethods = '/payment-methods';
  static const String terms = '/terms';
  static const String privacy = '/privacy';
  static const String faq = '/faq';
  static const String about = '/about';
  static const String contact = '/contact';
  static const String enquiryForm = '/enquiry-form';
  static const String enquiryList = '/enquiry-list';
  static const String upiSelection = '/upi-selection';
  static const String withdrawalSuccess = '/withdrawal-success';
  static const String registrationSuccess = '/registration-success';
  static const String accountDetails = '/accountdetails';
  static const String bankDetails = '/bank-details';
  static const String transactionHistory = '/transaction-history';
  static const String transactionDetails = '/transaction-details';
  static const String changeMpin = '/change-mpin';
  static const String maintenance = '/maintenance';
  static const String notifications = '/notifications';
  static const String deleteAccount = '/delete-account';
  static const String refereeList = '/referee-list';
  static const String autoSavings = '/auto-savings';
  static const String sipManage = '/sip-manage';
  static const String customSipManage = '/custom-sip-manage';
  static const String bankAccountPicker = '/bank-account-picker';
  static const String bankVerificationHub = '/bank-verification-hub';
  static const String bavHistory = '/bank-verification/bav-history';
  static const String pennyVerifyHistory = '/bank-verification/penny-history';
  static const String refundHistory = '/bank-verification/refund-history';
  static const String sipCancel = '/sip-cancel';
  static const String sipPayment = '/sip-payment';
  static const String sipSuccess = '/sip-success';
  static const String sipFailure = '/sip-failure';
  static const String nominee = '/nominee';
  static const String refundPolicy = '/refund-policy';
  static const String sipTransactions = '/sip-transactions';
  static const String sipTransactionDetails = '/sip-transaction-details';
  static const String sipOverview = '/sip-overview';
  static const String invoiceViewer = '/invoice-viewer';
  static const String jewellery = '/jewellery';

  static Map<String, WidgetBuilder> get routes => {
        splash: (context) => const SplashScreen(),
        onboarding: (context) => const OnboardingScreen(),
        login: (context) => const LoginScreen(),
        otp: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return OtpScreen(
            mobile: args['mobile'],
            countryCode: args['countryCode'] ?? '+91',
            idCountry: args['idCountry'] ?? '101',
            otpReferenceId: args['otpReferenceId'] ?? '',
          );
        },
        mpin: (context) => const MpinScreen(),
        changeMpin: (context) => const ChangeMpinScreen(),
        kyc: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return dynamic_kyc.KycScreen(
            requestFrom: args['request_from'] ?? 'instant',
            extraData: args,
          );
        },
        panVerification: (context) => const PanVerificationScreen(),
        aadhaarVerification: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return AadhaarDigilockerWebView(
            consentUrl: args['consentUrl'] as String,
          );
        },
        digilockerSdk: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return DigilockerSdkScreen(
            sdkToken: args['sdkToken'] as String,
            clientId: args['clientId'] as String?,
            environment: args['environment'] as String?,
          );
        },
        reversePennyDrop: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return ReversePennyDropScreen(cbankId: args['cbankId'] as String);
        },
        bankVerification: (context) =>
            const Scaffold(body: Center(child: Text('Bank Verification'))),
        instantSaving: (context) => const InstantSavingScreen(),
        dailySavings: (context) => const DailySavingsScreen(),
        home: (context) => const MainScreen(),
        main: (context) => const MainScreen(),
        profile: (context) => const ProfileScreen(),
        accountDetails: (context) => const AccountDetailsScreen(),
        bankDetails: (context) => const BankDetailsScreen(),
        transactionHistory: (context) => const TransactionHistoryScreen(),
        transactionDetails: (context) {
          final tx = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return TransactionDetailsScreen(transactionData: tx);
        },
        support: (context) => const SupportScreen(),
        referral: (context) => const ReferralScreen(),
        settings: (context) => const SettingsScreen(),
        mpinCreation: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return PinCreationScreen(
            mobile: args['mobile'] ?? '',
            fullName: args['fullName'] ?? '',
            email: args['email'] ?? '',
            dob: args['dob'] ?? '',
            referralCode: args['referralCode'] ?? '',
            tempToken: args['tempToken'] ?? '',
          );
        },
        pinEntry: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return PinScreen(mobile: args['mobile'] ?? '');
        },
        registration: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return RegistrationScreen(
            mobile: args['mobile'] ?? '',
            tempToken: args['tempToken'] ?? '',
          );
        },
        withdrawal: (context) => const WithdrawalScreen(),
        withdrawalConfirmation: (context) =>
            const WithdrawalConfirmationScreen(),
        payment: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return Scaffold(
            appBar: AppBar(title: const Text('Secure Payment')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.payment_rounded,
                      size: 80, color: Colors.indigo),
                  const SizedBox(height: 24),
                  Text('Completing Payment for ₹${args['amount'] ?? '0'}',
                      style: GoogleFonts.lora(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                      'Plan: ${args['type'] == 'daily_sip' ? 'Daily Savings' : 'One-time'}',
                      style: GoogleFonts.playfairDisplay(color: Colors.grey)),
                  const SizedBox(height: 48),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Home'),
                  )
                ],
              ),
            ),
          );
        },
        dynamicKyc: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return dynamic_kyc.KycScreen(
            requestFrom: args['request_from'] ?? 'instant',
            extraData: args,
          );
        },
        paymentMethods: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return PaymentMethodsScreen(
            amount: args['amount'],
            metalId: args['metal_id'],
            rate: args['rate'],
            couponCode: args['coupon_code'],
            buyType: (args['buy_type'] as int?) ?? 1,
            weight: (args['weight'] as num?)?.toDouble() ?? 0.0,
          );
        },
        terms: (context) => ContentScreen(
              title: 'Terms & Conditions',
              provider: termsProvider,
            ),
        privacy: (context) => ContentScreen(
              title: 'Privacy Policy',
              provider: privacyPolicyProvider,
            ),
        about: (context) => ContentScreen(
              title: 'About Us',
              provider: aboutUsProvider,
            ),
        faq: (context) => const FaqScreen(),
        contact: (context) => const ContactUsScreen(),
        enquiryForm: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return EnquiryFormScreen(
            initialType: args['initial_type'] as String?,
          );
        },
        enquiryList: (context) => const EnquiryListScreen(),
        upiSelection: (context) => const UpiSelectionScreen(),
        withdrawalSuccess: (context) => WithdrawalSuccessScreen(
            data: ModalRoute.of(context)!.settings.arguments
                as Map<String, dynamic>),
        registrationSuccess: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return RegistrationSuccessScreen(fullName: args['fullName'] ?? '');
        },
        maintenance: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return MaintenanceScreen(
            resumeRoute: args['resumeRoute'] as String? ?? AppRouter.login,
          );
        },
        notifications: (context) => const NotificationsScreen(),
        deleteAccount: (context) => const DeleteAccountScreen(),
        refereeList: (context) => const RefereeListScreen(),
        autoSavings: (context) => const AutoSavingsScreen(),
        sipManage: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return ManageSavingsScreen(
            subscriptionId: args['subscription_id'] ?? '',
          );
        },
        customSipManage: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return ManageCustomSavingsScreen(
            schemeId: int.tryParse(args['scheme_id']?.toString() ?? '0') ?? 0,
          );
        },
        bankAccountPicker: (context) => const BankAccountPickerScreen(),
        bankVerificationHub: (context) => const BankVerificationHubScreen(),
        bavHistory: (context) => const BavHistoryScreen(),
        pennyVerifyHistory: (context) => const PennyVerifyHistoryScreen(),
        refundHistory: (context) => const RefundHistoryScreen(),
        sipCancel: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>? ??
              {};
          return SipCancelScreen(
            subscriptionId: args['subscription_id'] ?? '',
            cancelEligibleAt:
                DateTime.tryParse(args['cancel_eligible_at']?.toString() ?? '')
                    ?.toLocal(),
            canCancelNow: args['can_cancel_now'] == null
                ? true
                : args['can_cancel_now'] == true,
            isCustom: args['is_custom'] == true,
            schemeId: args['scheme_id'] == null
                ? null
                : int.tryParse(args['scheme_id'].toString()),
          );
        },
        sipPayment: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return SipPaymentScreen(paymentData: args);
        },
        sipSuccess: (context) => SipSuccessScreen(
            data: ModalRoute.of(context)!.settings.arguments
                as Map<String, dynamic>),
        sipFailure: (context) => SipFailureScreen(
            data: ModalRoute.of(context)!.settings.arguments
                as Map<String, dynamic>),
        nominee: (context) => const NomineeScreen(),
        refundPolicy: (context) => ContentScreen(
              title: 'Refund Policy',
              provider: refundPolicyProvider,
            ),
        sipTransactions: (context) => const SipTransactionHistoryScreen(),
        sipTransactionDetails: (context) {
          final tx = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return SipTransactionDetailsScreen(transactionData: tx);
        },
        sipOverview: (context) => const SipOverviewScreen(),
        invoiceViewer: (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>;
          return InvoiceViewerScreen(
            filePath: args['file_path'] as String,
            title: args['title'] as String? ?? 'Invoice',
          );
        },
        jewellery: (context) => const JewelleryScreen(),
      };

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    if (routes.containsKey(settings.name)) {
      return MaterialPageRoute(
        builder: (context) => routes[settings.name]!(context),
        settings: settings,
      );
    }
    // Fallback: unknown or null route — redirect to the correct screen.
    // This catches edge cases where the navigator stack is empty
    // (e.g. back-press from a pushReplacement chain) and prevents
    // the user from ever seeing a "Page Not Found" screen.
    //
    // Authenticated users → MPIN (re-verify identity)
    // Unauthenticated users → Login
    debugPrint('[AppRouter] Unknown route "${settings.name}" — redirecting.');
    return MaterialPageRoute(
      builder: (context) {
        // Use addPostFrameCallback to navigate after the current frame,
        // avoiding "setState during build" issues.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          String fallbackRoute = AppRouter.login;
          try {
            final loggedIn = await SessionManager.isAuthenticated();
            final mpinEnabled = await SecureStorageService.isMpinEnabled();
            if (loggedIn && mpinEnabled) {
              fallbackRoute = AppRouter.mpin;
            }
          } catch (_) {}
          if (context.mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              fallbackRoute,
              (route) => false,
            );
          }
        });
        // Show a brief loading spinner while determining destination
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
