import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/customer.dart';
import '../models/entry.dart';

class PdfService {
  const PdfService();

  static const List<String> _ledgerHeaders = <String>[
    'Entry Date',
    'Created Date',
    'Page No',
    'Description',
    'Debit',
    'Credit',
    'Balance',
  ];

  static const Map<int, pw.Alignment> _ledgerCellAlignments =
      <int, pw.Alignment>{
        2: pw.Alignment.center,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
      };

  static final Map<int, pw.TableColumnWidth> _ledgerColumnWidths =
      <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(1.45),
        1: const pw.FlexColumnWidth(1.45),
        2: const pw.FlexColumnWidth(0.95),
        3: const pw.FlexColumnWidth(2.7),
        4: const pw.FlexColumnWidth(1.1),
        5: const pw.FlexColumnWidth(1.1),
        6: const pw.FlexColumnWidth(1.45),
      };

  Future<Uint8List> generateCustomerLedgerPdf({
    required Customer customer,
    required List<Entry> entries,
  }) async {
    final pdf = pw.Document();
    final rows = _buildLedgerRows(entries);
    final totalDebit = entries.fold<double>(
      0,
      (double sum, Entry entry) => sum + entry.debit,
    );
    final totalCredit = entries.fold<double>(
      0,
      (double sum, Entry entry) => sum + entry.credit,
    );
    final finalBalance = totalDebit - totalCredit;
    final entryCount = entries
        .where((Entry entry) => !_isOpeningBalanceEntry(entry))
        .length;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
        ),
        header: (pw.Context context) {
          return _buildLedgerPageHeader(
            context: context,
            customer: customer,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            finalBalance: finalBalance,
            entryCount: entryCount,
          );
        },
        build: (pw.Context context) {
          return <pw.Widget>[
            if (rows.isEmpty)
              _buildEmptyState('No ledger entries available.')
            else
              _buildCompactTextTableBody(
                headers: _ledgerHeaders,
                rows: rows,
                cellAlignments: _ledgerCellAlignments,
                columnWidths: _ledgerColumnWidths,
              ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> exportCustomerLedgerPdf({
    required Customer customer,
    required List<Entry> entries,
  }) async {
    final bytes = await generateCustomerLedgerPdf(
      customer: customer,
      entries: entries,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: _buildFileName(customer.name),
    );
  }

  Future<void> printCustomerLedgerPdf({
    required Customer customer,
    required List<Entry> entries,
  }) async {
    await Printing.layoutPdf(
      name: _buildFileName(customer.name),
      onLayout: (PdfPageFormat format) {
        return generateCustomerLedgerPdf(customer: customer, entries: entries);
      },
    );
  }

  Future<void> exportSnapshotPdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required String fileName,
    List<({String label, String value})> summaryItems = const [],
    Map<int, pw.Alignment> cellAlignments = const <int, pw.Alignment>{},
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) async {
    final bytes = await generateSnapshotPdf(
      title: title,
      headers: headers,
      rows: rows,
      summaryItems: summaryItems,
      cellAlignments: cellAlignments,
      columnWidths: columnWidths,
    );

    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  Future<Uint8List> generateSnapshotPdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    List<({String label, String value})> summaryItems = const [],
    Map<int, pw.Alignment> cellAlignments = const <int, pw.Alignment>{},
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) async {
    final pdf = pw.Document();
    final resolvedColumnWidths =
        columnWidths ?? _resolveSnapshotColumnWidths(headers);
    final resolvedCellAlignments = cellAlignments.isEmpty
        ? _resolveSnapshotCellAlignments(headers)
        : cellAlignments;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
        ),
        header: (pw.Context context) {
          return _buildSnapshotPageHeader(
            context: context,
            title: title,
            headers: headers,
            summaryItems: summaryItems,
            cellAlignments: resolvedCellAlignments,
            columnWidths: resolvedColumnWidths,
          );
        },
        build: (pw.Context context) {
          return <pw.Widget>[
            if (rows.isEmpty)
              _buildEmptyState('No snapshot rows available.')
            else
              _buildCompactTextTableBody(
                headers: headers,
                rows: rows,
                cellAlignments: resolvedCellAlignments,
                columnWidths: resolvedColumnWidths,
              ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildLedgerPageHeader({
    required pw.Context context,
    required Customer customer,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required int entryCount,
  }) {
    final titleBlock = _buildDocumentTitle(
      title: 'Customer Ledger',
      subtitle: customer.name,
    );

    if (context.pageNumber == 1) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          titleBlock,
          pw.SizedBox(height: 10),
          _buildLedgerSummaryCard(
            customer: customer,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
            finalBalance: finalBalance,
            entryCount: entryCount,
          ),
          pw.SizedBox(height: 12),
          _buildCompactTextTableHeader(
            headers: _ledgerHeaders,
            cellAlignments: _ledgerCellAlignments,
            columnWidths: _ledgerColumnWidths,
          ),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        titleBlock,
        pw.SizedBox(height: 6),
        _buildPageMetaLine(
          'Entries: $entryCount | Balance: ${_formatBalance(finalBalance)}',
        ),
        pw.SizedBox(height: 8),
        _buildCompactTextTableHeader(
          headers: _ledgerHeaders,
          cellAlignments: _ledgerCellAlignments,
          columnWidths: _ledgerColumnWidths,
        ),
      ],
    );
  }

  pw.Widget _buildSnapshotPageHeader({
    required pw.Context context,
    required String title,
    required List<String> headers,
    required List<({String label, String value})> summaryItems,
    required Map<int, pw.Alignment> cellAlignments,
    required Map<int, pw.TableColumnWidth> columnWidths,
  }) {
    final children = <pw.Widget>[_buildDocumentTitle(title: title)];

    if (context.pageNumber == 1 && summaryItems.isNotEmpty) {
      children.addAll(<pw.Widget>[
        pw.SizedBox(height: 10),
        _buildSummaryItems(summaryItems),
      ]);
    }

    children.addAll(<pw.Widget>[
      pw.SizedBox(height: 10),
      _buildCompactTextTableHeader(
        headers: headers,
        cellAlignments: cellAlignments,
        columnWidths: columnWidths,
      ),
    ]);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  pw.Widget _buildDocumentTitle({required String title, String? subtitle}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        if ((subtitle ?? '').trim().isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 3),
          pw.Text(
            subtitle!,
            style: pw.TextStyle(fontSize: 9.5, color: PdfColors.blueGrey700),
          ),
        ],
      ],
    );
  }

  pw.Widget _buildPageMetaLine(String value) {
    return pw.Text(
      value,
      style: pw.TextStyle(fontSize: 8.5, color: PdfColors.blueGrey700),
    );
  }

  pw.Widget _buildSummaryItems(List<({String label, String value})> items) {
    final groupedSummary = _buildSnapshotSummaryItems(items);
    if (groupedSummary != null) {
      return groupedSummary;
    }

    if (items.length <= 4) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: List<pw.Widget>.generate(items.length * 2 - 1, (int index) {
          if (index.isOdd) {
            return pw.SizedBox(width: 10);
          }

          return pw.Expanded(child: _buildSummaryItemCard(items[index ~/ 2]));
        }),
      );
    }

    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map<pw.Widget>((item) => _buildSummaryItemCard(item, width: 150))
          .toList(growable: false),
    );
  }

  pw.Widget? _buildSnapshotSummaryItems(
    List<({String label, String value})> items,
  ) {
    final openingItems = <({String label, String value})>[];
    final snapshotItems = <({String label, String value})>[];

    for (final item in items) {
      final group = _summaryItemGroup(item.label);
      if (group == null) {
        return null;
      }

      if (group == 'opening') {
        openingItems.add(item);
      } else {
        snapshotItems.add(item);
      }
    }

    if (openingItems.isEmpty) {
      return null;
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _buildSummaryItemRow(
          openingItems,
          tint: const PdfColor.fromInt(0xFFFFF6ED),
        ),
        if (snapshotItems.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 8),
          _buildSummaryItemRow(
            snapshotItems,
            tint: const PdfColor.fromInt(0xFFF2F7FF),
          ),
        ],
      ],
    );
  }

  String? _summaryItemGroup(String label) {
    final normalizedLabel = label.trim().toLowerCase();

    if (normalizedLabel.startsWith('opening ')) {
      return 'opening';
    }

    if (normalizedLabel == 'last saved snapshot' ||
        normalizedLabel.startsWith('snapshot ')) {
      return 'snapshot';
    }

    return null;
  }

  pw.Widget _buildSummaryItemRow(
    List<({String label, String value})> items, {
    required PdfColor tint,
  }) {
    if (items.isEmpty) {
      return pw.SizedBox.shrink();
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: List<pw.Widget>.generate(items.length * 2 - 1, (int index) {
        if (index.isOdd) {
          return pw.SizedBox(width: 8);
        }

        return pw.Expanded(
          child: _buildSummaryItemCard(
            items[index ~/ 2],
            tint: tint,
            compact: true,
          ),
        );
      }),
    );
  }

  pw.Widget _buildSummaryItemCard(
    ({String label, String value}) item, {
    PdfColor? tint,
    double? width,
    bool compact = false,
  }) {
    return pw.Container(
      width: width,
      padding: pw.EdgeInsets.symmetric(
        horizontal: compact ? 12 : 10,
        vertical: compact ? 8 : 10,
      ),
      decoration: pw.BoxDecoration(
        color: tint ?? const PdfColor.fromInt(0xFFF7F9FC),
        borderRadius: pw.BorderRadius.circular(compact ? 16 : 14),
        border: pw.Border.all(color: PdfColors.blueGrey200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            item.label,
            style: pw.TextStyle(
              fontSize: compact ? 8.2 : 8.5,
              color: PdfColors.blueGrey700,
            ),
          ),
          pw.SizedBox(height: compact ? 3 : 4),
          pw.Text(
            item.value,
            style: pw.TextStyle(
              fontSize: compact ? 11.8 : 12.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildLedgerSummaryCard({
    required Customer customer,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required int entryCount,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blueGrey200),
        borderRadius: pw.BorderRadius.circular(10),
        color: const PdfColor.fromInt(0xFFF7F9FC),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            customer.name,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Customer ID: ${customer.id ?? '-'}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _buildHeaderMeta(
                  label: 'Address',
                  value: customer.displayAddress,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildHeaderMeta(
                  label: 'Phone',
                  value: customer.displayPhone,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Ledger Summary',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey700,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: <pw.Widget>[
              _buildTotalCard(
                label: 'Total Debit',
                value: _formatAmount(totalDebit),
                tint: const PdfColor.fromInt(0xFFE7F5FF),
              ),
              pw.SizedBox(width: 10),
              _buildTotalCard(
                label: 'Total Credit',
                value: _formatAmount(totalCredit),
                tint: const PdfColor.fromInt(0xFFEFFCF3),
              ),
              pw.SizedBox(width: 10),
              _buildTotalCard(
                label: 'Balance',
                value: _formatBalance(finalBalance),
                tint: const PdfColor.fromInt(0xFFFFF4E5),
              ),
              pw.SizedBox(width: 10),
              _buildTotalCard(
                label: 'Entries',
                value: '$entryCount',
                tint: const PdfColor.fromInt(0xFFF2F4F7),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTotalCard({
    required String label,
    required String value,
    required PdfColor tint,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: pw.BoxDecoration(
          color: tint,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.blueGrey200),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8.5, color: PdfColors.blueGrey700),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildHeaderMeta({required String label, required String value}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 8.5, color: PdfColors.blueGrey600),
        ),
        pw.SizedBox(height: 3),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  pw.Widget _buildEmptyState(String value) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blueGrey200),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(value),
    );
  }

  List<List<String>> _buildLedgerRows(List<Entry> entries) {
    final rows = <List<String>>[];
    double? runningBalance;

    for (final entry in entries) {
      final hasValue = entry.debit != 0 || entry.credit != 0;
      String balanceLabel = '';

      if (hasValue) {
        final currentBalance =
            (runningBalance ?? 0) + entry.debit - entry.credit;
        runningBalance = currentBalance;
        balanceLabel = _formatBalance(currentBalance);
      }

      rows.add(<String>[
        _formatDate(entry.entryDate),
        _formatDate(entry.createdAt),
        entry.pageNo.isEmpty ? '-' : entry.pageNo,
        entry.displayDescription,
        _formatAmount(entry.debit),
        _formatAmount(entry.credit),
        balanceLabel,
      ]);
    }

    return rows;
  }

  bool _isOpeningBalanceEntry(Entry entry) {
    return entry.id == null && entry.entryDate == '-' && entry.createdAt == '-';
  }

  pw.Widget _buildCompactTextTableHeader({
    required List<String> headers,
    Map<int, pw.Alignment> cellAlignments = const <int, pw.Alignment>{},
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 7.5,
    );

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.6),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFE3F2FD),
          ),
          children: List<pw.Widget>.generate(headers.length, (int index) {
            return _buildTableCell(
              value: headers[index],
              style: headerStyle,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 3,
              ),
              alignment:
                  cellAlignments[index] ??
                  _defaultAlignmentForHeader(headers[index]),
            );
          }),
        ),
      ],
    );
  }

  pw.Widget _buildCompactTextTableBody({
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, pw.Alignment> cellAlignments = const <int, pw.Alignment>{},
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) {
    const cellStyle = pw.TextStyle(fontSize: 6.8);
    const padding = pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.6),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: rows
          .map<pw.TableRow>((List<String> row) {
            return pw.TableRow(
              children: List<pw.Widget>.generate(headers.length, (int index) {
                return _buildTableCell(
                  value: index < row.length ? row[index] : '',
                  style: cellStyle,
                  padding: padding,
                  alignment:
                      cellAlignments[index] ??
                      _defaultAlignmentForHeader(headers[index]),
                );
              }),
            );
          })
          .toList(growable: false),
    );
  }

  pw.Alignment _defaultAlignmentForHeader(String header) {
    final normalized = header.trim().toLowerCase();
    if (normalized == 'sr #' || normalized == 's/no') {
      return pw.Alignment.center;
    }
    if (normalized.contains('debit') ||
        normalized.contains('credit') ||
        normalized.contains('balance') ||
        normalized.contains('qty') ||
        normalized.contains('quantity')) {
      return pw.Alignment.centerRight;
    }
    if (normalized.contains('page no')) {
      return pw.Alignment.center;
    }
    return pw.Alignment.centerLeft;
  }

  Map<int, pw.Alignment> _resolveSnapshotCellAlignments(List<String> headers) {
    final alignments = <int, pw.Alignment>{};
    for (var index = 0; index < headers.length; index++) {
      alignments[index] = _defaultAlignmentForHeader(headers[index]);
    }
    return alignments;
  }

  Map<int, pw.TableColumnWidth> _resolveSnapshotColumnWidths(
    List<String> headers,
  ) {
    final normalizedHeaders = headers
        .map((String header) => header.trim().toLowerCase())
        .toList(growable: false);

    const summaryHeaders = <String>[
      'sr #',
      'customer',
      'page no',
      'total debit',
      'total credit',
      'balance',
    ];

    const snapshotHeaders = <String>[
      'customer',
      'entry date',
      'description',
      'debit',
      'credit',
      'balance',
      'page no',
    ];

    if (_sameHeaderShape(normalizedHeaders, summaryHeaders)) {
      return <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(0.7),
        1: const pw.FlexColumnWidth(2.35),
        2: const pw.FlexColumnWidth(0.95),
        3: const pw.FlexColumnWidth(1.15),
        4: const pw.FlexColumnWidth(1.15),
        5: const pw.FlexColumnWidth(1.3),
      };
    }

    if (_sameHeaderShape(normalizedHeaders, snapshotHeaders)) {
      return <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(1.65),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(2.45),
        3: const pw.FlexColumnWidth(1.0),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FlexColumnWidth(1.2),
        6: const pw.FlexColumnWidth(0.9),
      };
    }

    return <int, pw.TableColumnWidth>{
      for (var index = 0; index < headers.length; index++)
        index: const pw.FlexColumnWidth(1),
    };
  }

  bool _sameHeaderShape(List<String> current, List<String> expected) {
    if (current.length != expected.length) {
      return false;
    }
    for (var index = 0; index < current.length; index++) {
      if (current[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }

  pw.Widget _buildTableCell({
    required String value,
    required pw.TextStyle style,
    required pw.EdgeInsets padding,
    required pw.Alignment alignment,
  }) {
    return pw.Container(
      alignment: alignment,
      padding: padding,
      child: pw.Text(value, style: style),
    );
  }

  String _formatAmount(double amount) {
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String _formatBalance(double balance) {
    if (balance > 0) {
      return '${_formatAmount(balance)} Debit';
    }
    if (balance < 0) {
      return '${_formatAmount(balance.abs())} Credit';
    }
    return '0';
  }

  String _formatDate(String value) {
    final parsedDate = DateTime.tryParse(value);
    if (parsedDate == null) {
      return value;
    }

    final month = parsedDate.month.toString().padLeft(2, '0');
    final day = parsedDate.day.toString().padLeft(2, '0');
    return '${parsedDate.year}-$month-$day';
  }

  String _buildFileName(String customerName) {
    final safeName = customerName
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    return '${safeName.isEmpty ? 'customer' : safeName}_ledger.pdf';
  }
}
