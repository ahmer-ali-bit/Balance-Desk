class Customer {
  const Customer({
    this.id,
    required this.name,
    this.address = '',
    this.phone = '',
  });

  final int? id;
  final String name;
  final String address;
  final String phone;

  String get displayAddress => address.trim().isEmpty ? '-' : address.trim();
  String get displayPhone => phone.trim().isEmpty ? '-' : phone.trim();

  factory Customer.fromMap(Map<String, Object?> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String,
      address: map['address'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
    };
  }
}
