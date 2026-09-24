/// One per-commodity row from GET /withdrawal/eligibility ("holdings").
///
/// total_holding = wallet quantity, unchanged until a payout settles
/// requested     = open, pre-approval withdrawal requests
/// on_hold       = ledger rows held against this commodity (e.g. pending
///                 admin-approved withdrawals, once that module places one)
/// withdrawable  = total_holding - requested - on_hold
class WithdrawalBalance {
  final int? commodityId;
  final String commodity;
  final double totalHolding;
  final double requested;
  final double onHold;
  final double withdrawable;

  const WithdrawalBalance({
    this.commodityId,
    required this.commodity,
    required this.totalHolding,
    required this.requested,
    required this.onHold,
    required this.withdrawable,
  });

  factory WithdrawalBalance.fromJson(Map<String, dynamic> json) {
    double parse(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;
    return WithdrawalBalance(
      commodityId: json['commodity_id'] is int
          ? json['commodity_id'] as int
          : int.tryParse(json['commodity_id']?.toString() ?? ''),
      commodity: json['commodity']?.toString() ?? '',
      totalHolding: parse(json['total_holding']),
      requested: parse(json['requested']),
      onHold: parse(json['on_hold']),
      withdrawable: parse(json['withdrawable']),
    );
  }

  static const empty = WithdrawalBalance(
    commodity: '',
    totalHolding: 0,
    requested: 0,
    onHold: 0,
    withdrawable: 0,
  );
}
