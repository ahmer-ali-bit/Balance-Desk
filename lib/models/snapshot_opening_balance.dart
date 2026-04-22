class SnapshotOpeningBalance {
  const SnapshotOpeningBalance({required this.debit, required this.credit});

  final double debit;
  final double credit;

  bool get hasValue => debit > 0 || credit > 0;

  double get finalBalance => debit - credit;
}
