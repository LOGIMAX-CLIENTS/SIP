import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';
import '../../core/utils/masking_utils.dart';
import 'profile_controller.dart';
import 'widgets/profile_photo_widget.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/gradient_header.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/secure_clipboard.dart';
import '../../shared/utils/upper_case_words_formatter.dart';
import '../../shared/utils/address_input_formatter.dart';
import '../../core/utils/validators.dart';
import '../auth/controller/auth_controller.dart';
import '../../core/services/auth_service.dart';
import '../auth/registration/email_otp_sheet.dart';
import 'package:startgold/shared/utils/dob_input_formatter.dart';
import 'package:startgold/shared/widgets/dob_date_picker.dart';

class AccountDetailsScreen extends ConsumerStatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  ConsumerState<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends ConsumerState<AccountDetailsScreen> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _dobController;
  late TextEditingController _pincodeController;
  late TextEditingController _stateController;
  late TextEditingController _cityController;
  late TextEditingController _addressController;
  bool _isPincodeChecking = false;
  bool _isVerifyingEmail = false;
  String? _emailError;
  String? _dobError;

  // Verified baselines.
  // A pincode / e-mail counts as verified only while it EXACTLY matches the
  // value that was confirmed - either the value already on file (loaded from
  // the profile, so it was validated when it was saved) or one the customer
  // confirmed in this session via 'Check' / 'Verify'. Editing the field away
  // from that value invalidates it and Save disables again.
  // Empty string = nothing confirmed yet.
  String _verifiedPincode = '';
  String _verifiedEmail = '';

  /// True only when the pincode in the box is 6 digits AND confirmed.
  bool get _isPincodeConfirmed {
    final pincode = _pincodeController.text.trim();
    return pincode.length == 6 && pincode == _verifiedPincode;
  }

  /// True only when the e-mail in the box is well-formed AND confirmed.
  bool get _isEmailConfirmed {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || Validators.validateEmail(email) != null) return false;
    return email == _verifiedEmail;
  }

  /// Adopts whatever the server currently reports as confirmed for this
  /// customer, so an untouched profile does not force a needless re-check.
  void _syncVerifiedBaseline(UserProfile user) {
    _verifiedPincode = user.pincode.trim();
    _verifiedEmail = user.isEmailVerified ? user.email.trim().toLowerCase() : '';
  }

  // Save needs every mandatory field filled AND both the pincode and the
  // e-mail confirmed.
  bool get _canSave {
    final firstName = _firstNameController.text.trim();
    return firstName.isNotEmpty && _isEmailConfirmed && _isPincodeConfirmed;
  }

  @override
  void initState() {
    super.initState();
    final user = ref.read(profileProvider).user;
    _firstNameController = TextEditingController(text: user.firstName);
    _lastNameController = TextEditingController(text: user.lastName);
    _emailController = TextEditingController(text: user.email);
    // Seeded in DD/MM/YYYY, not the API's ISO — this field is editable now,
    // so its text is what the customer reads and types. profile/update
    // accepts either shape (see identity.py's dob branch).
    _dobController = TextEditingController(text: _toDisplayDob(user.dob));
    _pincodeController = TextEditingController(text: user.pincode);
    _stateController = TextEditingController(text: user.state);
    _cityController = TextEditingController(text: user.city);
    _addressController = TextEditingController(text: user.address);
    _syncVerifiedBaseline(user);

    // Rebuild whenever mandatory fields change so Save button reacts live
    _firstNameController.addListener(() => setState(() {}));
    _emailController.addListener(() => setState(() {}));
    _pincodeController.addListener(() => setState(() {}));

    // Always re-fetch on screen entry â€” profileProvider is a persistent singleton
    // so its constructor only runs once; we must manually refresh each visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always start in view mode — reset any stale editing state
      ref.read(profileProvider.notifier).setEditing(false);
      ref.read(profileProvider.notifier).fetchProfileDetails().then((_) {
        if (!mounted) return;
        // Sync controllers with freshly loaded data
        final updated = ref.read(profileProvider).user;
        _firstNameController.text = updated.firstName;
        _lastNameController.text = updated.lastName;
        _emailController.text = updated.email;
        _dobController.text = _toDisplayDob(updated.dob);
        _pincodeController.text = updated.pincode;
        _stateController.text = updated.state;
        _cityController.text = updated.city;
        _addressController.text = updated.address;
        setState(() => _syncVerifiedBaseline(updated));
      });
    });
  }

  @override
  void dispose() {
    // Reset editing state so it doesn't persist when navigating away.
    // Resolve the notifier NOW: `ref` belongs to this widget and must not be
    // touched from the microtask, which runs after dispose() has returned.
    final profile = ref.read(profileProvider.notifier);
    Future.microtask(() => profile.setEditing(false));
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _pincodeController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _handlePincodeCheck() async {
    if (_pincodeController.text.length != 6) return;
    setState(() => _isPincodeChecking = true);
    final result = await ref.read(profileProvider.notifier).checkPincode(_pincodeController.text);
    if (!mounted) return;
    setState(() => _isPincodeChecking = false);
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      setState(() => _verifiedPincode = _pincodeController.text.trim());
      _stateController.text = data['state'] ?? '';
      _cityController.text = data['city'] ?? '';
      ref.read(profileProvider.notifier).updateLocationInfo(
            stateVal: data['state'] ?? '',
            city: data['city'] ?? '',
            idCountry: data['id_country'] ?? '101',
            idState: data['id_state'] ?? '',
            idCity: data['id_city'] ?? '',
          );
    } else {
      setState(() {
        _verifiedPincode = '';
        _stateController.text = '';
        _cityController.text = '';
      });
      AppToast.show(context, result['message']?.toString() ?? 'Pincode not found.', type: ToastType.error);
    }
  }

  /// Verifies the customer's on-file e-mail — same OTP sheet as onboarding
  /// (RegistrationScreen._verifyEmail), but this re-verifies an EXISTING
  /// account's address rather than a not-yet-registered one, so on success
  /// we re-fetch the profile (picks up the backend's persisted
  /// cus_email_verified_on — see AuthService.verify_email_otp) instead of
  /// just flipping local widget state.
  Future<void> _verifyEmail() async {
    final email = _emailController.text.trim();
    final emailError = Validators.validateEmail(email);
    if (emailError != null) {
      AppToast.show(context, emailError, type: ToastType.error);
      return;
    }

    setState(() => _isVerifyingEmail = true);
    final success = await ref.read(authControllerProvider.notifier).sendEmailOtp(
          email,
          firstName: _firstNameController.text.trim().isNotEmpty
              ? _firstNameController.text.trim()
              : null,
        );

    if (!mounted) return;
    setState(() => _isVerifyingEmail = false);
    if (!success) return;

    final otpReferenceId =
        ref.read(authControllerProvider).data?['otp_reference_id'] as String?;
    if (otpReferenceId == null) return;

    final verified = await showEmailOtpSheet(
      context,
      email: email,
      otpReferenceId: otpReferenceId,
      firstName: _firstNameController.text.trim(),
    );

    if (verified == true && mounted) {
      // Record it locally first: the customer may have just verified a NEW
      // address, so do not make Save wait on what the refetch reports.
      setState(() => _verifiedEmail = email.toLowerCase());
      await ref.read(profileProvider.notifier).fetchProfileDetails();
      if (mounted) {
        AppToast.show(context, 'E-mail verified successfully', type: ToastType.success);
      }
    }
  }

  Future<void> _handleSubmit() async {
    // â”€â”€ Validate Name â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    if (firstName.isEmpty) {
      AppToast.show(context, 'First name as per PAN is required', type: ToastType.error);
      return;
    }
    if (firstName.length < 2) {
      AppToast.show(context, 'Enter a valid first name', type: ToastType.error);
      return;
    }

    // -- Validate DOB ------------------------------------------------------
    // The field is typed now, so an incomplete or impossible date can reach
    // here. Worth failing loudly: profile/update's own dob branch swallows a
    // malformed value silently (`except (ValueError, TypeError): pass`), so
    // without this the customer would be told "Profile updated successfully"
    // while their DOB was quietly dropped.
    final dobText = _dobController.text.trim();
    if (dobText.isEmpty) {
      setState(() => _dobError = 'Date of birth is required');
      return;
    }
    final parsedDob = DobInputFormatter.parse(dobText);
    if (parsedDob == null) {
      setState(() => _dobError = 'Enter a valid date as DD/MM/YYYY');
      return;
    }
    final nowForDob = DateTime.now();
    if (parsedDob.isAfter(DateTime(nowForDob.year - 18, nowForDob.month, nowForDob.day))) {
      setState(() => _dobError = 'You must be at least 18 years old');
      return;
    }
    setState(() => _dobError = null);

    // â”€â”€ Validate Email â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final email = _emailController.text.trim();
    final emailFormatError = Validators.validateEmail(email);
    if (emailFormatError != null) {
      setState(() => _emailError = emailFormatError);
      return;
    }
    setState(() => _emailError = null);
    if (!_isEmailConfirmed) {
      AppToast.show(context, 'Please verify your e-mail before saving', type: ToastType.error);
      return;
    }

    // â”€â”€ Validate Pincode â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final pincode = _pincodeController.text.trim();
    if (pincode.isEmpty) {
      AppToast.show(context, 'Pincode is required', type: ToastType.error);
      return;
    }
    if (pincode.length != 6) {
      AppToast.show(context, 'Please enter a valid 6-digit pincode', type: ToastType.error);
      return;
    }
    if (!_isPincodeConfirmed) {
      AppToast.show(context, 'Please tap Check to verify your pincode', type: ToastType.error);
      return;
    }

    final success = await ref.read(profileProvider.notifier).updateProfile(
          firstName: firstName,
          lastName: lastName,
          email: email,
          dob: _dobController.text,
          pincode: pincode,
          stateVal: _stateController.text,
          city: _cityController.text,
          address: _addressController.text,
        );
    if (success && mounted) {
      AppToast.show(context, 'Profile updated successfully', type: ToastType.success);
    } else if (mounted) {
      final errorMsg = ref.read(profileProvider).error ?? 'Failed to update profile. Please try again.';
      AppToast.show(context, errorMsg, type: ToastType.error);
    }
  }

  Future<void> _handlePhotoUpdate(File photo) async {
    final success = await ref.read(profileProvider.notifier).updateProfilePhoto(photo);
    if (mounted) {
      if (success) {
        AppToast.show(context, 'Profile photo updated successfully', type: ToastType.success);
      } else {
        AppToast.show(context, 'Failed to update profile photo', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileState = ref.watch(profileProvider);
    final user = profileState.user;

    ref.listen(profileProvider, (previous, next) {
      if (!next.isEditing && (previous == null || previous.user != next.user)) {
        _firstNameController.text = next.user.firstName;
        _lastNameController.text = next.user.lastName;
        _emailController.text = next.user.email;
        _dobController.text = _toDisplayDob(next.user.dob);
        _pincodeController.text = next.user.pincode;
        _stateController.text = next.user.state;
        _cityController.text = next.user.city;
        _addressController.text = next.user.address;
        _syncVerifiedBaseline(next.user);
      }
    });

    // email_otp_sheet.dart relies on the caller to surface auth errors
    // (e.g. OTP send failures) — same listener RegistrationScreen uses.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error && mounted) {
        AppToast.show(context, next.error!, type: ToastType.error);
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // â”€â”€ Gradient Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          GradientHeader(
            title: 'Account Details',
            trailing: TextButton.icon(
              onPressed: () {
                if (profileState.isEditing) {
                  // Block cancel if mandatory fields are empty
                  final firstName = _firstNameController.text.trim();
                  final pincode = _pincodeController.text.trim();
                  if (firstName.isEmpty) {
                    AppToast.show(context, 'First name as per PAN is required', type: ToastType.error);
                    return;
                  }
                  if (pincode.length != 6) {
                    AppToast.show(context, 'Please enter a valid 6-digit pincode', type: ToastType.error);
                    return;
                  }
                }
                ref.read(profileProvider.notifier).setEditing(!profileState.isEditing);
              },
              icon: Icon(
                profileState.isEditing ? Icons.close_rounded : Icons.edit_rounded,
                color: Colors.white,
                size: 18.sp,
              ),
              label: Text(
                profileState.isEditing ? 'Cancel' : 'Edit',
                style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),

          // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Expanded(
            child: profileState.isLoading && user.name.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppTheme.arcticBlue))
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 16.h),
                        Center(
                          child: ProfilePhotoWidget(
                            initialPhotoUrl: user.photoUrl,
                            initials: user.name.isNotEmpty
                                ? user.name
                                    .split(' ')
                                    .where((e) => e.isNotEmpty)
                                    .map((e) => e[0])
                                    .take(2)
                                    .join('')
                                    .toUpperCase()
                                : '??',
                            onPhotoSelected: _handlePhotoUpdate,
                            isLoading: profileState.isPhotoLoading,
                          ),
                        ),
                        SizedBox(height: 32.h),
                        _buildInputField(label: 'First Name as per PAN *', controller: _firstNameController, isEditable: profileState.isEditing, isDark: isDark, textCapitalization: TextCapitalization.words, inputFormatters: [UpperCaseWordsFormatter(), LengthLimitingTextInputFormatter(30)]),
                        _buildInputField(label: 'Last Name as per PAN (Optional)', controller: _lastNameController, isEditable: profileState.isEditing, isDark: isDark, textCapitalization: TextCapitalization.words, inputFormatters: [UpperCaseWordsFormatter(), LengthLimitingTextInputFormatter(30)]),
                        _buildInputField(label: 'Phone Number *', hint: MaskingUtils.maskMobile(user.phone), isEditable: false, isDark: isDark, isNumeric: true),
                        _buildInputField(label: 'E-Mail *', controller: _emailController, isEditable: profileState.isEditing, isDark: isDark, keyboardType: TextInputType.emailAddress, errorText: _emailError, onChanged: (_) { if (_emailError != null) setState(() => _emailError = null); }, actionWidget: _buildEmailVerifyBadge(user, isDark)),
                        _buildInputField(label: 'DOB *', controller: _dobController, isEditable: profileState.isEditing, isDark: isDark, isNumeric: true, keyboardType: TextInputType.number, inputFormatters: [DobInputFormatter()], errorText: _dobError, onChanged: (_) { if (_dobError != null) setState(() => _dobError = null); }, actionIcon: Icons.calendar_today_rounded, onAction: profileState.isEditing ? _selectDob : null),
                        _buildInputField(label: 'Pincode *', controller: _pincodeController, isEditable: profileState.isEditing, isDark: isDark, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)], actionLabel: 'Check', onAction: _handlePincodeCheck, isActionLoading: _isPincodeChecking, isNumeric: true),
                        if (_stateController.text.isNotEmpty)
                          _buildInputField(label: 'State', controller: _stateController, isEditable: false, isDark: isDark),
                        if (_cityController.text.isNotEmpty)
                          _buildInputField(label: 'City', controller: _cityController, isEditable: false, isDark: isDark),
                        _buildInputField(label: 'Residential Address', controller: _addressController, isEditable: profileState.isEditing, isDark: isDark, maxLines: 4, textCapitalization: TextCapitalization.words, inputFormatters: [AddressInputFormatter()]),
                        SizedBox(height: 40.h),
                      ],
                    ),
                  ),
          ),

          // â”€â”€ Footer Save Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (profileState.isEditing)
            SafeArea(
              top: false,
              child: Container(
                padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 16.h),
                decoration: const BoxDecoration(color: Colors.transparent),
                child: CustomButton(
                  text: 'Save', svgIconPath: 'assets/buttons/folder-add.svg',
                  isLoading: profileState.isLoading,
                  onPressed: (profileState.isLoading || !_canSave)
                      ? null
                      : _handleSubmit,
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: _canSave
                        ? const [Color(0xFF1B882C), Color(0xFF003716)]
                        : [
                            const Color(0xFF1B882C).withOpacity(0.4),
                            const Color(0xFF003716).withOpacity(0.4),
                          ],
                  ),
                  boxShadow: _canSave
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1B882C).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                  textColor: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// API DOB (ISO `2000-12-11`) -> the `DD/MM/YYYY` the field shows and the
  /// customer types. Passes an already-formatted value straight through, so
  /// re-seeding after a save doesn't mangle it.
  String _toDisplayDob(String apiDob) {
    if (apiDob.isEmpty) return '';
    final iso = DateTime.tryParse(apiDob);
    if (iso != null && apiDob.contains('-')) return DobInputFormatter.formatDate(iso);
    return apiDob;
  }

  /// Calendar for the DOB field. `calendarOnly` deliberately drops the
  /// picker's own keyboard-entry mode — it parses by locale (en_US =>
  /// MM/DD/YYYY) and is what rejects "19061992" with "Invalid format.";
  /// typing is handled by DobInputFormatter on the field itself.
  Future<void> _selectDob() async {
    final now = DateTime.now();
    final maxDob = DateTime(now.year - 18, now.month, now.day);
    final typed = DobInputFormatter.parse(_dobController.text);
    // See RegistrationScreen's _selectDate — the stock picker has no month
    // step, so DOB uses showDobPicker on both screens.
    final picked = await showDobPicker(
      context: context,
      initialDate: (typed != null && !typed.isAfter(maxDob)) ? typed : maxDob,
      firstDate: DateTime(1900),
      lastDate: maxDob,
    );
    if (picked != null && mounted) {
      setState(() => _dobController.text = DobInputFormatter.formatDate(picked));
    }
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }

  /// Mirrors RegistrationScreen's E-Mail label row — a "Verify" link when
  /// unverified, a green "Verified" badge when verified. `_verifyEmail()`
  /// already sends the OTP to whatever is currently typed (not necessarily
  /// [user.email]), so the "Verify" link stays available while editing —
  /// letting the customer verify a freshly-typed NEW address inline instead
  /// of only being able to re-verify the address already on file. The
  /// "Verified" badge itself is still gated on matching the on-file
  /// [user.email] — a newly-typed address is never already verified.
  Widget _buildEmailVerifyBadge(UserProfile user, bool isDark) {
    final currentInput = _emailController.text.trim().toLowerCase();
    if (currentInput.isEmpty || Validators.validateEmail(currentInput) != null) {
      return const SizedBox.shrink();
    }
    // Same predicate the Save gate uses, so the badge can never say 'Verify'
    // while Save is enabled (or the reverse) - it covers both the already
    // verified on-file address and one verified in this session.
    if (_isEmailConfirmed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14.sp, color: const Color(0xFF1B882C)),
          SizedBox(width: 4.w),
          Text('Verified', style: GoogleFonts.playfairDisplay(fontSize: 13.sp, fontWeight: FontWeight.w600, color: const Color(0xFF1B882C))),
        ],
      );
    }

    // Whole padded region is the tap target, not just the word — same reason
    // as RegistrationScreen's _buildEmailVerifyAction. HitTestBehavior.opaque
    // makes the transparent padding count as part of the button.
    return GestureDetector(
      onTap: _isVerifyingEmail ? null : _verifyEmail,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
        child: _isVerifyingEmail
            ? SizedBox(height: 14.h, width: 14.h, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent))
            : Text('Verify', style: GoogleFonts.playfairDisplay(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.orangeAccent, decoration: TextDecoration.underline)),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    TextEditingController? controller,
    String? hint,
    bool isEditable = true,
    bool isDark = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? actionLabel,
    /// Renders instead of [actionLabel] when set — for actions better shown as
    /// a glyph than a word (the DOB calendar).
    IconData? actionIcon,
    /// An arbitrary widget rendered INSIDE the value box (unlike [labelAction],
    /// which sits beside the label). Not gated on [isEditable] — the widget
    /// itself decides what to show per state, e.g. the e-mail Verify link vs
    /// its Verified badge.
    Widget? actionWidget,
    VoidCallback? onAction,
    bool isActionLoading = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    ValueChanged<String>? onChanged,
    bool isNumeric = false,
    // Shown next to the LABEL (not inside the value box, unlike
    // actionLabel/onAction above) — always visible regardless of edit
    // mode, for actions independent of editing the field's value (e.g.
    // e-mail verification).
    Widget? labelAction,
  }) {
    String displayValue = controller?.text ?? hint ?? '';
    if (label.contains('DOB')) displayValue = _formatDate(displayValue);

    // Playfair Display ships OLDSTYLE figures by default — digits are drawn at
    // varying heights, which is why an e-mail like "sankarguru.8750@..." looked
    // like the numbers were bouncing up and down. liningFigures forces uniform
    // cap-height digits; tabularFigures keeps them evenly spaced.
    const digitFeatures = [FontFeature.liningFigures(), FontFeature.tabularFigures()];

    final valueStyle = isNumeric
        ? GoogleFonts.lora(fontSize: 16.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white54 : const Color(0xFF333333))
        : GoogleFonts.playfairDisplay(fontSize: 16.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white54 : const Color(0xFF333333), fontFeatures: digitFeatures);
    final inputStyle = isNumeric
        ? GoogleFonts.lora(fontSize: 16.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white : const Color(0xFF333333))
        : GoogleFonts.playfairDisplay(fontSize: 16.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white : const Color(0xFF333333), fontFeatures: digitFeatures);
    final hintStyle = isNumeric
        ? GoogleFonts.lora(fontSize: 16.sp, color: Colors.grey)
        : GoogleFonts.playfairDisplay(fontSize: 16.sp, color: Colors.grey, fontFeatures: digitFeatures);

    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (labelAction != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: GoogleFonts.playfairDisplay(fontSize: 15.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : const Color(0xFF8D8D8D))),
                labelAction,
              ],
            )
          else
            Text(label, style: GoogleFonts.playfairDisplay(fontSize: 15.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : const Color(0xFF8D8D8D))),
          SizedBox(height: 8.h),
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(15.r),
              border: Border.all(color: errorText != null ? Colors.redAccent : (isDark ? Colors.white10 : Colors.black.withOpacity(0.1))),
              boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Row(
              children: [
                Expanded(
                  child: isEditable
                      ? TextField(
                          controller: controller,
                          maxLines: maxLines,
                          keyboardType: keyboardType,
                          textCapitalization: textCapitalization,
                          inputFormatters: inputFormatters,
                          onChanged: onChanged,
                          contextMenuBuilder: SecureClipboard.none,
                          style: inputStyle,
                          decoration: InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12.h), hintStyle: hintStyle),
                        )
                      : Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          child: Text(displayValue, style: valueStyle),
                        ),
                ),
                if (actionWidget != null)
                  Padding(padding: EdgeInsets.only(left: 12.w), child: actionWidget),
                if ((actionLabel != null || actionIcon != null) && isEditable)
                  GestureDetector(
                    onTap: isActionLoading ? null : onAction,
                    child: Padding(
                      padding: EdgeInsets.only(left: 12.w),
                      child: isActionLoading
                        ? SizedBox(height: 16.h, width: 16.h, child: const CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0E5723)))
                        : actionIcon != null
                            ? Icon(actionIcon, size: 20.sp, color: const Color(0xFF0E5723))
                            : Text(actionLabel!, style: GoogleFonts.playfairDisplay(fontSize: 16.sp, fontWeight: FontWeight.bold, color: const Color(0xFF0E5723))),
                    ),
                  ),
              ],
            ),
          ),
          if (errorText != null) ...[
            SizedBox(height: 6.h),
            Text(errorText, style: GoogleFonts.playfairDisplay(fontSize: 12.sp, color: Colors.redAccent, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}
