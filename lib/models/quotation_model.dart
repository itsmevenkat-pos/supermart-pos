import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Quotation extends Equatable {
  final String id;
  final String? storeId;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String quoteNo;
  final double subtotal;
  final double taxTotal;
  final double discountTotal;
  final String? discountReason;
  final double netAmount;
  final String? notes;
  final int expiryDate; // Unix timestamp
  final String status; // pending, converted, expired
  final int createdAt;
  final int? updatedAt;

  const Quotation({
    required this.id,
    this.storeId,
    this.customerId,
    required this.customerName,
    this.customerPhone,
    this.customerEmail,
    required this.quoteNo,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.discountTotal = 0,
    this.discountReason,
    this.netAmount = 0,
    this.notes,
    this.expiryDate = 0,
    this.status = 'pending',
    this.createdAt = 0,
    this.updatedAt,
  });

  factory Quotation.create({
    String? storeId,
    String? customerId,
    required String customerName,
    String? customerPhone,
    String? customerEmail,
    double subtotal = 0,
    double taxTotal = 0,
    double discountTotal = 0,
    String? discountReason,
    double netAmount = 0,
    String? notes,
    int expiryDate = 0,
  }) {
    return Quotation(
      id: const Uuid().v4(),
      storeId: storeId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      quoteNo: 'QUOT-${DateTime.now().millisecondsSinceEpoch}',
      subtotal: subtotal,
      taxTotal: taxTotal,
      discountTotal: discountTotal,
      discountReason: discountReason,
      netAmount: netAmount,
      notes: notes,
      expiryDate: expiryDate,
    );
  }

  Quotation copyWith({
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    double? subtotal,
    double? taxTotal,
    double? discountTotal,
    String? discountReason,
    double? netAmount,
    String? notes,
    int? expiryDate,
    String? status,
  }) {
    return Quotation(
      id: id,
      storeId: storeId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      quoteNo: quoteNo,
      subtotal: subtotal ?? this.subtotal,
      taxTotal: taxTotal ?? this.taxTotal,
      discountTotal: discountTotal ?? this.discountTotal,
      discountReason: discountReason ?? this.discountReason,
      netAmount: netAmount ?? this.netAmount,
      notes: notes ?? this.notes,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_email': customerEmail,
        'quote_no': quoteNo,
        'subtotal': subtotal,
        'tax_total': taxTotal,
        'discount_total': discountTotal,
        'discount_reason': discountReason,
        'net_amount': netAmount,
        'notes': notes,
        'expiry_date': expiryDate,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Quotation.fromJson(Map<String, dynamic> map) => Quotation(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        customerId: map['customer_id'] as String?,
        customerName: map['customer_name'] as String,
        customerPhone: map['customer_phone'] as String?,
        customerEmail: map['customer_email'] as String?,
        quoteNo: map['quote_no'] as String,
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
        taxTotal: (map['tax_total'] as num?)?.toDouble() ?? 0,
        discountTotal: (map['discount_total'] as num?)?.toDouble() ?? 0,
        discountReason: map['discount_reason'] as String?,
        netAmount: (map['net_amount'] as num?)?.toDouble() ?? 0,
        notes: map['notes'] as String?,
        expiryDate: map['expiry_date'] as int? ?? 0,
        status: map['status'] as String? ?? 'pending',
        createdAt: map['created_at'] as int? ?? 0,
        updatedAt: map['updated_at'] as int?,
      );

  @override
  List<Object?> get props => [id, quoteNo, customerName, netAmount, status];
}
