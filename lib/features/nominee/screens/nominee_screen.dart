import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import '../../../shared/utils/upper_case_words_formatter.dart';
import '../../../shared/utils/address_input_formatter.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../core/security/secure_logger.dart';
import '../../../core/utils/validators.dart';
import '../../profile/profile_controller.dart' as pc;
import '../controller/nominee_controller.dart';
import '../models/nominee_model.dart';

/// Nominee Details screen.
///
/// â€¢ On load â†’ fetches existing nominee via API.
/// â€¢ If data exists â†’ shows view mode with "Edit" option.
/// â€¢ If not â†’ shows empty form for adding.
class NomineeScreen extends ConsumerStatefulWidget {
  const NomineeScreen({super.key});

  @override
  ConsumerState<NomineeScreen> createState() => _NomineeScreenState();
}

class _NomineeScreenState extends ConsumerState<NomineeScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _idNumberCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  String? _selectedRelationship;
  int? _selectedRelationshipId;
  String? _selectedIdType;
  DateTime? _selectedDob;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isInitialized = false;
  bool _isPincodeChecking = false;
  bool _isPincodeValid = true;

  // Location IDs from pincode check or existing data
  int? _idCity;
  int? _idState;
  int? _idCountry;
  int? _nomineeId;

  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    // Force fresh API calls every time the screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(nomineeDetailsProvider);
      ref.invalidate(nomineeRelationshipsProvider);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _idNumberCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  /// Populate form fields from existing nominee data.
  void _populateFields(NomineeDetails nominee) {
    _nomineeId = nominee.id;
    _nameCtrl.text = nominee.name;
    _mobileCtrl.text = nominee.mobile;
    _emailCtrl.text = nominee.email ?? '';
    _idNumberCtrl.text = nominee.idNumber ?? '';
    _addressCtrl.text = nominee.address ?? '';
    _cityCtrl.text = nominee.city ?? '';
    _stateCtrl.text = nominee.state ?? '';
    _pincodeCtrl.text = nominee.pincode ?? '';
    _selectedRelationship =
        nominee.relationship.isNotEmpty ? nominee.relationship : null;
    _selectedRelationshipId = nominee.relationshipId;
    _idCity = nominee.idCity;
    _idState = nominee.idState;
    _idCountry = nominee.idCountry;
    _selectedIdType = (nominee.idType != null && nominee.idType!.isNotEmpty)
        ? nominee.idType
        : null;
    if (nominee.dob.isNotEmpty) {
      try {
        _selectedDob = _parseDob(nominee.dob);
      } catch (_) {}
    }
  }

  /// Clear all form fields (used when server returns empty nominee data).
  void _clearForm() {
    _nomineeId = null;
    _nameCtrl.clear();
    _mobileCtrl.clear();
    _emailCtrl.clear();
    _idNumberCtrl.clear();
    _addressCtrl.clear();
    _cityCtrl.clear();
    _stateCtrl.clear();
    _pincodeCtrl.clear();
    _selectedRelationship = null;
    _selectedRelationshipId = null;
    _selectedIdType = null;
    _selectedDob = null;
    _idCity = null;
    _idState = null;
    _idCountry = null;
    _isEditing = false;
  }

  @override
  Widget build(BuildContext context) {
    final nomineeAsync = ref.watch(nomineeDetailsProvider);

    // Seed form once when data loads
    ref.listen<AsyncValue<NomineeDetails?>>(nomineeDetailsProvider,
        (prev, next) {
      next.whenData((nominee) {
        if (nominee != null && nominee.isValid) {
          if (!_isInitialized) {
            _populateFields(nominee);
            _isInitialized = true;
          }
        } else {
          // Server returned empty data — clear stale form fields
          _clearForm();
          _isInitialized = false;
        }
      });
    });

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.lightGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            GradientHeader(
              title: 'Nominee Details',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: nomineeAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF064E3B),
                    strokeWidth: 2.5,
                  ),
                ),
                error: (err, _) => _buildErrorState(),
                data: (nominee) {
                  // Seed fields on first load only
                  if (!_isInitialized && nominee != null && nominee.isValid) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _populateFields(nominee);
                      setState(() => _isInitialized = true);
                    });
                  }

                  final hasNominee = nominee != null && nominee.isValid;
                  final showForm = !hasNominee || _isEditing;

                  return FadeTransition(
                    opacity: _fadeController,
                    child: showForm
                        ? _buildFormView(nominee)
                        : _buildDetailView(nominee),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // VIEW MODE
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Widget _buildDetailView(NomineeDetails nominee) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 24.h),

            // â”€â”€ Success banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(
                  color: const Color(0xFF16A34A).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38.w,
                    height: 38.w,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(Icons.verified_user_rounded,
                        size: 20.sp, color: const Color(0xFF16A34A)),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nominee Added',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF166534),
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'Your nominee details are up to date',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 11.sp,
                            color: const Color(0xFF166534).withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20.h),

            // â”€â”€ Details card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                      Icons.person_rounded, 'Full Name', nominee.name),
                  _divider(),
                  _buildDetailRow(Icons.people_rounded, 'Relationship',
                      nominee.relationship),
                  _divider(),
                  _buildDetailRow(Icons.cake_rounded, 'Date of Birth',
                      _formatDisplayDate(nominee.dob), isNumeric: true),
                  _divider(),
                  _buildDetailRow(
                      Icons.phone_rounded, 'Mobile', nominee.mobile, isNumeric: true),
                  if (nominee.email != null && nominee.email!.isNotEmpty) ...[
                    _divider(),
                    _buildDetailRow(
                        Icons.email_rounded, 'Email', nominee.email!,
                        fullWidth: true),
                  ],
                  if (nominee.address != null &&
                      nominee.address!.isNotEmpty) ...[
                    _divider(),
                    _buildDetailRow(
                      Icons.location_on_rounded,
                      'Address',
                      [
                        nominee.address,
                        nominee.city,
                        nominee.state,
                        nominee.pincode,
                      ].where((e) => e != null && e.isNotEmpty).join(', '),
                      fullWidth: true,
                    ),
                  ],
                ],
              ),
            ),

            SizedBox(height: 24.h),

            // â”€â”€ Edit button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            CustomButton(
              text: 'Edit Nominee',
              svgIconPath: 'assets/buttons/profile-add.svg',
              onPressed: () {
                _populateFields(nominee);
                setState(() => _isEditing = true);
              },
              gradient: const LinearGradient(
                colors: [Color(0xFF003716), Color(0xFF167525)],
              ),
            ),

            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {bool fullWidth = false, bool isNumeric = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: fullWidth
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36.w,
                      height: 36.w,
                      decoration: BoxDecoration(
                        color: const Color(0xFF064E3B).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(icon,
                          size: 18.sp, color: const Color(0xFF064E3B)),
                    ),
                    SizedBox(width: 12.w),
                    Text(
                      label,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        color: const Color(0xFF8D8D8D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(left: 48.w, top: 6.h),
                  child: NumericStyledText(
                    value,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF333333),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 36.w,
                  height: 36.w,
                  decoration: BoxDecoration(
                    color: const Color(0xFF064E3B).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(icon,
                      size: 18.sp, color: const Color(0xFF064E3B)),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 13.sp,
                      color: const Color(0xFF8D8D8D),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Flexible(
                  child: NumericStyledText(
                    value,
                    textAlign: TextAlign.left,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF333333),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        color: Colors.black.withOpacity(0.04),
      );

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // FORM MODE
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Widget _buildFormView(NomineeDetails? existing) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 20.h),

              // â”€â”€ Section: Basic Details â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              _buildSectionLabel('Basic Details'),
              SizedBox(height: 12.h),

              _buildTextField(
                controller: _nameCtrl,
                label: 'Full Name *',
                hint: 'Enter nominee full name',
                icon: Icons.person_rounded,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [
                  UpperCaseWordsFormatter(),
                  LengthLimitingTextInputFormatter(60),
                ],
              ),

              _buildRelationshipDropdown(),

              _buildDateField(),

              SizedBox(height: 20.h),

              // ——— Section: Contact Details ———————————————
              _buildSectionLabel('Contact Details'),
              SizedBox(height: 12.h),

              _buildTextField(
                controller: _mobileCtrl,
                label: 'Mobile Number *',
                hint: '10-digit mobile number',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                isNumeric: true,
              ),

              _buildTextField(
                controller: _emailCtrl,
                label: 'Email ID',
                hint: 'Enter email (optional)',
                icon: Icons.email_rounded,
                keyboardType: TextInputType.emailAddress,
                isOptional: true,
                validator: (v) =>
                    (v == null || v.isEmpty) ? null : Validators.validateEmail(v),
              ),

              SizedBox(height: 20.h),

              // â”€â”€ Section: Address â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              _buildSectionLabel('Address'),
              SizedBox(height: 12.h),

              _buildTextField(
                controller: _pincodeCtrl,
                label: 'Pincode',
                hint: '6-digit pincode',
                icon: Icons.pin_drop_rounded,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                isOptional: true,
                isNumeric: true,
                actionLabel: 'Check',
                onAction: _handlePincodeCheck,
                isActionLoading: _isPincodeChecking,
                onChanged: (_) {
                  if (!_isPincodeValid) {
                    setState(() => _isPincodeValid = true);
                  }
                },
                validator: (v) {
                  if (v != null && v.isNotEmpty && v.length != 6) {
                    return 'Enter valid 6-digit pincode';
                  }
                  return null;
                },
              ),

              // Only show State/City after pincode validation or if data exists
              if (_stateCtrl.text.isNotEmpty || _cityCtrl.text.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: _buildReadOnlyField(
                        label: 'State',
                        value: _stateCtrl.text,
                        icon: Icons.map_rounded,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _buildReadOnlyField(
                        label: 'City',
                        value: _cityCtrl.text,
                        icon: Icons.location_city_rounded,
                      ),
                    ),
                  ],
                ),

              _buildTextField(
                controller: _addressCtrl,
                label: 'Residential Address',
                hint: 'Enter address',
                icon: Icons.location_on_rounded,
                textCapitalization: TextCapitalization.words,
                maxLines: 4,
                inputFormatters: [
                  AddressInputFormatter(),
                ],
                isOptional: true,
              ),

              SizedBox(height: 24.h),

              // â”€â”€ Submit button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              CustomButton(
                text: _isEditing ? 'Update Nominee' : 'Save Nominee',
                svgIconPath: 'assets/buttons/folder-add.svg',
                isLoading: _isSaving,
                loadingText: 'Saving...',
                onPressed: (_isSaving || !_isPincodeValid) ? null : _handleSubmit,
                gradient: const LinearGradient(
                  colors: [Color(0xFF003716), Color(0xFF167525)],
                ),
              ),

              if (_isEditing) ...[
                SizedBox(height: 12.h),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _isEditing = false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.black45,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                      ),
                    ),
                  ),
                ),
              ],

              SizedBox(height: 32.h),
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€â”€ Form Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.playfairDisplay(
        fontSize: 12.sp,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
        color: const Color(0xFF064E3B),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool isOptional = false,
    String? actionLabel,
    VoidCallback? onAction,
    bool isActionLoading = false,
    int maxLines = 1,
    String? errorText,
    ValueChanged<String>? onChanged,
    bool isNumeric = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF8D8D8D),
                ),
              ),
              if (isOptional)
                Text(
                  ' (Optional)',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 11.sp,
                    color: Colors.black26,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
          SizedBox(height: 8.h),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15.r),
              border: Border.all(color: errorText != null ? Colors.redAccent : Colors.black.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    keyboardType: keyboardType,
                    textCapitalization: textCapitalization,
                    maxLength: maxLength,
                    maxLines: maxLines,
                    inputFormatters: inputFormatters,
                    validator: validator,
                    onChanged: onChanged,
                    contextMenuBuilder: SecureClipboard.none,
                    style: isNumeric
                        ? GoogleFonts.lora(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF333333),
                          )
                        : GoogleFonts.playfairDisplay(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF333333),
                          ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                      hintText: hint,
                      hintStyle: GoogleFonts.playfairDisplay(
                        fontSize: 16.sp,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                if (actionLabel != null)
                  GestureDetector(
                    onTap: isActionLoading ? null : onAction,
                    child: Padding(
                      padding: EdgeInsets.only(left: 12.w),
                      child: isActionLoading
                          ? SizedBox(
                              height: 16.h,
                              width: 16.h,
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF0E5723)),
                            )
                          : Text(
                              actionLabel,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0E5723),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          if (errorText != null) ...[
            SizedBox(height: 6.h),
            Text(
              errorText,
              style: GoogleFonts.playfairDisplay(
                fontSize: 12.sp,
                color: Colors.redAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Relationship dropdown using [NomineeRelationship] objects (id + name).
  Widget _buildRelationshipDropdown() {
    final relationships = ref.watch(nomineeRelationshipsProvider).when(
          data: (list) => list,
          loading: () => nomineeRelationships,
          error: (_, __) => nomineeRelationships,
        );

    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Relationship *',
            style: GoogleFonts.playfairDisplay(
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF8D8D8D),
            ),
          ),
          SizedBox(height: 8.h),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15.r),
              border: Border.all(color: Colors.black.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: DropdownButtonFormField<String>(
              value: _selectedRelationship,
              validator: (_) => null,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 22.sp, color: Colors.black38),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                hintText: 'Select relationship',
                hintStyle: GoogleFonts.playfairDisplay(
                  fontSize: 16.sp,
                  color: Colors.grey,
                ),
              ),
              style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF333333),
              ),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(15.r),
              items: relationships
                  .map((rel) => DropdownMenuItem(
                        value: rel.name,
                        child: Text(rel.name),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedRelationship = v;
                  final match =
                      relationships.where((r) => r.name == v).toList();
                  _selectedRelationshipId =
                      match.isNotEmpty ? match.first.id : null;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String hint,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
    bool isOptional = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              if (isOptional)
                Text(
                  ' (Optional)',
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: Colors.black26,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          SizedBox(height: 6.h),
          DropdownButtonFormField<String>(
            value: value,
            validator: validator,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                size: 22.sp, color: Colors.black38),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 13.sp,
                color: Colors.black26,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Container(
                margin: EdgeInsets.only(left: 12.w, right: 8.w),
                child: Icon(icon, size: 20.sp, color: const Color(0xFF064E3B)),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 40.w),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide(
                  color: Colors.black.withOpacity(0.06),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: BorderSide(
                  color: Colors.black.withOpacity(0.06),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: const BorderSide(
                  color: Color(0xFF064E3B),
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14.r),
                borderSide: const BorderSide(
                  color: Color(0xFFE53935),
                ),
              ),
              errorStyle: TextStyle(
                fontSize: 11.sp,
                color: const Color(0xFFE53935),
              ),
            ),
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A2E),
            ),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
            items: items
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    final dateText = _selectedDob != null
        ? DateFormat('dd MMM yyyy').format(_selectedDob!)
        : '';

    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Date of Birth *',
            style: GoogleFonts.playfairDisplay(
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF8D8D8D),
            ),
          ),
          SizedBox(height: 8.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickDate,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15.r),
                border: Border.all(color: Colors.black.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dateText.isNotEmpty ? dateText : 'Select date of birth',
                      style: dateText.isNotEmpty
                          ? GoogleFonts.lora(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF333333),
                            )
                          : GoogleFonts.playfairDisplay(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey,
                            ),
                    ),
                  ),
                  Icon(Icons.calendar_month_rounded,
                      size: 20.sp, color: Colors.black26),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(1900);
    final last = now.subtract(const Duration(days: 1));
    // Clamp initialDate within [firstDate, lastDate] to avoid assertion errors
    DateTime initial = _selectedDob ?? DateTime(now.year - 25);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF064E3B),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1A1A2E),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDob = picked);
    }
  }

  // â”€â”€â”€ Submit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handleSubmit() async {
    // ── Validate all mandatory fields with toast ──
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, 'Full name is required', type: ToastType.error);
      return;
    }
    if (name.length < 2) {
      AppToast.show(context, 'Enter a valid name', type: ToastType.error);
      return;
    }

    if (_selectedRelationship == null || _selectedRelationship!.isEmpty) {
      AppToast.show(context, 'Please select relationship',
          type: ToastType.error);
      return;
    }

    if (_selectedDob == null) {
      AppToast.show(context, 'Please select date of birth',
          type: ToastType.error);
      return;
    }

    final mobile = _mobileCtrl.text.trim();
    final mobileError = Validators.validateMobile(mobile);
    if (mobileError != null) {
      AppToast.show(context, mobileError, type: ToastType.error);
      return;
    }

    // Email is optional — only enforce format when the customer typed one.
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty) {
      final emailError = Validators.validateEmail(email);
      if (emailError != null) {
        AppToast.show(context, emailError, type: ToastType.error);
        return;
      }
    }

    // Pincode is optional, but if the customer started typing one it must be
    // complete — otherwise an untouched/never-"Check"ed partial pincode
    // (e.g. "123") would silently save with the nominee record, since
    // _isPincodeValid only ever flips false when Check is explicitly run.
    final pincode = _pincodeCtrl.text.trim();
    if (pincode.isNotEmpty && pincode.length != 6) {
      AppToast.show(context, 'Enter a valid 6-digit pincode', type: ToastType.error);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final nominee = NomineeDetails(
        id: _nomineeId,
        name: _nameCtrl.text.trim(),
        relationship: _selectedRelationship ?? '',
        relationshipId: _selectedRelationshipId,
        dob: DateFormat('yyyy-MM-dd').format(_selectedDob!),
        mobile: _mobileCtrl.text.trim(),
        email:
            _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
        idType: _selectedIdType,
        idNumber: _idNumberCtrl.text.trim().isNotEmpty
            ? _idNumberCtrl.text.trim()
            : null,
        address: _addressCtrl.text.trim().isNotEmpty
            ? _addressCtrl.text.trim()
            : null,
        city: _cityCtrl.text.trim().isNotEmpty ? _cityCtrl.text.trim() : null,
        state:
            _stateCtrl.text.trim().isNotEmpty ? _stateCtrl.text.trim() : null,
        pincode: _pincodeCtrl.text.trim().isNotEmpty
            ? _pincodeCtrl.text.trim()
            : null,
        idCity: _idCity,
        idState: _idState,
        idCountry: _idCountry ?? 101,
      );

      final service = ref.read(nomineeServiceProvider);
      final response = await service.updateNominee(nominee);

      if (mounted) {
        final success = response['success'] == true;
        if (success) {
          ref.invalidate(nomineeDetailsProvider);
          setState(() => _isEditing = false);
          AppToast.show(
            context,
            response['message'] ?? 'Nominee updated successfully',
            type: ToastType.success,
          );
        } else {
          final errorObj = response['error'];
          final dataObj = response['data'];
          final serverMsg = (errorObj is Map ? errorObj['message'] : null) ??
              (dataObj is Map ? dataObj['message'] : null) ??
              response['message'] ??
              'Failed to update nominee';
          AppToast.show(
            context,
            serverMsg,
            type: ToastType.error,
          );
        }
      }
    } catch (e) {
      SecureLogger.e('NOMINEE: Update failed: $e');
      if (mounted) {
        AppToast.show(
          context,
          'Something went wrong. Please try again.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // â”€â”€â”€ Error State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48.sp, color: Colors.black26),
            SizedBox(height: 16.h),
            Text(
              'Unable to load nominee details',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Please check your connection and try again',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: Colors.black45),
            ),
            SizedBox(height: 24.h),
            CustomButton(
              text: 'Retry',
              svgIconPath: 'assets/buttons/back-home.svg',
              onPressed: () => ref.invalidate(nomineeDetailsProvider),
              gradient: const LinearGradient(
                colors: [Color(0xFF003716), Color(0xFF167525)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDisplayDate(String dob) {
    try {
      final date = _parseDob(dob);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (_) {
      return dob;
    }
  }

  /// Parse DOB string — handles both dd-MM-yyyy (server) and yyyy-MM-dd formats.
  DateTime _parseDob(String dob) {
    // Try dd-MM-yyyy first (server format)
    try {
      return DateFormat('dd-MM-yyyy').parse(dob);
    } catch (_) {}
    // Fallback to yyyy-MM-dd
    return DateFormat('yyyy-MM-dd').parse(dob);
  }

  // â”€â”€â”€ Pincode Check (same pattern as account details) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _handlePincodeCheck() async {
    final pincode = _pincodeCtrl.text.trim();
    if (pincode.length != 6) return;

    setState(() => _isPincodeChecking = true);
    final result =
        await ref.read(pc.profileProvider.notifier).checkPincode(pincode);
    if (!mounted) return;
    setState(() => _isPincodeChecking = false);

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      setState(() {
        _isPincodeValid = true;
        _stateCtrl.text = data['state'] ?? '';
        _cityCtrl.text = data['city'] ?? '';
        _idCity = int.tryParse(data['id_city'] ?? '');
        _idState = int.tryParse(data['id_state'] ?? '');
        _idCountry = int.tryParse(data['id_country'] ?? '') ?? 101;
      });
    } else {
      setState(() {
        _isPincodeValid = false;
        _stateCtrl.text = '';
        _cityCtrl.text = '';
      });
      AppToast.show(context, result['message']?.toString() ?? 'Pincode not found.',
          type: ToastType.error);
    }
  }

  // â”€â”€â”€ Read-only field (auto-filled from pincode check) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.playfairDisplay(
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF8D8D8D),
            ),
          ),
          SizedBox(height: 8.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(15.r),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: Text(
              value.isNotEmpty ? value : '—',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
                color: value.isNotEmpty ? const Color(0xFF333333) : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
