import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/customer.dart';
import '../models/entry.dart';
import '../utils/number_format_utils.dart';

const PdfColor debitColor = PdfColor.fromInt(0xFF16A34A);
const PdfColor creditColor = PdfColor.fromInt(0xFFDC2626);
const PdfColor debitLightColor = PdfColor.fromInt(0xFFDCFCE7);
const PdfColor creditLightColor = PdfColor.fromInt(0xFFFEE2E2);

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

  static const List<String> _stockLedgerHeaders = <String>[
    'Entry Date',
    'Page No',
    'Buy',
    'Buy Amount',
    'Sell',
    'Sell Amount',
    'Remaining',
    'Balance',
  ];

  static const Map<int, pw.Alignment> _ledgerCellAlignments =
      <int, pw.Alignment>{
        2: pw.Alignment.center,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
      };

  static const Map<int, pw.Alignment> _stockLedgerCellAlignments =
      <int, pw.Alignment>{
        1: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
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

  static final Map<int, pw.TableColumnWidth> _stockLedgerColumnWidths =
      <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(1.2), // Date
        1: const pw.FlexColumnWidth(0.8), // Page No
        2: const pw.FlexColumnWidth(0.9), // Buy Bags
        3: const pw.FlexColumnWidth(1.1), // Buy Amt
        4: const pw.FlexColumnWidth(0.9), // Sell Bags
        5: const pw.FlexColumnWidth(1.1), // Sell Amt
        6: const pw.FlexColumnWidth(1.0), // Rem Bags
        7: const pw.FlexColumnWidth(1.2), // Balance
      };

  Future<Uint8List> generateCustomerLedgerPdf({
    required Customer customer,
    required List<Entry> entries,
  }) async {
    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font, 
        bold: boldFont,
      ),
    );
    final isStock = customer.isStockLedger;
    final useWeight = customer.useWeight;
    final rows = _buildLedgerRows(entries, isStockLedger: isStock, useWeight: useWeight);
    final headers = isStock 
        ? (useWeight 
            ? ['Entry Date', 'Page No', 'Buy Weight', 'Buy Amount', 'Sell Weight', 'Sell Amount', 'Rem. Weight', 'Balance']
            : _stockLedgerHeaders)
        : _ledgerHeaders;
    final cellAlignments = isStock
        ? _stockLedgerCellAlignments
        : _ledgerCellAlignments;
    final columnWidths = isStock
        ? _stockLedgerColumnWidths
        : _ledgerColumnWidths;

    final totalDebit = entries.fold<double>(
      0,
      (double sum, Entry entry) => sum + entry.debit,
    );
    final totalCredit = entries.fold<double>(
      0,
      (double sum, Entry entry) => sum + entry.credit,
    );
    final totalBuyBags = entries.fold<double>(
      0,
      (double sum, Entry entry) => sum + (double.tryParse(entry.buyBags) ?? 0),
    );
    final totalSellBags = entries.fold<double>(
      0,
      (double sum, Entry entry) => sum + (double.tryParse(entry.sellBags) ?? 0),
    );

    final finalBalance = isStock
        ? totalCredit - totalDebit
        : totalDebit - totalCredit;
    final remainingBags = totalBuyBags - totalSellBags;

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
            totalBuyBags: totalBuyBags,
            totalSellBags: totalSellBags,
            remainingBags: remainingBags,
            entryCount: entryCount,
            isStockLedger: isStock,
            useWeight: useWeight,
          );
        },
        build: (pw.Context context) {
          return <pw.Widget>[
            if (rows.isEmpty)
              _buildEmptyState('No ledger entries available.')
            else
              _buildCompactTextTableBody(
                headers: headers,
                rows: rows,
                cellAlignments: cellAlignments,
                columnWidths: columnWidths,
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
    bool highlightFirstRow = false,
    List<String>? openingBalanceRow,
  }) async {
    final bytes = await generateSnapshotPdf(
      title: title,
      headers: headers,
      rows: rows,
      summaryItems: summaryItems,
      cellAlignments: cellAlignments,
      columnWidths: columnWidths,
      highlightFirstRow: highlightFirstRow,
      openingBalanceRow: openingBalanceRow,
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
    bool highlightFirstRow = false,
    List<String>? openingBalanceRow,
  }) async {
    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font, 
        bold: boldFont,
      ),
    );
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
            openingBalanceRow: openingBalanceRow,
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
                highlightFirstRow: highlightFirstRow,
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
    required double totalBuyBags,
    required double totalSellBags,
    required double remainingBags,
    required int entryCount,
    required bool isStockLedger,
    required bool useWeight,
  }) {
    final titleBlock = _buildDocumentTitle(
      title: isStockLedger ? 'Stock Ledger' : 'Customer Ledger',
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
            totalBuyBags: totalBuyBags,
            totalSellBags: totalSellBags,
            remainingBags: remainingBags,
            entryCount: entryCount,
            isStockLedger: isStockLedger,
            useWeight: useWeight,
          ),
          pw.SizedBox(height: 12),
          _buildCompactTextTableHeader(
            headers: isStockLedger ? _stockLedgerHeaders : _ledgerHeaders,
            cellAlignments: isStockLedger
                ? _stockLedgerCellAlignments
                : _ledgerCellAlignments,
            columnWidths: isStockLedger
                ? _stockLedgerColumnWidths
                : _ledgerColumnWidths,
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
          isStockLedger
              ? 'Entries: $entryCount | Remaining: ${useWeight ? formatWeight(remainingBags) : _formatBags(remainingBags)} | Balance: ${_formatBalance(finalBalance)}'
              : 'Entries: $entryCount | Balance: ${_formatBalance(finalBalance)}',
        ),
        pw.SizedBox(height: 8),
        _buildCompactTextTableHeader(
          headers: isStockLedger ? _stockLedgerHeaders : _ledgerHeaders,
          cellAlignments: isStockLedger
              ? _stockLedgerCellAlignments
              : _ledgerCellAlignments,
          columnWidths: isStockLedger
              ? _stockLedgerColumnWidths
              : _ledgerColumnWidths,
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
    List<String>? openingBalanceRow,
  }) {
    final children = <pw.Widget>[
      if (context.pageNumber == 1) _buildDocumentTitle(title: title),
    ];

    // Show Total Debit, Total Credit, Total Balance as cards at top (page 1 only)
    if (context.pageNumber == 1 && summaryItems.isNotEmpty) {
      final isStockSummary =
          summaryItems.length == 6 &&
          summaryItems.any((item) => item.label == 'Buy') &&
          summaryItems.any((item) => item.label == 'Sell');

      if (isStockSummary) {
        // Extract values
        final buyBags = summaryItems
            .firstWhere((i) => i.label == 'Buy')
            .value;
        final buyAmt = summaryItems
            .firstWhere((i) => i.label == 'Buy Amount' || i.label == 'Buy Amt')
            .value;
        final sellBags = summaryItems
            .firstWhere((i) => i.label == 'Sell')
            .value;
        final sellAmt = summaryItems
            .firstWhere(
              (i) => i.label == 'Sell Amount' || i.label == 'Sell Amt',
            )
            .value;
        final remBags = summaryItems
            .firstWhere(
              (i) => i.label == 'Remaining Bags' || i.label == 'Rem. Bags',
            )
            .value;
        final finalBalance = summaryItems
            .firstWhere((i) => i.label == 'Net Balance' || i.label == 'Final Balance')
            .value;

        children.addAll(<pw.Widget>[
          pw.SizedBox(height: 10),
          _buildStockSnapshotSummarySection(
            buyBags: buyBags,
            buyAmt: buyAmt,
            sellBags: sellBags,
            sellAmt: sellAmt,
            remBags: remBags,
            finalBalance: finalBalance,
          ),
        ]);
      } else if (summaryItems.length == 4 && 
                 summaryItems.any((i) => i.label == 'Total Entries') &&
                 summaryItems.any((i) => i.label == 'Total Debit') &&
                 summaryItems.any((i) => i.label == 'Total Credit') &&
                 summaryItems.any((i) => i.label == 'Net Balance')) {
        
        final entries = summaryItems.firstWhere((i) => i.label == 'Total Entries').value;
        final debit = summaryItems.firstWhere((i) => i.label == 'Total Debit').value;
        final credit = summaryItems.firstWhere((i) => i.label == 'Total Credit').value;
        final balance = summaryItems.firstWhere((i) => i.label == 'Net Balance').value;

        children.addAll(<pw.Widget>[
          pw.SizedBox(height: 10),
          _buildDailyLogSummaryCards(
            entries: entries,
            debit: debit,
            credit: credit,
            balance: balance,
          ),
        ]);
      } else {
        children.addAll(<pw.Widget>[
          pw.SizedBox(height: 10),
          _buildSummaryItemRow(
            summaryItems,
            color: const PdfColor.fromInt(0xFFF9FAFB),
          ),
        ]);
      }
    }

    children.addAll(<pw.Widget>[
      pw.SizedBox(height: 10),
      _buildCompactTextTableHeader(
        headers: headers,
        cellAlignments: cellAlignments,
        columnWidths: columnWidths,
      ),
    ]);

    // Show opening balance row highlighted only on first page
    if (context.pageNumber == 1 &&
        openingBalanceRow != null &&
        openingBalanceRow.isNotEmpty) {
      children.addAll(<pw.Widget>[
        pw.SizedBox(height: 0), // no gap - row directly under header
        _buildOpeningBalanceRow(
          row: openingBalanceRow,
          headers: headers,
          cellAlignments: cellAlignments,
          columnWidths: columnWidths,
        ),
        pw.SizedBox(height: 0),
      ]);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  pw.Widget _buildOpeningBalanceRow({
    required List<String> row,
    required List<String> headers,
    required Map<int, pw.Alignment> cellAlignments,
    required Map<int, pw.TableColumnWidth> columnWidths,
  }) {
    final cellStyle = pw.TextStyle(
      fontSize: 6.8,
      fontWeight: pw.FontWeight.bold,
    );
    const padding = pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.6),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFFFF3E0),
          ),
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
        ),
      ],
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

  pw.Widget _buildSummaryItemRow(
    List<({String label, String value})> items, {
    required PdfColor color,
  }) {
    if (items.isEmpty) {
      return pw.SizedBox.shrink();
    }

    final children = <pw.Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(_buildSummaryItemCard(items[i], color: color, compact: true));
      if (i < items.length - 1) {
        children.add(pw.SizedBox(width: 10));
      }
    }

    return pw.Table(
      children: <pw.TableRow>[
        pw.TableRow(
          children: List<pw.Widget>.generate(children.length, (int i) {
            return children[i];
          }),
        ),
      ],
    );
  }

  pw.Widget _buildSummaryItemCard(
    ({String label, String value}) item, {
    PdfColor? color,
    double? width,
    bool compact = false,
  }) {
    return pw.Container(
      width: width,
      padding: pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: color ?? const PdfColor.fromInt(0xFFF7F9FC),
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.blueGrey100, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: <pw.Widget>[
          pw.Text(
            item.label,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey600,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            item.value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
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
    required double totalBuyBags,
    required double totalSellBags,
    required double remainingBags,
    required int entryCount,
    required bool isStockLedger,
    required bool useWeight,
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
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Customer ID: ${customer.id ?? '-'}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              if (isStockLedger)
                pw.Text(
                  'Total Entries: $entryCount',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey700,
                  ),
                ),
            ],
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
            isStockLedger ? 'Stock & Financial Summary' : 'Ledger Summary',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey700,
            ),
          ),
          pw.SizedBox(height: 6),
          if (isStockLedger) ...[
            pw.Row(
              children: <pw.Widget>[
                pw.Expanded(
                  child: _buildTotalCard(
                    label: useWeight ? 'Buy Wt' : 'Buy',
                    value: useWeight ? formatWeight(totalBuyBags) : _formatBags(totalBuyBags),
                    color: debitLightColor,
                    isCompact: true,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: _buildTotalCard(
                    label: 'Buy Amt',
                    value: _formatAmount(totalDebit),
                    color: debitLightColor,
                    isCompact: true,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: _buildTotalCard(
                    label: useWeight ? 'Sell Wt' : 'Sell',
                    value: useWeight ? formatWeight(totalSellBags) : _formatBags(totalSellBags),
                    color: creditLightColor,
                    isCompact: true,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: _buildTotalCard(
                    label: 'Sell Amt',
                    value: _formatAmount(totalCredit),
                    color: creditLightColor,
                    isCompact: true,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: _buildTotalCard(
                    label: useWeight ? 'Rem Wt' : 'Remaining',
                    value: useWeight ? formatWeight(remainingBags) : _formatBags(remainingBags),
                    color: const PdfColor.fromInt(0xFFF1F5F9),
                    isCompact: true,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: _buildTotalCard(
                    label: 'Balance',
                    value: _formatBalance(finalBalance),
                    color: finalBalance == 0
                        ? const PdfColor.fromInt(0xFFF9FAFB)
                        : (finalBalance > 0 ? debitLightColor : creditLightColor),
                    isCompact: true,
                  ),
                ),
              ],
            ),
          ] else
            pw.Row(
              children: <pw.Widget>[
                pw.Expanded(
                  child: _buildTotalCard(
                    label: 'Entries',
                    value: '$entryCount',
                    color: const PdfColor.fromInt(0xFFF2F4F7),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildTotalCard(
                    label: 'Total Debit',
                    value: _formatAmount(totalDebit),
                    color: debitLightColor,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildTotalCard(
                    label: 'Total Credit',
                    value: _formatAmount(totalCredit),
                    color: creditLightColor,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildTotalCard(
                    label: 'Balance',
                    value: _formatBalance(finalBalance),
                    color: finalBalance == 0
                        ? const PdfColor.fromInt(0xFFF9FAFB)
                        : (finalBalance > 0 ? debitLightColor : creditLightColor),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  pw.Widget _buildStockSnapshotSummarySection({
    required String buyBags,
    required String buyAmt,
    required String sellBags,
    required String sellAmt,
    required String remBags,
    required String finalBalance,
    bool useWeight = false,
  }) {
    PdfColor balanceAccent;
    final balanceStr = finalBalance.toLowerCase();
    if (balanceStr.contains('credit')) {
      balanceAccent = creditLightColor;
    } else if (balanceStr.contains('debit')) {
      balanceAccent = debitLightColor;
    } else {
      balanceAccent = const PdfColor.fromInt(0xFFF1F5F9); // Neutral
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blueGrey200),
        borderRadius: pw.BorderRadius.circular(10),
        color: const PdfColor.fromInt(0xFFF7F9FC),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Snapshot Stock & Financial Totals',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey700,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _buildTotalCard(
                      label: useWeight ? 'Total Buy Weight' : 'Total Buy',
                      value: buyBags,
                      color: debitLightColor,
                    ),
                    pw.SizedBox(height: 6),
                    _buildTotalCard(
                      label: 'Total Buy Amt',
                      value: buyAmt,
                      color: debitLightColor,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _buildTotalCard(
                      label: useWeight ? 'Total Sell Weight' : 'Total Sell',
                      value: sellBags,
                      color: creditLightColor,
                    ),
                    pw.SizedBox(height: 6),
                    _buildTotalCard(
                      label: 'Total Sell Amt',
                      value: sellAmt,
                      color: creditLightColor,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _buildTotalCard(
                      label: useWeight ? 'Total Rem. Weight' : 'Total Remaining',
                      value: remBags,
                      color: const PdfColor.fromInt(0xFFE0F2FE), // Blue
                    ),
                    pw.SizedBox(height: 6),
                    _buildTotalCard(
                      label: 'Net Balance',
                      value: finalBalance,
                      color: balanceAccent,
                      isLarge: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

  pw.Widget _buildDailyLogSummaryCards({
    required String entries,
    required String debit,
    required String credit,
    required String balance,
  }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _buildTotalCard(
            label: 'Total Entries',
            value: entries,
            color: const PdfColor.fromInt(0xFFF1F5F9), // Slate 100
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _buildTotalCard(
            label: 'Total Debit',
            value: debit,
            color: const PdfColor.fromInt(0xFFDCFCE7), // Green 100
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _buildTotalCard(
            label: 'Total Credit',
            value: credit,
            color: const PdfColor.fromInt(0xFFFEE2E2), // Red 100
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _buildTotalCard(
            label: 'Net Balance',
            value: balance,
            color: const PdfColor.fromInt(0xFFEFF6FF), // Blue 100
          ),
        ),
      ],
    );
  }

pw.Widget _buildTotalCard({
  required String label,
  required String value,
  required PdfColor color,
  bool isLarge = false,
  bool isCompact = false,
}) {
  return pw.Container(
    width: double.infinity,
    padding: pw.EdgeInsets.symmetric(
      horizontal: isCompact ? 6 : 10,
      vertical: isLarge ? 14 : (isCompact ? 6 : 10),
    ),
    decoration: pw.BoxDecoration(
      color: color,
      borderRadius: pw.BorderRadius.circular(isCompact ? 4 : 8),
      border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: <pw.Widget>[
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: isLarge ? 10 : (isCompact ? 7 : 8.5),
            color: PdfColors.blueGrey800,
            fontWeight: isLarge ? pw.FontWeight.bold : null,
          ),
        ),
        pw.SizedBox(height: isLarge ? 6 : (isCompact ? 2 : 4)),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: isLarge ? 16 : (isCompact ? 10 : 13),
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        ),
      ],
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

List<List<String>> _buildLedgerRows(
  List<Entry> entries, {
  required bool isStockLedger,
  bool useWeight = false,
}) {
  final reversedEntries = entries.reversed.toList();
  final rows = <List<String>>[];
  double? runningBalance;
  double? runningBags;

  for (final entry in reversedEntries) {
    final hasValue = entry.debit != 0 || entry.credit != 0;
    final hasBags = (entry.buyBags.trim().isNotEmpty && entry.buyBags.trim() != '0') || (entry.sellBags.trim().isNotEmpty && entry.sellBags.trim() != '0');

    String balanceLabel = '';
    String bagsLabel = '';

    bool isFirstEntry = _isOpeningBalanceEntry(entry);

    if (hasValue || (isStockLedger && hasBags)) {
      if (isStockLedger) {
        final currentBags = (runningBags ?? 0) + (double.tryParse(entry.buyBags) ?? 0) - (double.tryParse(entry.sellBags) ?? 0);
        runningBags = currentBags;
        bagsLabel = useWeight ? formatWeight(currentBags) : _formatBags(currentBags);

        final currentBalance = (runningBalance ?? 0) + entry.credit - entry.debit;
        runningBalance = currentBalance;
        balanceLabel = _formatBalance(currentBalance);
      } else {
        final currentBalance = (runningBalance ?? 0) + entry.debit - entry.credit;
        runningBalance = currentBalance;
        balanceLabel = _formatBalance(currentBalance);
      }
    }

    if (isStockLedger) {
      final combinedPageNo = isFirstEntry
          ? 'Opening Balance'
          : <String>[
              if (entry.pageNo.isNotEmpty) entry.pageNo,
              if (entry.dailyLogPageNo.isNotEmpty) 'DL: ${entry.dailyLogPageNo}',
            ].join(' | ');

      rows.add(<String>[
        _formatDate(entry.entryDate),
        combinedPageNo.isEmpty ? '-' : combinedPageNo,
        useWeight ? formatWeight(double.tryParse(entry.buyBags) ?? 0) : _formatBagsString(entry.buyBags),
        entry.debit == 0 ? '' : _formatAmount(entry.debit), // Buy Amt (UI: debit)
        useWeight ? formatWeight(double.tryParse(entry.sellBags) ?? 0) : _formatBagsString(entry.sellBags),
        entry.credit == 0
            ? ''
            : _formatAmount(entry.credit), // Sell Amt (UI: credit)
        bagsLabel,
        balanceLabel,
      ]);
    } else {
      rows.add(<String>[
        _formatDate(entry.entryDate),
        _formatDate(entry.createdAt),
        isFirstEntry ? '-' : (entry.pageNo.isEmpty ? '-' : entry.pageNo),
        isFirstEntry ? 'Opening Balance' : _formatDescription(entry, useWeight: useWeight),
        _formatAmount(entry.debit),
        _formatAmount(entry.credit),
        balanceLabel,
      ]);
    }
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
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE3F2FD)),
        children: List<pw.Widget>.generate(headers.length, (int index) {
          return _buildTableCell(
            value: headers[index],
            style: headerStyle,
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
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
  bool highlightFirstRow = false,
}) {
  const cellStyle = pw.TextStyle(fontSize: 6.8);
  final highlightStyle = pw.TextStyle(
    fontSize: 6.8,
    fontWeight: pw.FontWeight.bold,
  );
  const padding = pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2);

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.6),
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    columnWidths: columnWidths,
    children: List<pw.TableRow>.generate(rows.length, (int rowIndex) {
      final row = rows[rowIndex];
      final isFirst = rowIndex == 0 && highlightFirstRow;
      return pw.TableRow(
        decoration: isFirst
            ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE3F2FD))
            : null,
        children: List<pw.Widget>.generate(headers.length, (int colIndex) {
          final header = headers[colIndex].toLowerCase();
          final isBuy = header.contains('buy');
          final isSell = header.contains('sell');
          final isDebit = header.contains('debit');
          final isCredit = header.contains('credit');
          final isRemBags =
              header.contains('rem. bags') || header.contains('remaining');
          final isBalance = header.contains('balance');

          var currentStyle = isFirst ? highlightStyle : cellStyle;

          // Apply bold for key columns
          if (isBuy ||
              isSell ||
              isDebit ||
              isCredit ||
              isRemBags ||
              isBalance) {
            currentStyle = currentStyle.copyWith(
              fontWeight: pw.FontWeight.bold,
            );
          }

          // Apply color based on transaction type or value
          PdfColor? textColor;
          if (isBuy) {
            textColor = creditColor; // Buy -> Red
          } else if (isSell) {
            textColor = debitColor;  // Sell -> Green
          } else if (isDebit) {
            textColor = debitColor;  // Debit -> Green
          } else if (isCredit) {
            textColor = creditColor; // Credit -> Red
          } else if (isRemBags) {
            final cellValue = colIndex < row.length
                ? row[colIndex].replaceAll(',', '')
                : '';
            final val = double.tryParse(cellValue) ?? 0;
            textColor = val >= 0 ? creditColor : debitColor;
          } else if (isBalance) {
            final cellValue = colIndex < row.length
                ? row[colIndex].toLowerCase()
                : '';
            if (cellValue.endsWith(' c')) {
              textColor = creditColor;
            } else if (cellValue.endsWith(' d')) {
              textColor = debitColor;
            }
          }

          return _buildTableCell(
            value: colIndex < row.length ? row[colIndex] : '',
            style: textColor != null
                ? currentStyle.copyWith(color: textColor)
                : currentStyle,
            padding: padding,
            alignment:
                cellAlignments[colIndex] ??
                _defaultAlignmentForHeader(headers[colIndex]),
          );
        }),
      );
    }),
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
      normalized.contains('buy') ||
      normalized.contains('sell') ||
      normalized.contains('remaining') ||
      normalized.contains('amt') ||
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

  const stockSnapshotHeaders = <String>[
    'customer',
    'entry date',
    'description',
    'page no',
    'buy',
    'buy amount',
    'sell',
    'sell amount',
    'remaining',
    'balance',
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

  if (_sameHeaderShape(normalizedHeaders, stockSnapshotHeaders)) {
    return <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.15), // Customer
      1: const pw.FlexColumnWidth(0.75), // Date
      2: const pw.FlexColumnWidth(1.1),  // Description
      3: const pw.FlexColumnWidth(0.6),  // Page No
      4: const pw.FlexColumnWidth(0.55), // Buy Bags
      5: const pw.FlexColumnWidth(0.8),  // Buy Amt
      6: const pw.FlexColumnWidth(0.55), // Sell Bags
      7: const pw.FlexColumnWidth(0.8),  // Sell Amt
      8: const pw.FlexColumnWidth(0.7),  // Rem. Bags
      9: const pw.FlexColumnWidth(1.0),  // Balance
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

String _formatAmount(double amount) => formatAmount(amount);

String _formatBalance(double balance) {
  if (balance > 0) {
    return '${formatAmount(balance)} D';
  }
  if (balance < 0) {
    return '${formatAmount(balance.abs())} C';
  }
  return '0';
}

String _formatBags(double bags) => formatBags(bags);

String _formatBagsString(String bags) => formatBagsString(bags);

String _formatDate(String value) {
  final parsedDate = DateTime.tryParse(value);
  if (parsedDate == null) {
    return value;
  }
  return DateFormat('yyyy-MM-dd').format(parsedDate);
}

String _buildFileName(String customerName) {
  final safeName = customerName
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  return '${safeName.isEmpty ? 'customer' : safeName}_ledger.pdf';
}

String _formatDescription(Entry entry, {bool useWeight = false}) {
  final desc = entry.description.trim();
  final lowerDesc = desc.toLowerCase();
  final parts = <String>[];
  
  if (entry.buyBags.trim().isNotEmpty && entry.buyBags.trim() != '0') {
    final val = double.tryParse(entry.buyBags) ?? 0;
    parts.add(useWeight ? "Buy Wt: ${formatWeight(val)}" : "Buy: ${entry.buyBags.trim()}");
  }
  
  final parsedSellBags = double.tryParse(entry.sellBags) ?? 0;
  if (parsedSellBags > 0 || (entry.sellBags.trim().isNotEmpty && entry.sellBags.trim() != '0')) {
    final val = double.tryParse(entry.sellBags) ?? 0;
    parts.add(useWeight ? "Sell Wt: ${formatWeight(val)}" : "Sell: ${entry.sellBags.trim()}");
  }
  
  if (entry.dailyLogPageNo.isNotEmpty) {
    parts.add("DL Pg: ${entry.dailyLogPageNo}");
  }

  if (desc.isEmpty) {
    return parts.isEmpty ? "-" : parts.join(" | ");
  }

  // If exact match, just show the auto-generated part (e.g., "Buy: 10")
  if ((lowerDesc == 'buy' || lowerDesc == 'sell') && parts.isNotEmpty) {
    return parts.join(" | ");
  }

  // Otherwise, check if keywords are in description to avoid "(Buy: 10)" duplication
  final cleanParts = <String>[];
  for (final part in parts) {
    if (part.startsWith("Buy") && lowerDesc.contains("buy")) {
      final valStr = useWeight ? formatWeight(double.tryParse(entry.buyBags) ?? 0) : entry.buyBags.trim();
      if (lowerDesc.contains(valStr)) {
        continue; // completely omit if quantity is also present
      }
      cleanParts.add(part.replaceFirst(RegExp(r'Buy( Wt)?: '), ''));
    } else if (part.startsWith("Sell") && lowerDesc.contains("sell")) {
      final valStr = useWeight ? formatWeight(double.tryParse(entry.sellBags) ?? 0) : entry.sellBags.trim();
      if (lowerDesc.contains(valStr)) {
        continue; // completely omit if quantity is also present
      }
      cleanParts.add(part.replaceFirst(RegExp(r'Sell( Wt)?: '), ''));
    } else {
      cleanParts.add(part);
    }
  }

  final bagsPart = cleanParts.join(" | ");
  return bagsPart.isEmpty ? desc : "$desc ($bagsPart)";
}
