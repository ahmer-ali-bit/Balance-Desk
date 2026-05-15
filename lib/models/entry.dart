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
    this.buyBags = '',
    this.sellBags = '',
    this.dailyLogPageNo = '',
    this.showInDailyLog = true,
  });

  final int? id;
  final int customerId;
  final String entryDate;
  final String createdAt;
  final String pageNo;
  final String description;
  final double debit;
  final double credit;
  final String buyBags;
  final String sellBags;
  final String dailyLogPageNo;
  final bool showInDailyLog;

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
      buyBags: _cleanBagsString(map['buyBags']?.toString() ?? ''),
      sellBags: _cleanBagsString(map['sellBags']?.toString() ?? ''),
      dailyLogPageNo: map['dailyLogPageNo'] as String? ?? '',
      showInDailyLog: (map['showInDailyLog'] as int? ?? 1) == 1,
    );
  }

  /// Removes trailing decimal point and zeros from purely numeric strings.
  /// e.g. "5.0" → "5", "10.00" → "10", "abc" → "abc", "5.5" → "5.5"
  static String _cleanBagsString(String raw) {
    if (raw.isEmpty) return raw;
    final d = double.tryParse(raw);
    if (d != null && d % 1 == 0) return d.toInt().toString();
    return raw;
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
      'buyBags': buyBags,
      'sellBags': sellBags,
      'dailyLogPageNo': dailyLogPageNo,
      'showInDailyLog': showInDailyLog ? 1 : 0,
    };
  }
}
