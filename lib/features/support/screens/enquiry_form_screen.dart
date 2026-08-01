import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/support/enquiry_service.dart';
import 'package:startgold/shared/widgets/app_toast.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';
import 'package:startgold/shared/widgets/secure_clipboard.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';

class EnquiryFormScreen extends ConsumerStatefulWidget {
  /// Optional: pre-select a ticket type when navigating from a specific screen.
  /// E.g. 'Auto Savings' when coming from ManageSavingsScreen.
  final String? initialType;

  const EnquiryFormScreen({super.key, this.initialType});

  @override
  ConsumerState<EnquiryFormScreen> createState() => _EnquiryFormScreenState();
}

class _EnquiryFormScreenState extends ConsumerState<EnquiryFormScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _contentController = TextEditingController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Selected type label — maps to int via kTicketTypes
  String _selectedType = 'General';
  bool _isLoading = false;

  // Icon for each type chip
  static const Map<String, IconData> _typeIcons = {
    'General':      Icons.chat_bubble_outline_rounded,
    'Payment':      Icons.payments_outlined,
    'Technical':    Icons.build_outlined,
    'Account':      Icons.manage_accounts_outlined,
    'Enquiry':      Icons.help_outline_rounded,
    'Support':      Icons.support_agent_outlined,
    'Review':       Icons.rate_review_outlined,
    'Others':       Icons.more_horiz_rounded,
    'Auto Savings': Icons.savings_outlined,
  };

  @override
  void initState() {
    super.initState();
    // Pre-select type if passed from the calling screen
    if (widget.initialType != null &&
        kTicketTypes.containsKey(widget.initialType)) {
      _selectedType = widget.initialType!;
    }
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _contentController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final typeInt = kTicketTypes[_selectedType] ?? 1;
      final response = await ref.read(enquiryServiceProvider).submitEnquiry(
            type: typeInt,
            subject: _subjectController.text.trim(),
            content: _contentController.text.trim(),
          );

      if (response['success'] == true && mounted) {
        ref.invalidate(enquiriesProvider);
        _showSuccessSheet(
          response['message'] ?? 'Support ticket submitted successfully.',
          response['data'] as Map<String, dynamic>? ?? {},
        );
      } else if (mounted) {
        AppToast.show(
          context,
          response['message'] ?? 'Submission failed. Please try again.',
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Something went wrong. Please try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessSheet(String message, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuccessSheet(message: message, data: data),
    ).then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            GradientHeader(title: 'New Enquiry'),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
                  children: [
              // ── Hero header card ───────────────────────────────────────
              _buildHeroCard(),
              SizedBox(height: 24.h),

              // ── Type picker ────────────────────────────────────────────
              _buildSectionLabel('Type of Enquiry'),
              SizedBox(height: 12.h),
              _buildTypePicker(),
              SizedBox(height: 24.h),

              // ── Subject ────────────────────────────────────────────────
              _buildSectionLabel('Subject'),
              SizedBox(height: 10.h),
              _buildTextField(
                controller: _subjectController,
                hint: 'Briefly Describe Your Issue…',
                icon: Icons.edit_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Subject is required' : null,
              ),
              SizedBox(height: 24.h),

              // ── Content / Message ──────────────────────────────────────
              _buildSectionLabel('Message'),
              SizedBox(height: 10.h),
              _buildTextField(
                controller: _contentController,
                hint: 'Describe Your Issue In Detail…',
                icon: Icons.notes_rounded,
                maxLines: 6,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Message is required' : null,
              ),
              SizedBox(height: 36.h),

              // ── Submit button ──────────────────────────────────────────
              _buildSubmitButton(),
              SizedBox(height: 12.h),

              // ── Footer note ────────────────────────────────────────────
              Center(
                child: Text(
                  'Our support team typically responds within 24 hours.',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 11.sp,
                    color: const Color(0xFF888888),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero Card ─────────────────────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B882C), Color(0xFF003716)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B882C).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56.w,
            height: 56.w,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Icon(Icons.support_agent_rounded,
                color: Colors.white, size: 30.sp),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How can we help?',
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Submit a ticket and our team will\nget back to you shortly.',
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white70,
                    fontSize: 12.sp,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.playfairDisplay(
        fontSize: 13.sp,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF444444),
        letterSpacing: 0.4,
      ),
    );
  }

  // ── Type chip picker ──────────────────────────────────────────────────────
  Widget _buildTypePicker() {
    return Wrap(
      spacing: 10.w,
      runSpacing: 10.h,
      children: kTicketTypes.keys.map((label) {
        final selected = _selectedType == label;
        return GestureDetector(
          onTap: () => setState(() => _selectedType = label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF1B882C)
                  : Colors.white,
              borderRadius: BorderRadius.circular(50.r),
              border: Border.all(
                color: selected
                    ? const Color(0xFF1B882C)
                    : const Color(0xFFE0E0E0),
                width: 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF1B882C).withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _typeIcons[label] ?? Icons.label_outline,
                  size: 15.sp,
                  color: selected ? Colors.white : const Color(0xFF666666),
                ),
                SizedBox(width: 6.w),
                Text(
                  label,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xFF444444),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Text field ─────────────────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      contextMenuBuilder: SecureClipboard.none,
      enableSuggestions: false,
      autocorrect: false,
      style: GoogleFonts.playfairDisplay(
        fontSize: 15.sp,
        color: const Color(0xFF1A2332),
        height: 1.5,
      ),
      decoration: InputDecoration(
        prefixIcon: maxLines == 1
            ? Icon(icon, size: 18.sp, color: const Color(0xFF1B882C))
            : null,
        hintText: hint,
        hintStyle: GoogleFonts.playfairDisplay(
          color: const Color(0xFFBBBBBB),
          fontSize: 16.sp,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 18.w,
          vertical: maxLines > 1 ? 16.h : 0,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: Color(0xFF1B882C), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
        ),
      ),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────
  Widget _buildSubmitButton() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: _isLoading
            ? const LinearGradient(
                colors: [Color(0xFF9CA3AF), Color(0xFF6B7280)])
            : const LinearGradient(
                colors: [Color(0xFF1B882C), Color(0xFF003716)],
              ),
        borderRadius: BorderRadius.circular(50.r),
        boxShadow: _isLoading
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF1B882C).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: Size(double.infinity, 56.h),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50.r)),
        ),
        child: _isLoading
            ? SizedBox(
                width: 22.w,
                height: 22.w,
                child: const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
                  SizedBox(width: 10.w),
                  Text(
                    'Submit Enquiry',
                    style: AppTextStyles.button(false),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Success Bottom Sheet ───────────────────────────────────────────────────
class _SuccessSheet extends StatelessWidget {
  final String message;
  final Map<String, dynamic> data;

  const _SuccessSheet({required this.message, required this.data});

  @override
  Widget build(BuildContext context) {
    final ticketId   = data['id']?.toString() ?? '';
    final subject    = data['subject'] ?? '';
    final status     = data['status'] ?? 'pending';
    final submittedOn = data['on'] ?? '';

    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 32.h),
      padding: EdgeInsets.all(28.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ─────────────────────────────────────────────────
          Container(
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(height: 24.h),

          // ── Success icon ────────────────────────────────────────────
          Container(
            width: 72.w,
            height: 72.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1B882C), Color(0xFF003716)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B882C).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(Icons.check_rounded, color: Colors.white, size: 36.sp),
          ),
          SizedBox(height: 16.h),

          Text(
            'Ticket Submitted!',
            style: GoogleFonts.playfairDisplay(
              fontSize: 22.sp,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A2332),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            message,
            style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp,
              color: const Color(0xFF666666),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24.h),

          // ── Ticket info card ────────────────────────────────────────
          Container(
            padding: EdgeInsets.all(18.w),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FFF9),
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(color: const Color(0xFF1B882C).withOpacity(0.15)),
            ),
            child: Column(
              children: [
                if (ticketId.isNotEmpty)
                  _info('Ticket ID', '#$ticketId', numeric: true),
                if (subject.isNotEmpty)
                  _info('Subject', subject),
                if (submittedOn.isNotEmpty)
                  _info('Submitted', submittedOn, numeric: true),
                _infoStatus(status),
              ],
            ),
          ),
          SizedBox(height: 28.h),

          // ── Done button ─────────────────────────────────────────────
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1B882C), Color(0xFF003716)]),
              borderRadius: BorderRadius.circular(50.r),
            ),
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                minimumSize: Size(double.infinity, 52.h),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50.r)),
              ),
              child: Text(
                'Done',
                style: AppTextStyles.button(false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value, {bool numeric = false}) {
    final valueStyle = numeric
        ? GoogleFonts.lora(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A2332),
          )
        : GoogleFonts.playfairDisplay(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A2332),
          );
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        children: [
          Text(
            '$label:',
            style: GoogleFonts.playfairDisplay(
              fontSize: 12.sp,
              color: const Color(0xFF888888),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              value,
              style: valueStyle,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoStatus(String status) {
    final color = status == 'pending'
        ? const Color(0xFFD97706)
        : const Color(0xFF1B882C);
    return Row(
      children: [
        Text(
          'Status:',
          style: GoogleFonts.playfairDisplay(
            fontSize: 12.sp,
            color: const Color(0xFF888888),
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Text(
            status.toUpperCase(),
            style: GoogleFonts.playfairDisplay(
              fontSize: 11.sp,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
