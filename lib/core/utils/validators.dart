class Validators {
  static String? validateMobile(String? value) {
    if (value == null || value.isEmpty) return 'Mobile number is required';
    // Real Indian mobile numbers always start 6-9 — a leading 0-5 is never
    // valid, even though it's still 10 digits.
    final regExp = RegExp(r'^[6-9]\d{9}$');
    if (!regExp.hasMatch(value)) return 'Enter a valid 10-digit mobile number';
    return null;
  }

  static String? validateOTP(String? value) {
    if (value == null || value.isEmpty) return 'OTP is required';
    if (value.length != 6) return 'Enter a 6-digit OTP';
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'E-Mail is required';
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid e-mail address';
    return null;
  }
}

