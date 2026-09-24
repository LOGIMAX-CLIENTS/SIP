// lib/features/sip/widgets/bank_details_sheet.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// BankDetailsSheet — Bottom Sheet for eMandate bank account entry
//
// Shown only when the customer picks "eMandate (Netbanking)" on
// PaymentMethodSheet (PaymentMethodSheet.isRecurring relabels the shared
// "netbanking" option for SIP — the underlying id stays "netbanking" until
// auto_savings_screen.dart translates it to 'emandate' for the backend).
// Razorpay's eMandate recurring product requires a bank_account object
// (beneficiary name, account number, IFSC, account type) up front — see
// shared/services/razorpay_recurring.py create_subscription()'s 'emandate'
// branch and Razorpay's eMandate create-authorization-transaction docs.
// UPI and Card mandates need nothing extra here (collected inside Razorpay
// Checkout instead), so this sheet only exists for this one method.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/secure_clipboard.dart';

/// Bank account details collected for an eMandate AutoPay mandate.
class BankDetails {
  final String beneficiaryName;
  final String accountNumber;
  final String ifsc;
  final String accountType; // 'savings' | 'current'

  const BankDetails({
    required this.beneficiaryName,
    required this.accountNumber,
    required this.ifsc,
    required this.accountType,
  });
}

class BankDetailsSheet extends StatefulWidget {
  /// Called with the validated bank details when the user taps "Continue".
  final void Function(BankDetails details) onSubmit;

  const BankDetailsSheet({super.key, required this.onSubmit});

  @override
  State<BankDetailsSheet> createState() => _BankDetailsSheetState();
}

class _BankDetailsSheetState extends State<BankDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _accountController = TextEditingController();
  final _confirmAccountController = TextEditingController();
  final _ifscController = TextEditingController();
  String _accountType = 'savings';

  static final _ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    _confirmAccountController.dispose();
    _ifscController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(BankDetails(
      beneficiaryName: _nameController.text.trim(),
      accountNumber: _accountController.text.trim(),
      ifsc: _ifscController.text.trim().toUpperCase(),
      accountType: _accountType,
    ));
    Navigator.pop(context);
  }

  InputDecoration _decoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: const BorderSide(color: Color(0xFF064E3B), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20.w,
            8.h,
            20.w,
            20.h + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40.w,
                      height: 4.h,
                      margin: EdgeInsets.only(bottom: 16.h),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                  ),
                  Text(
                    'Bank Account Details',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Required to register your eMandate AutoPay mandate.',
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp, color: Colors.black54),
                  ),
                  SizedBox(height: 20.h),
                  TextFormField(
                    controller: _nameController,
                    contextMenuBuilder: SecureClipboard.none,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                      LengthLimitingTextInputFormatter(60),
                    ],
                    decoration: _decoration(
                        'Beneficiary Name', 'As per bank records'),
                    validator: (v) => (v == null || v.trim().length < 4)
                        ? 'Enter the account holder\'s full name'
                        : null,
                  ),
                  SizedBox(height: 14.h),
                  TextFormField(
                    controller: _accountController,
                    contextMenuBuilder: SecureClipboard.none,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(20),
                    ],
                    decoration: _decoration('Account Number', ''),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Enter a valid account number'
                        : null,
                  ),
                  SizedBox(height: 14.h),
                  TextFormField(
                    controller: _confirmAccountController,
                    contextMenuBuilder: SecureClipboard.none,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(20),
                    ],
                    decoration: _decoration('Confirm Account Number', ''),
                    validator: (v) => (v != _accountController.text)
                        ? 'Account numbers do not match'
                        : null,
                  ),
                  SizedBox(height: 14.h),
                  TextFormField(
                    controller: _ifscController,
                    contextMenuBuilder: SecureClipboard.none,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(11),
                    ],
                    decoration: _decoration('IFSC Code', 'e.g. HDFC0001234'),
                    validator: (v) =>
                        (v == null || !_ifscRegex.hasMatch(v.trim().toUpperCase()))
                            ? 'Enter a valid 11-character IFSC code'
                            : null,
                  ),
                  SizedBox(height: 14.h),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('Savings',
                              style: GoogleFonts.playfairDisplay(
                                  fontSize: 13.sp)),
                          value: 'savings',
                          groupValue: _accountType,
                          onChanged: (v) => setState(() => _accountType = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('Current',
                              style: GoogleFonts.playfairDisplay(
                                  fontSize: 13.sp)),
                          value: 'current',
                          groupValue: _accountType,
                          onChanged: (v) => setState(() => _accountType = v!),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  CustomButton(
                    text: 'Continue',
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
