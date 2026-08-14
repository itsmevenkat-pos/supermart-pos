import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

class Purchase extends Equatable {
  final String id;
  final String? storeId;
  final String? supplierId;
  final String grnNo;
  final int purchaseDate;
  final String? location;
  final String? supplierName;
  final String? supplierMerchant;
  final String? supplierAddress;
  final double total;
  final double billTotal;
  final double difference;
  final double accountPercent;
  final double account;
  final double taxRate;
  final double taxPercent;
  final double tax;
  final String? chess;
  final double netAmount;
  final String? transportStatus;
  final String? transport;
  final String? labourStatus;
  final double labourCharges;
  final double transportCharge;
  final double totalQty;
  final String? remarks;
  final bool received;
  final String? cForm;
  final String? dueStatus;
  final String? closeStatus;
  final int dueDate;
  final String status;
  final int synced;
  final int createdAt;
  final int? updatedAt;

  const Purchase({
    required this.id,
    this.storeId,
    this.supplierId,
    this.grnNo = '',
    this.purchaseDate = 0,
    this.location,
    this.supplierName,
    this.supplierMerchant,
    this.supplierAddress,
    this.total = 0,
    this.billTotal = 0,
    this.difference = 0,
    this.accountPercent = 0,
    this.account = 0,
    this.taxRate = 0,
    this.taxPercent = 0,
    this.tax = 0,
    this.chess,
    this.netAmount = 0,
    this.transportStatus,
    this.transport,
    this.labourStatus,
    this.labourCharges = 0,
    this.transportCharge = 0,
    this.totalQty = 0,
    this.remarks,
    this.received = false,
    this.cForm,
    this.dueStatus,
    this.closeStatus,
    this.dueDate = 0,
    this.status = 'received',
    this.synced = 0,
    this.createdAt = 0,
    this.updatedAt,
  });

