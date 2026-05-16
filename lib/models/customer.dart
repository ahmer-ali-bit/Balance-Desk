class Customer {
  const Customer({
    this.id,
    required this.name,
    this.address = '',
    this.phone = '',
    this.isStockLedger = false,
    this.useWeight = false,
  });

  final int? id;
  final String name;
  final String address;
  final String phone;
  final bool isStockLedger;
  final bool useWeight;

  String get displayAddress => address.trim().isEmpty ? '-' : address.trim();
  String get displayPhone => phone.trim().isEmpty ? '-' : phone.trim();

  factory Customer.fromMap(Map<String, Object?> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String,
      address: map['address'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      isStockLedger: (map['isStockLedger'] as int? ?? 0) == 1,
      useWeight: (map['useWeight'] as int? ?? 0) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'isStockLedger': isStockLedger ? 1 : 0,
      'useWeight': useWeight ? 1 : 0,
    };
  }
}
