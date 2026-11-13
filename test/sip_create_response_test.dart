import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/core/error/failures.dart';
import 'package:startgold/features/sip/models/sip_models.dart';

/// SipCreateResponse must pick up Airpay's "approve in your UPI app" answer
/// without changing how Cashfree / Razorpay answers parse.
void main() {
  test('Airpay create answer: upi_collect with the UPI ID to approve from', () {
    final r = SipCreateResponse.fromJson({
      'success': true,
      'message': 'AutoGold created',
      'data': {
        'subscription_id': 'SUB_ab12cd34',
        'status': 'ACTIVE',
        'order_id': '778899',
        'session_id': '',
        'authorization_link': '',
        'environment': 'PRODUCTION',
        'payment_gateway': 'airpay',
        'mode': 'upi_collect',
        'key_id': '',
        'customer_id': '',
        'payment_method': 'upi',
        'enach_auth_link': '',
        'enach_details': null,
        'approve_vpa': 'priya@okaxis',
      },
    });

    expect(r.success, isTrue);
    expect(r.paymentGateway, 'airpay');
    expect(r.mode, 'upi_collect');
    expect(r.approveVpa, 'priya@okaxis');
    expect(r.subscriptionId, 'SUB_ab12cd34');
    expect(r.sessionId, '');
    expect(r.isUpiCollect, isTrue);
  });

  test('upi_collect mode alone also means "approve in the UPI app"', () {
    final r = SipCreateResponse.fromJson({
      'success': true,
      'data': {'payment_gateway': 'AIRPAY_SIP', 'mode': 'UPI_COLLECT'},
    });
    expect(r.mode, 'upi_collect');
    expect(r.isUpiCollect, isTrue);
  });

  test('Cashfree answer is unchanged: no approve_vpa, not upi_collect', () {
    final r = SipCreateResponse.fromJson({
      'success': true,
      'data': {
        'subscription_id': 'SUB_ab12cd34',
        'order_id': '2727035',
        'session_id': 'sub_session_xyz',
        'payment_gateway': 'cashfree',
        'mode': 'subscriptions',
        'payment_method': 'upi',
        'approve_vpa': '',
      },
    });
    expect(r.paymentGateway, 'cashfree');
    expect(r.mode, 'subscriptions');
    expect(r.sessionId, 'sub_session_xyz');
    expect(r.approveVpa, isNull, reason: "'' from the server means none");
    expect(r.isUpiCollect, isFalse);
  });

  test('Razorpay recurring answer is unchanged', () {
    final r = SipCreateResponse.fromJson({
      'success': true,
      'data': {
        'order_id': 'order_Nabc',
        'session_id': '',
        'payment_gateway': 'razorpay',
        'mode': 'recurring',
        'key_id': 'rzp_live_x',
        'customer_id': 'cust_1',
      },
    });
    expect(r.paymentGateway, 'razorpay');
    expect(r.mode, 'recurring');
    expect(r.keyId, 'rzp_live_x');
    expect(r.customerId, 'cust_1');
    expect(r.approveVpa, isNull);
    expect(r.isUpiCollect, isFalse);
  });

  test('older backend without the new fields keeps the old defaults', () {
    final r = SipCreateResponse.fromJson({
      'success': true,
      'data': {'order_id': '1', 'session_id': 's'},
    });
    expect(r.paymentGateway, 'cashfree');
    expect(r.mode, 'subscriptions');
    expect(r.approveVpa, isNull);
    expect(r.isUpiCollect, isFalse);
  });

  test('UPI-only refusal keeps the server message for the error toast', () {
    final r = SipCreateResponse.fromJson({
      'success': false,
      'error': {
        'code': 'SIP_CREATE_FAILED',
        'message': 'AutoGold with this payment gateway supports UPI only right '
            'now. Please choose UPI.',
      },
      'data': <String, dynamic>{},
    });
    expect(r.success, isFalse);
    expect(r.errorCode, 'SIP_CREATE_FAILED');
    expect(r.message, contains('supports UPI only'));
  });

  // sip/create and sip/custom/create refuse with HTTP 400, which ApiClient
  // throws; _createSipPlan / _createCustomSipPlan's catch-all toasts
  // e.toString(). That must be the server's sentence, word for word.
  for (final serverMessage in [
    'AutoGold with this payment gateway supports UPI only right now. '
        'Please choose UPI.',
    'Add a UPI ID to your account first — the AutoPay request is sent to it.',
  ]) {
    test('create refused with HTTP 400 toasts: $serverMessage', () {
      final options = RequestOptions(path: 'sip/create');
      final failure = ApiFailureMapper.map(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: 400,
          data: <String, dynamic>{
            'success': false,
            'error': <String, dynamic>{
              'code': 'SIP_CREATE_FAILED',
              'message': serverMessage,
              'internal_message': serverMessage,
            },
            'data': <String, dynamic>{},
            'validation_errors': <String, dynamic>{},
          },
        ),
      ));
      expect(failure.toString().replaceAll('Exception: ', ''), serverMessage);
    });
  }
}
