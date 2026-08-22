import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Sale extends Equatable {
  final String id;
  final String? storeId;
  final String? customerId;
  final String? sessionId;
  final String? userId;
  final String? salesmanId;
  final int invoiceNo;
  /// Formatted statutory invoice number, e.g. "SM/25-26/00001" — null for
  /// bills issued before this was introduced. [invoiceNo] remains the
  /// gapless integer sequence this is derived from; this is a display label,
  /// not a replacement primary sequence.
  final String? invoiceDisplayNo;
  final double subtotal;
  final double taxTotal;
  final double discountTotal;
  final String? discountReason;
  final double roundOff;
  final double netAmount;
  final Map<String, double>? paymentMethods;
  final double? partialPaymentAmount;
  final double? creditUsed;
  final String? deliveryAddress;
  final bool isDelivery;
  final double deliveryCharge;
  final bool isCreditSale;
  final String status;
  final String? remarks;
  /// Points redeemed toward this bill, and the ₹ value they were worth —
  /// separate from [discountTotal] so reporting can distinguish a cashier
  /// discount from a customer redeeming their own loyalty points.
  final int loyaltyPointsRedeemed;
  final double loyaltyRedemptionAmount;
  final int synced;
  final int createdAt;

  const Sale({
    required this.id,
    this.storeId,
    this.customerId,
    this.sessionId,
    this.userId,
    this.salesmanId,
    required this.invoiceNo,
    this.invoiceDisplayNo,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.discountTotal = 0,
    this.discountReason,
    this.roundOff = 0,
    this.netAmount = 0,
    this.paymentMethods,
    this.partialPaymentAmount,
    this.creditUsed,
    this.deliveryAddress,
    this.isDelivery = false,
    this.deliveryCharge = 0,
    this.isCreditSale = false,
    this.status = 'completed',
    this.remarks,
    this.loyaltyPointsRedeemed = 0,
    this.loyaltyRedemptionAmount = 0,
    this.synced = 0,
    this.createdAt = 0,
  });

  factory Sale.create({
    String? storeId,
    String? customerId,
    String? sessionId,
    String? userId,
    String? salesmanId,
    int? invoiceNo,
    double subtotal = 0,
    double taxTotal = 0,
    double discountTotal = 0,
    String? discountReason,
    double roundOff = 0,
    double netAmount = 0,
    Map<String, double>? paymentMethods,
    double? partialPaymentAmount,
    double? creditUsed,
    String? deliveryAddress,
    bool isDelivery = false,
    double deliveryCharge = 0,
    bool isCreditSale = false,
    String? remarks,
    int loyaltyPointsRedeemed = 0,
    double loyaltyRedemptionAmount = 0,
  }) {
    return Sale(
      id: const Uuid().v4(),
      storeId: storeId,
      customerId: customerId,
      sessionId: sessionId,
      userId: userId,
      salesmanId: salesmanId,
      // Falls back to a timestamp-based number only if the caller doesn't
      // supply a real sequential one — BillingService always does now.
      invoiceNo: invoiceNo ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      subtotal: subtotal,
      taxTotal: taxTotal,
      discountTotal: discountTotal,
      discountReason: discountReason,
      roundOff: roundOff,
      netAmount: netAmount,
      paymentMethods: paymentMethods,
      partialPaymentAmount: partialPaymentAmount,
      creditUsed: creditUsed,
      deliveryAddress: deliveryAddress,
      isDelivery: isDelivery,
      deliveryCharge: deliveryCharge,
      isCreditSale: isCreditSale,
      remarks: remarks,
      loyaltyPointsRedeemed: loyaltyPointsRedeemed,
      loyaltyRedemptionAmount: loyaltyRedemptionAmount,
      // Was left at the default of 0 before — every sale printed/sorted as
      // Jan 1 1970, which is why reports could look empty even with real
      // billing happening.
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Sale copyWith({
    String? status,
    int? synced,
    int? invoiceNo,
    String? invoiceDisplayNo,
    Map<String, double>? paymentMethods,
  }) {
    return Sale(
      id: id,
      storeId: storeId,
      customerId: customerId,
      sessionId: sessionId,
      userId: userId,
      salesmanId: salesmanId,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      invoiceDisplayNo: invoiceDisplayNo ?? this.invoiceDisplayNo,
      subtotal: subtotal,
      taxTotal: taxTotal,
      discountTotal: discountTotal,
      discountReason: discountReason,
      roundOff: roundOff,
      netAmount: netAmount,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      partialPaymentAmount: partialPaymentAmount,
      creditUsed: creditUsed,
      deliveryAddress: deliveryAddress,
      isDelivery: isDelivery,
      deliveryCharge: deliveryCharge,
      isCreditSale: isCreditSale,
      remarks: remarks,
      status: status ?? this.status,
      synced: synced ?? this.synced,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'customer_id': customerId,
        'session_id': sessionId,
        'user_id': userId,
        'salesman_id': salesmanId,
        'invoice_no': invoiceNo,
        'invoice_display_no': invoiceDisplayNo,
        'subtotal': subtotal,
        'tax_total': taxTotal,
        'discount_total': discountTotal,
        'discount_reason': discountReason,
        'round_off': roundOff,
        'net_amount': netAmount,
        'payment_methods': paymentMethods != null ? jsonEncode(paymentMethods) : null,
        'partial_payment_amount': partialPaymentAmount,
        'credit_used': creditUsed,
        'delivery_address': deliveryAddress,
        'is_delivery': isDelivery ? 1 : 0,
        'delivery_charge': deliveryCharge,
        'is_credit_sale': isCreditSale ? 1 : 0,
        'status': status,
        'remarks': remarks,
        'loyalty_points_redeemed': loyaltyPointsRedeemed,
        'loyalty_redemption_amount': loyaltyRedemptionAmount,
        'synced': synced,
        'created_at': createdAt,
      };

  factory Sale.fromJson(Map<String, dynamic> map) => Sale(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        customerId: map['customer_id'] as String?,
        sessionId: map['session_id'] as String?,
        userId: map['user_id'] as String?,
        salesmanId: map['salesman_id'] as String?,
        invoiceNo: map['invoice_no'] as int,
        invoiceDisplayNo: map['invoice_display_no'] as String?,
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
        taxTotal: (map['tax_total'] as num?)?.toDouble() ?? 0,
        discountTotal: (map['discount_total'] as num?)?.toDouble() ?? 0,
        discountReason: map['discount_reason'] as String?,
        roundOff: (map['round_off'] as num?)?.toDouble() ?? 0,
        netAmount: (map['net_amount'] as num?)?.toDouble() ?? 0,
        paymentMethods: map['payment_methods'] != null
            ? Map<String, double>.from(jsonDecode(map['payment_methods']))
            : null,
        partialPaymentAmount: (map['partial_payment_amount'] as num?)?.toDouble(),
        creditUsed: (map['credit_used'] as num?)?.toDouble(),
        deliveryAddress: map['delivery_address'] as String?,
        isDelivery: (map['is_delivery'] as int?) == 1,
        deliveryCharge: (map['delivery_charge'] as num?)?.toDouble() ?? 0,
        isCreditSale: (map['is_credit_sale'] as int?) == 1,
        status: map['status'] as String? ?? 'completed',
        remarks: map['remarks'] as String?,
        loyaltyPointsRedeemed: map['loyalty_points_redeemed'] as int? ?? 0,
        loyaltyRedemptionAmount: (map['loyalty_redemption_amount'] as num?)?.toDouble() ?? 0,
        synced: map['synced'] as int? ?? 0,
        createdAt: map['created_at'] as int? ?? 0,
      );

  /// What to print/display for this bill's number — the formatted
  /// prefix/FY/sequence label where available, falling back to the plain
  /// integer for bills issued before invoiceDisplayNo existed.
  String get invoiceLabel => invoiceDisplayNo ?? '#$invoiceNo';

  @override
  List<Object?> get props => [id, invoiceNo, netAmount, status];
}