  factory Purchase.create({
    String? storeId,
    String? supplierId,
    String grnNo = '',
    int purchaseDate = 0,
    String? location,
    String? supplierName,
    String? supplierMerchant,
    String? supplierAddress,
    double total = 0,
    double billTotal = 0,
    double difference = 0,
    double accountPercent = 0,
    double account = 0,
    double taxRate = 0,
    double taxPercent = 0,
    double tax = 0,
    String? chess,
    double netAmount = 0,
    String? transportStatus,
    String? transport,
    String? labourStatus,
    double labourCharges = 0,
    double transportCharge = 0,
    double totalQty = 0,
    String? remarks,
    bool received = false,
    String? cForm,
    String? dueStatus,
    String? closeStatus,
    int dueDate = 0,
    String status = 'received',
  }) {
    return Purchase(
      id: const Uuid().v4(),
      storeId: storeId,
      supplierId: supplierId,
      grnNo: grnNo.isNotEmpty ? grnNo : 'GRN-${DateTime.now().millisecondsSinceEpoch}',
      purchaseDate: purchaseDate,
      location: location,
      supplierName: supplierName,
      supplierMerchant: supplierMerchant,
      supplierAddress: supplierAddress,
      total: total,
      billTotal: billTotal,
      difference: difference,
      accountPercent: accountPercent,
      account: account,
      taxRate: taxRate,
      taxPercent: taxPercent,
      tax: tax,
      chess: chess,
      netAmount: netAmount,
      transportStatus: transportStatus,
      transport: transport,
      labourStatus: labourStatus,
      labourCharges: labourCharges,
      transportCharge: transportCharge,
      totalQty: totalQty,
      remarks: remarks,
      received: received,
      cForm: cForm,
      dueStatus: dueStatus,
      closeStatus: closeStatus,
      dueDate: dueDate,
      status: status,
      // Was left at the default of 0 before — purchase reports filter on
      // this (created_at >= ? AND <= ?), so every new purchase was
      // invisible to date-range reports until now.
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Purchase copyWith({
    String? grnNo,
    int? purchaseDate,
    String? location,
    String? supplierName,
    String? supplierMerchant,
    String? supplierAddress,
    double? total,
    double? billTotal,
    double? difference,
    double? accountPercent,
    double? account,
    double? taxRate,
    double? taxPercent,
    double? tax,
    String? chess,
    double? netAmount,
    String? transportStatus,
    String? transport,
    String? labourStatus,
    double? labourCharges,
    double? transportCharge,
    double? totalQty,
    String? remarks,
    bool? received,
    String? cForm,
    String? dueStatus,
    String? closeStatus,
    int? dueDate,
    String? status,
  }) {
    return Purchase(
      id: id,
      storeId: storeId,
      supplierId: supplierId,
      grnNo: grnNo ?? this.grnNo,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      location: location ?? this.location,
      supplierName: supplierName ?? this.supplierName,
      supplierMerchant: supplierMerchant ?? this.supplierMerchant,
      supplierAddress: supplierAddress ?? this.supplierAddress,
      total: total ?? this.total,
      billTotal: billTotal ?? this.billTotal,
      difference: difference ?? this.difference,
      accountPercent: accountPercent ?? this.accountPercent,
      account: account ?? this.account,
      taxRate: taxRate ?? this.taxRate,
      taxPercent: taxPercent ?? this.taxPercent,
      tax: tax ?? this.tax,
      chess: chess ?? this.chess,
      netAmount: netAmount ?? this.netAmount,
      transportStatus: transportStatus ?? this.transportStatus,
      transport: transport ?? this.transport,
      labourStatus: labourStatus ?? this.labourStatus,
      labourCharges: labourCharges ?? this.labourCharges,
      transportCharge: transportCharge ?? this.transportCharge,
      totalQty: totalQty ?? this.totalQty,
      remarks: remarks ?? this.remarks,
      received: received ?? this.received,
      cForm: cForm ?? this.cForm,
      dueStatus: dueStatus ?? this.dueStatus,
      closeStatus: closeStatus ?? this.closeStatus,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'supplier_id': supplierId,
        'grn_no': grnNo,
        'purchase_date': purchaseDate,
        'location': location,
        'supplier_name': supplierName,
        'supplier_merchant': supplierMerchant,
        'supplier_address': supplierAddress,
        'total': total,
        'bill_total': billTotal,
        'difference': difference,
        'account_percent': accountPercent,
        'account': account,
        'tax_rate': taxRate,
        'tax_percent': taxPercent,
        'tax': tax,
        'chess': chess,
        'net_amount': netAmount,
        'transport_status': transportStatus,
        'transport': transport,
        'labour_status': labourStatus,
        'labour_charges': labourCharges,
        'transport_charge': transportCharge,
        'total_qty': totalQty,
        'remarks': remarks,
        'received': received ? 1 : 0,
        'c_form': cForm,
        'due_status': dueStatus,
        'close_status': closeStatus,
        'due_date': dueDate,
        'status': status,
        'synced': synced,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Purchase.fromJson(Map<String, dynamic> map) => Purchase(
        id: map['id'] as String,
        storeId: map['store_id'] as String?,
        supplierId: map['supplier_id'] as String?,
        grnNo: map['grn_no'] as String? ?? '',
        purchaseDate: map['purchase_date'] as int? ?? 0,
        location: map['location'] as String?,
        supplierName: map['supplier_name'] as String?,
        supplierMerchant: map['supplier_merchant'] as String?,
        supplierAddress: map['supplier_address'] as String?,
        total: (map['total'] as num?)?.toDouble() ?? 0,
        billTotal: (map['bill_total'] as num?)?.toDouble() ?? 0,
        difference: (map['difference'] as num?)?.toDouble() ?? 0,
        accountPercent: (map['account_percent'] as num?)?.toDouble() ?? 0,
        account: (map['account'] as num?)?.toDouble() ?? 0,
        taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0,
        taxPercent: (map['tax_percent'] as num?)?.toDouble() ?? 0,
        tax: (map['tax'] as num?)?.toDouble() ?? 0,
        chess: map['chess'] as String?,
        netAmount: (map['net_amount'] as num?)?.toDouble() ?? 0,
        transportStatus: map['transport_status'] as String?,
        transport: map['transport'] as String?,
        labourStatus: map['labour_status'] as String?,
        labourCharges: (map['labour_charges'] as num?)?.toDouble() ?? 0,
        transportCharge: (map['transport_charge'] as num?)?.toDouble() ?? 0,
        totalQty: (map['total_qty'] as num?)?.toDouble() ?? 0,
        remarks: map['remarks'] as String?,
        received: (map['received'] as int?) == 1,
        cForm: map['c_form'] as String?,
        dueStatus: map['due_status'] as String?,
        closeStatus: map['close_status'] as String?,
        dueDate: map['due_date'] as int? ?? 0,
        status: map['status'] as String? ?? 'received',
        synced: map['synced'] as int? ?? 0,
        createdAt: map['created_at'] as int? ?? 0,
        updatedAt: map['updated_at'] as int?,
      );

  @override
  List<Object?> get props => [id, grnNo, supplierId, netAmount, status];
}