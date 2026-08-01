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

class AccountDetailsScreen extends ConsumerStatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  ConsumerState<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends ConsumerState<AccountDetailsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _dobController;
  late TextEditingController _pincodeController;
  late TextEditingController _stateController;
  late TextEditingController _cityController;
  late TextEditingController _addressController;
  bool _isPincodeChecking = false;
  String? _emailError;
  bool _isPincodeValid = true;

  // Returns true only when all mandatory fields have content
  bool get _canSave {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final pincode = _pincodeController.text.trim();
    return name.isNotEmpty && email.isNotEmpty && pincode.length == 6 && _isPincodeValid;
  }

  @override
  void initState() {
    super.initState();
    final user = ref.read(profileProvider).user;
    _nameController = TextEditingController(text: user.name);
    _emailController = TextEditingController(text: user.email);
    _dobController = TextEditingController(text: user.dob);
    _pincodeController = TextEditingController(text: user.pincode);
    _stateController = TextEditingController(text: user.state);
    _cityController = TextEditingController(text: user.city);
    _addressController = TextEditingController(text: user.address);

    // Rebuild whenever mandatory fields change so Save button reacts live
    _nameController.addListener(() => setState(() {}));
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
        _nameController.text = updated.name;
        _emailController.text = updated.email;
        _dobController.text = updated.dob;
        _pincodeController.text = updated.pincode;
        _stateController.text = updated.state;
        _cityController.text = updated.city;
        _addressController.text = updated.address;
      });
    });
  }

  @override
  void dispose() {
    // Reset editing state so it doesn't persist when navigating away
    Future.microtask(() {
      ref.read(profileProvider.notifier).setEditing(false);
    });
    _nameController.dispose();
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
      setState(() => _isPincodeValid = true);
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
        _isPincodeValid = false;
        _stateController.text = '';
        _cityController.text = '';
      });
      AppToast.show(context, result['message']?.toString() ?? 'Pincode not found.', type: ToastType.error);
    }
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
    return regex.hasMatch(email);
  }

  Future<void> _handleSubmit() async {
    // â”€â”€ Validate Name â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, 'Name as per PAN is required', type: ToastType.error);
      return;
    }

    // â”€â”€ Validate Email â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'E-Mail is required');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _emailError = 'Enter a valid e-mail address');
      return;
    }
    setState(() => _emailError = null);

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

    final success = await ref.read(profileProvider.notifier).updateProfile(
          name: name,
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
        _nameController.text = next.user.name;
        _emailController.text = next.user.email;
        _dobController.text = next.user.dob;
        _pincodeController.text = next.user.pincode;
        _stateController.text = next.user.state;
        _cityController.text = next.user.city;
        _addressController.text = next.user.address;
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
                  final name = _nameController.text.trim();
                  final pincode = _pincodeController.text.trim();
                  if (name.isEmpty) {
                    AppToast.show(context, 'Name as per PAN is required', type: ToastType.error);
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
                        _buildInputField(label: 'Name as per PAN *', controller: _nameController, isEditable: profileState.isEditing, isDark: isDark, textCapitalization: TextCapitalization.words, inputFormatters: [UpperCaseWordsFormatter()]),
                        _buildInputField(label: 'Phone Number *', hint: MaskingUtils.maskMobile(user.phone), isEditable: false, isDark: isDark, isNumeric: true),
                        _buildInputField(label: 'E-Mail *', controller: _emailController, isEditable: profileState.isEditing, isDark: isDark, keyboardType: TextInputType.emailAddress, errorText: _emailError, onChanged: (_) { if (_emailError != null) setState(() => _emailError = null); }),
                        _buildInputField(label: 'DOB *', hint: user.dob, isEditable: false, isDark: isDark, isNumeric: true),
                        _buildInputField(label: 'Pincode *', controller: _pincodeController, isEditable: profileState.isEditing, isDark: isDark, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)], actionLabel: 'Check', onAction: _handlePincodeCheck, isActionLoading: _isPincodeChecking, onChanged: (_) { if (!_isPincodeValid) setState(() => _isPincodeValid = true); }, isNumeric: true),
                        if (_stateController.text.isNotEmpty)
                          _buildInputField(label: 'State', controller: _stateController, isEditable: false, isDark: isDark),
                        if (_cityController.text.isNotEmpty)
                          _buildInputField(label: 'City', controller: _cityController, isEditable: false, isDark: isDark),
                        _buildInputField(label: 'Residential Address', controller: _addressController, isEditable: profileState.isEditing, isDark: isDark, maxLines: 4, textCapitalization: TextCapitalization.words, inputFormatters: [UpperCaseWordsFormatter()]),
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

  Widget _buildInputField({
    required String label,
    TextEditingController? controller,
    String? hint,
    bool isEditable = true,
    bool isDark = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? actionLabel,
    VoidCallback? onAction,
    bool isActionLoading = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    ValueChanged<String>? onChanged,
    bool isNumeric = false,
  }) {
    String displayValue = controller?.text ?? hint ?? '';
    if (label.contains('DOB')) displayValue = _formatDate(displayValue);

    final valueStyle = isNumeric
        ? GoogleFonts.lora(fontSize: 16.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white54 : const Color(0xFF333333))
        : GoogleFonts.playfairDisplay(fontSize: 16.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white54 : const Color(0xFF333333));
    final inputStyle = isNumeric
        ? GoogleFonts.lora(fontSize: 16.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white : const Color(0xFF333333))
        : GoogleFonts.playfairDisplay(fontSize: 16.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white : const Color(0xFF333333));
    final hintStyle = isNumeric
        ? GoogleFonts.lora(fontSize: 16.sp, color: Colors.grey)
        : GoogleFonts.playfairDisplay(fontSize: 16.sp, color: Colors.grey);

    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                if (actionLabel != null && isEditable)
                  GestureDetector(
                    onTap: isActionLoading ? null : onAction,
                    child: Padding(
                      padding: EdgeInsets.only(left: 12.w),
                      child: isActionLoading
                        ? SizedBox(height: 16.h, width: 16.h, child: const CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0E5723)))
                        : Text(actionLabel, style: GoogleFonts.playfairDisplay(fontSize: 16.sp, fontWeight: FontWeight.bold, color: const Color(0xFF0E5723))),
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
