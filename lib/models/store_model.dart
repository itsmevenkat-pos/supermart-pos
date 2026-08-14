import 'package:equatable/equatable.dart';

class Store extends Equatable {
  final String id;
  final String name;
  final String timezone;
  final String invoicePrefix;
  final String? phone;
  final String? gstin;
  final String? email;
  final String? businessType;
  final String? businessCategory;
  final String? address;
  final String? state;
  final String? pincode;
  final String? logoPath;
  final String? signaturePath;
  /// Rupee amount at/under which a return posts without manager/admin
  /// approval. Untied returns (no originating sale) always require
  /// approval regardless of this value — enforced in code, not here.
  final double returnThresholdNoApproval;

  const Store({
    required this.id,
    required this.name,
    this.timezone = 'Asia/Kolkata',
    this.invoicePrefix = 'SM',
    this.phone,
    this.gstin,
    this.email,
    this.businessType,
    this.businessCategory,
    this.address,
    this.state,
    this.pincode,
    this.logoPath,
    this.signaturePath,
    this.returnThresholdNoApproval = 500,
  });

  Store copyWith({
    String? name,
    String? invoicePrefix,
    String? phone,
    String? gstin,
    String? email,
    String? businessType,
    String? businessCategory,
    String? address,
    String? state,
    String? pincode,
    String? logoPath,
    String? signaturePath,
    double? returnThresholdNoApproval,
  }) {
    return Store(
      id: id,
      name: name ?? this.name,
      timezone: timezone,
      invoicePrefix: invoicePrefix ?? this.invoicePrefix,
      phone: phone ?? this.phone,
      gstin: gstin ?? this.gstin,
      email: email ?? this.email,
      businessType: businessType ?? this.businessType,
      businessCategory: businessCategory ?? this.businessCategory,
      address: address ?? this.address,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      logoPath: logoPath ?? this.logoPath,
      signaturePath: signaturePath ?? this.signaturePath,
      returnThresholdNoApproval: returnThresholdNoApproval ?? this.returnThresholdNoApproval,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'timezone': timezone,
        'invoice_prefix': invoicePrefix,
        'phone': phone,
        'gstin': gstin,
        'email': email,
        'business_type': businessType,
        'business_category': businessCategory,
        'address': address,
        'state': state,
        'pincode': pincode,
        'logo_path': logoPath,
        'signature_path': signaturePath,
        'return_threshold_no_approval': returnThresholdNoApproval,
      };

  factory Store.fromJson(Map<String, dynamic> map) => Store(
        id: map['id'] as String,
        name: map['name'] as String,
        timezone: map['timezone'] as String? ?? 'Asia/Kolkata',
        invoicePrefix: map['invoice_prefix'] as String? ?? 'SM',
        phone: map['phone'] as String?,
        gstin: map['gstin'] as String?,
        email: map['email'] as String?,
        businessType: map['business_type'] as String?,
        businessCategory: map['business_category'] as String?,
        address: map['address'] as String?,
        state: map['state'] as String?,
        pincode: map['pincode'] as String?,
        logoPath: map['logo_path'] as String?,
        signaturePath: map['signature_path'] as String?,
        returnThresholdNoApproval: (map['return_threshold_no_approval'] as num?)?.toDouble() ?? 500,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        phone,
        gstin,
        email,
        businessType,
        businessCategory,
        address,
        state,
        pincode,
        logoPath,
        signaturePath,
        returnThresholdNoApproval,
      ];
}
