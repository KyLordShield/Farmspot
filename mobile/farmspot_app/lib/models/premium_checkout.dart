class PremiumCheckout {
  final String id, status, url;
  final int amount;
  final bool testMode;
  final String? paymentReference, premiumUntil;
  const PremiumCheckout({
    required this.id,
    required this.status,
    required this.url,
    required this.amount,
    this.testMode = true,
    this.paymentReference,
    this.premiumUntil,
  });
  bool get paid => status == 'PAID';
  bool get expired => status == 'EXPIRED';
  String get price => '₱${(amount / 100).toStringAsFixed(2)}';
  factory PremiumCheckout.fromJson(Map<String, dynamic> json) {
    if (json['test_mode'] is! bool || json['currency'] != 'PHP') {
      throw Exception('Invalid payment details.');
    }
    return PremiumCheckout(
      id: json['id'] as String,
      status: json['status'] as String,
      url: json['checkout_url'] as String? ?? '',
      amount: json['amount'] as int,
      testMode: json['test_mode'] as bool,
      paymentReference: json['payment_reference'] as String?,
      premiumUntil: json['premium_until'] as String?,
    );
  }
}
