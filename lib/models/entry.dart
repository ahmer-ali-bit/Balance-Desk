class Entry {
  const Entry({
    this.id,
    required this.customerId,
    required this.entryDate,
    required this.createdAt,
    required this.pageNo,
    required this.description,
    required this.debit,
    required this.credit,
    this.dailyLogPageNo = '',
  });

  final int? id;
  final int customerId;
  final String entryDate;
  final String createdAt;
  final String pageNo;
  final String description;
  final double debit;
  final double credit;
  final String dailyLogPageNo;

  String get displayDescription =>
      description.trim().isEmpty ? '-' : description.trim();

  factory Entry.fromMap(Map<String, Object?> map) {
    return Entry(
      id: map['id'] as int?,
      customerId: map['customerId'] as int,
      entryDate: map['entryDate'] as String,
      createdAt: map['createdAt'] as String,
      pageNo: map['pageNo'] as String? ?? '',
      description: map['description'] as String,
      debit: (map['debit'] as num).toDouble(),
      credit: (map['credit'] as num).toDouble(),
      dailyLogPageNo: map['dailyLogPageNo'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'customerId': customerId,
      'entryDate': entryDate,
      'createdAt': createdAt,
      'pageNo': pageNo,
      'description': description,
      'debit': debit,
      'credit': credit,
      'dailyLogPageNo': dailyLogPageNo,
    };
  }
}
