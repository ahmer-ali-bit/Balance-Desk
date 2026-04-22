class SummarySnapshot {
  const SummarySnapshot({
    this.id,
    required this.savedAt,
    required this.overallDebit,
    required this.overallCredit,
    required this.customerCount,
  });

  final int? id;
  final String savedAt;
  final double overallDebit;
  final double overallCredit;
  final int customerCount;

  double get finalBalance => overallDebit - overallCredit;

  factory SummarySnapshot.fromMap(Map<String, Object?> map) {
    return SummarySnapshot(
      id: map['id'] as int?,
      savedAt: map['savedAt'] as String,
      overallDebit: (map['overallDebit'] as num).toDouble(),
      overallCredit: (map['overallCredit'] as num).toDouble(),
      customerCount: map['customerCount'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'savedAt': savedAt,
      'overallDebit': overallDebit,
      'overallCredit': overallCredit,
      'customerCount': customerCount,
    };
  }
}
