/// 计费状态
class BillingStatus {
  final String planId;
  final int secondsUsed;
  final int secondsLimit;
  final String periodStart;
  final String periodEnd;

  BillingStatus({
    required this.planId,
    required this.secondsUsed,
    required this.secondsLimit,
    required this.periodStart,
    required this.periodEnd,
  });

  factory BillingStatus.fromJson(Map<String, dynamic> json) {
    return BillingStatus(
      planId: json['planId'] as String? ?? 'free',
      secondsUsed: json['secondsUsed'] as int? ?? 0,
      secondsLimit: json['secondsLimit'] as int? ?? 1800,
      periodStart: json['periodStart'] as String? ?? '',
      periodEnd: json['periodEnd'] as String? ?? '',
    );
  }

  int get secondsRemaining => (secondsLimit - secondsUsed).clamp(0, secondsLimit);
  double get usagePercent => secondsLimit > 0 ? (secondsUsed / secondsLimit).clamp(0.0, 1.0) : 0.0;
  bool get isQuotaExceeded => secondsUsed >= secondsLimit;
  bool get isFree => planId == 'free';

  String get formattedRemaining {
    final r = secondsRemaining;
    if (r >= 3600) return '${r ~/ 3600}h ${(r % 3600) ~/ 60}m';
    if (r >= 60) return '${r ~/ 60}m';
    return '${r}s';
  }

  String get formattedLimit {
    if (secondsLimit >= 3600) return '${secondsLimit ~/ 3600}h';
    return '${secondsLimit ~/ 60}m';
  }
}

/// 套餐
class BillingPlan {
  final String id;
  final String name;
  final String nameEn;
  final int seconds;
  final int priceCny;
  final int priceUsd;

  BillingPlan({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.seconds,
    required this.priceCny,
    required this.priceUsd,
  });

  factory BillingPlan.fromJson(Map<String, dynamic> json) {
    return BillingPlan(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      nameEn: json['nameEn'] as String? ?? json['id'] as String,
      seconds: json['seconds'] as int,
      priceCny: json['priceCny'] as int? ?? 0,
      priceUsd: json['priceUsd'] as int? ?? 0,
    );
  }

  bool get isFree => priceCny == 0 && priceUsd == 0;

  String get formattedPriceCny => isFree ? '免费' : '¥${(priceCny / 100).toStringAsFixed(priceCny % 100 == 0 ? 0 : 1)}/月';
  String get formattedPriceUsd => isFree ? 'Free' : '\$${(priceUsd / 100).toStringAsFixed(priceUsd % 100 == 0 ? 0 : 2)}/mo';
  String get formattedDuration {
    if (seconds >= 3600) return '${seconds ~/ 3600}h/月';
    return '${seconds ~/ 60}min/月';
  }
}

/// 订单
class BillingOrder {
  final String orderId;
  final String status;
  final String? qrCode;
  final String? checkoutUrl;

  BillingOrder({
    required this.orderId,
    required this.status,
    this.qrCode,
    this.checkoutUrl,
  });

  factory BillingOrder.fromJson(Map<String, dynamic> json) {
    return BillingOrder(
      orderId: json['orderId'] as String,
      status: json['status'] as String? ?? 'pending',
      qrCode: json['qrCode'] as String?,
      checkoutUrl: json['checkoutUrl'] as String?,
    );
  }

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
}
