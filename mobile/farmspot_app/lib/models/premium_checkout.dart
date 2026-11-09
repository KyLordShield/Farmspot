class PremiumCheckout {
  final String id, status, url;
  final int amount;
  final String? paymentReference, premiumUntil;
  const PremiumCheckout({
    required this.id,
    required this.status,
    required this.url,
    required this.amount,
    this.paymentReference,
    this.premiumUntil,
  });
  bool get paid => status == 'PAID';
  bool get expired => status == 'EXPIRED';
  String get price => '₱${(amount / 100).toStringAsFixed(2)}';
  factory PremiumCheckout.fromJson(Map<String, dynamic> json) {
    if (json['test_mode'] != true || json['currency'] != 'PHP') {
      throw Exception('Only test payments are supported.');
    }
    return PremiumCheckout(
      id: json['id'] as String,
      status: json['status'] as String,
      url: json['checkout_url'] as String? ?? '',
      amount: json['amount'] as int,
      paymentReference: json['payment_reference'] as String?,
      premiumUntil: json['premium_until'] as String?,
    );
  }
}
