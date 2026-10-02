/// Which installed UPI app owns a UPI ID, judged by its handle (the part
/// after `@`).
///
/// The SIP payment sheet uses this to list that app first. Cashfree's
/// subscription SDK only supports UPI intent, so the customer must approve
/// the mandate inside the app that holds the selected UPI ID. The UPI ID
/// itself cannot be passed to the gateway.
///
/// Each handle maps to keywords that are matched against the lowercased app
/// `id` (the package name on Android, the URL scheme on iOS) and
/// `displayName` from `CFUPIUtils().getUPIApps()`.
const Map<String, List<String>> _handleKeywords = {
  // Google Pay issues its handles through partner banks.
  'oksbi': _googlePay,
  'okaxis': _googlePay,
  'okhdfcbank': _googlePay,
  'okicici': _googlePay,
  'ybl': _phonePe,
  'ibl': _phonePe,
  'axl': _phonePe,
  'paytm': _paytm,
  'pthdfc': _paytm,
  'ptsbi': _paytm,
  'ptaxis': _paytm,
  'ptyes': _paytm,
  'upi': ['bhim', 'npci'],
  'sbi': ['yono', 'sbi'],
  'icici': ['imobile', 'icici'],
  'apl': _amazonPay,
  'yapl': _amazonPay,
  'rapl': _amazonPay,
  'axisb': ['cred', 'dreamplug'],
  'idfcfirst': ['idfc'],
  'waicici': _whatsApp,
  'wahdfcbank': _whatsApp,
  'waaxis': _whatsApp,
  'wasbi': _whatsApp,
};

const _googlePay = ['gpay', 'google', 'paisa', 'tez'];
const _phonePe = ['phonepe'];
const _paytm = ['paytm'];
const _amazonPay = ['amazon'];
const _whatsApp = ['whatsapp'];

/// True if [app], an entry from `CFUPIUtils().getUPIApps()`, is the app
/// that issued [vpa]. Returns false for an empty or unknown handle.
bool upiAppMatchesVpa(Map<dynamic, dynamic> app, String vpa) {
  final at = vpa.lastIndexOf('@');
  if (at < 0) return false;
  final keywords = _handleKeywords[vpa.substring(at + 1).trim().toLowerCase()];
  if (keywords == null) return false;

  final haystack =
      '${app['id'] ?? ''} ${app['displayName'] ?? ''}'.toLowerCase();
  return keywords.any(haystack.contains);
}
