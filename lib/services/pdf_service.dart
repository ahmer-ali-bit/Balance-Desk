import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/customer.dart';
import '../models/entry.dart';
import '../utils/number_format_utils.dart';
import 'company_profile_service.dart';
import 'export_file_service.dart';

/// Balance Desk — Paper Ledger tokens (see docs/DESIGN.md v1.0).
/// Debit = money in (teal family) · Credit = money out (rose family) ·
/// Brass = premium metadata · Emerald = brand.
const PdfColor _ink = PdfColor.fromInt(0xFF182420);
const PdfColor _inkVariant = PdfColor.fromInt(0xFF55645A);
const PdfColor _emerald = PdfColor.fromInt(0xFF0E5F3D);
const PdfColor _emeraldDeep = PdfColor.fromInt(0xFF12402E);
const PdfColor _emeraldInk = PdfColor.fromInt(0xFF0B241B);
const PdfColor _mint = PdfColor.fromInt(0xFF8FE7B4);
const PdfColor _mintFaint = PdfColor.fromInt(0xFF9FD8B8);
const PdfColor _brassOnDark = PdfColor.fromInt(0xFFE3C878);
const PdfColor _ivory = PdfColor.fromInt(0xFFF4F5F0);
const PdfColor _paper = PdfColor.fromInt(0xFFFFFFFF);
const PdfColor _paperTint = PdfColor.fromInt(0xFFFAFAF7);
const PdfColor _paperWarm = PdfColor.fromInt(0xFFF4F5F0);
const PdfColor _hairline = PdfColor.fromInt(0xFFE7E9E0);
const PdfColor _hairlineStrong = PdfColor.fromInt(0xFFDFE2D8);
const PdfColor _brass = PdfColor.fromInt(0xFF8A6D1D);
const PdfColor _brassSoft = PdfColor.fromInt(0xFFFAF3DC);
const PdfColor _debit = PdfColor.fromInt(0xFF0E7A5F);
const PdfColor _credit = PdfColor.fromInt(0xFFC72B4A);
const PdfColor _debitSoft = PdfColor.fromInt(0xFFE0EFE5);

class _PdfFonts {
  const _PdfFonts({
    required this.latoRegular,
    required this.latoMedium,
    required this.latoSemiBold,
    required this.latoBold,
    required this.latoBlack,
    required this.monoRegular,
    required this.monoSemiBold,
    required this.monoBold,
  });

  final pw.Font latoRegular;
  final pw.Font latoMedium;
  final pw.Font latoSemiBold;
  final pw.Font latoBold;
  final pw.Font latoBlack;
  final pw.Font monoRegular;
  final pw.Font monoSemiBold;
  final pw.Font monoBold;
}

class _PdfBrand {
  const _PdfBrand({this.companyName = '', this.companyLogo});

  final String companyName;
  final pw.ImageProvider? companyLogo;
}

class _StatCell {
  const _StatCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.compact = false,
  });

  final String label;
  final String value;
  final PdfColor? valueColor;
  final bool compact;
}

class PdfService {
  const PdfService();

  static _PdfFonts? _cachedFonts;
  static pw.MemoryImage? _cachedEmblem;
  static bool _emblemLoaded = false;

  static const ExportFileService _fileService = ExportFileService();

  static const List<String> _ledgerHeaders = <String>[
    'Sr #',
    'Entry Date',
    'Page No',
    'Description',
    'Debit',
    'Credit',
    'Balance',
  ];

  static const List<String> _stockLedgerHeaders = <String>[
    'Sr #',
    'Entry Date',
    'Page No',
    'Buy',
    'Buy Amount',
    'Sell',
    'Sell Amount',
    'Remaining',
    'Balance',
  ];

  static const List<String> _stockLedgerWeightHeaders = <String>[
    'Sr #',
    'Entry Date',
    'Page No',
    'Buy Weight',
    'Buy Amount',
    'Sell Weight',
    'Sell Amount',
    'Rem. Weight',
    'Balance',
  ];

  static const Map<int, pw.Alignment> _ledgerCellAlignments =
      <int, pw.Alignment>{
        0: pw.Alignment.center,
        2: pw.Alignment.center,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
      };

  static const Map<int, pw.Alignment> _stockLedgerCellAlignments =
      <int, pw.Alignment>{
        0: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      };

  static final Map<int, pw.TableColumnWidth> _ledgerColumnWidths =
      <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(0.5),
        1: const pw.FlexColumnWidth(1.35),
        2: const pw.FlexColumnWidth(0.9),
        3: const pw.FlexColumnWidth(2.5),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FlexColumnWidth(1.0),
        6: const pw.FlexColumnWidth(1.35),
      };

  static final Map<int, pw.TableColumnWidth> _stockLedgerColumnWidths =
      <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(0.5), // Sr #
        1: const pw.FlexColumnWidth(1.1), // Date
        2: const pw.FlexColumnWidth(0.7), // Page No
        3: const pw.FlexColumnWidth(0.8), // Buy Bags
        4: const pw.FlexColumnWidth(1.0), // Buy Amt
        5: const pw.FlexColumnWidth(0.8), // Sell Bags
        6: const pw.FlexColumnWidth(1.0), // Sell Amt
        7: const pw.FlexColumnWidth(0.9), // Rem Bags
        8: const pw.FlexColumnWidth(1.1), // Balance
      };

  static final Map<int, pw.TableColumnWidth> _stockLedgerWeightColumnWidths =
      <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(0.5), // Sr #
        1: const pw.FlexColumnWidth(1.0), // Date
        2: const pw.FlexColumnWidth(0.7), // Page No
        3: const pw.FlexColumnWidth(0.8), // Buy Weight
        4: const pw.FlexColumnWidth(1.0), // Buy Amt
        5: const pw.FlexColumnWidth(0.8), // Sell Weight
        6: const pw.FlexColumnWidth(1.0), // Sell Amt
        7: const pw.FlexColumnWidth(0.9), // Rem Weight
        8: const pw.FlexColumnWidth(1.1), // Balance
      };

  static const Map<int, pw.Alignment> _stockLedgerWeightCellAlignments =
      <int, pw.Alignment>{
        0: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      };

  static Future<_PdfFonts> _loadFonts() async {
    final cached = _cachedFonts;
    if (cached != null) {
      return cached;
    }
    final fonts = _PdfFonts(
      latoRegular: pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Regular.ttf')),
      latoMedium: pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Medium.ttf')),
      latoSemiBold: pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-SemiBold.ttf')),
      latoBold: pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Bold.ttf')),
      latoBlack: pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Black.ttf')),
      monoRegular: pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexMono-Regular.ttf')),
      monoSemiBold: pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexMono-SemiBold.ttf')),
      monoBold: pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexMono-Bold.ttf')),
    );
    _cachedFonts = fonts;
    return fonts;
  }

  static Future<pw.MemoryImage?> _loadEmblem() async {
    if (_emblemLoaded) {
      return _cachedEmblem;
    }
    _emblemLoaded = true;
    try {
      final data = await rootBundle.load('assets/logo.png');
      _cachedEmblem = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      _cachedEmblem = null;
    }
    return _cachedEmblem;
  }

  static Future<_PdfBrand> _loadBrand() async {
    try {
      final service = CompanyProfileService();
      final profile = await service.loadProfile();
      final name = profile.name.trim();
      pw.MemoryImage? logo;
      final logoPath = profile.logoPath?.trim() ?? '';
      if (logoPath.isNotEmpty) {
        try {
          final file = File(logoPath);
          if (await file.exists()) {
            logo = pw.MemoryImage(await file.readAsBytes());
          }
        } catch (_) {
          logo = null;
        }
      }
      return _PdfBrand(companyName: name, companyLogo: logo);
    } catch (_) {
      return const _PdfBrand();
    }
  }

  Future<Uint8List> generateCustomerLedgerPdf({
    required Customer customer,
    required List<Entry> entries,
  }) async {
    final fonts = await _loadFonts();
    final brand = await _loadBrand();
    final emblem = await _loadEmblem();

    final pdf = pw.Document(
      title: customer.isStockLedger
          ? '${customer.name} — Stock Ledger'
          : '${customer.name} — Customer Ledger',
      author: 'Balance Desk',
      creator: 'Balance Desk',
      theme: pw.ThemeData.withFont(
        base: fonts.latoRegular,
        bold: fonts.latoBold,
        italic: fonts.latoRegular,
        boldItalic: fonts.latoBold,
      ),
    );
    final isStock = customer.isStockLedger;
    final useWeight = customer.useWeight;
    final rows = _buildLedgerRows(entries, isStockLedger: isStock, useWeight: useWeight);
    final headers = isStock
        ? (useWeight
            ? _stockLedgerWeightHeaders
            : _stockLedgerHeaders)
        : _ledgerHeaders;
    final cellAlignments = isStock
        ? (useWeight
            ? _stockLedgerWeightCellAlignments
            : _stockLedgerCellAlignments)
        : _ledgerCellAlignments;
    final columnWidths = isStock
        ? (useWeight
            ? _stockLedgerWeightColumnWidths
            : _stockLedgerColumnWidths)
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

    final docLabel = isStock ? 'Stock Ledger' : 'Customer Ledger';

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 16),
        ),
        header: (pw.Context context) => _buildContinuousHeader(
          context: context,
          fonts: fonts,
          brand: brand,
          emblem: emblem,
          documentTitle: docLabel,
          subtitle: customer.name,
          firstPageBody: <pw.Widget>[
            pw.SizedBox(height: 10),
            _buildCustomerMetaPanel(fonts, customer, isStock: isStock),
            pw.SizedBox(height: 10),
            _buildLedgerStatStrip(
              fonts,
              isStockLedger: isStock,
              useWeight: useWeight,
              entryCount: entryCount,
              totalDebit: totalDebit,
              totalCredit: totalCredit,
              finalBalance: finalBalance,
              totalBuyBags: totalBuyBags,
              totalSellBags: totalSellBags,
              remainingBags: remainingBags,
            ),
          ],
          headers: headers,
          cellAlignments: cellAlignments,
          columnWidths: columnWidths,
        ),
        footer: (pw.Context context) => _buildFooter(context, fonts, docLabel),
        build: (pw.Context context) {
          return <pw.Widget>[
            if (rows.isEmpty)
              _buildEmptyState(fonts, 'No ledger entries available.')
            else
              _buildCompactTextTableBody(
                fonts: fonts,
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

  Future<ExportFileResult> exportCustomerLedgerPdf({
    required Customer customer,
    required List<Entry> entries,
  }) async {
    final bytes = await generateCustomerLedgerPdf(
      customer: customer,
      entries: entries,
    );
    return _fileService.saveBytes(
      fileName: _buildFileName(customer.name),
      bytes: bytes,
      dialogTitle: 'Save customer ledger PDF',
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

  Future<ExportFileResult> exportSnapshotPdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required String fileName,
    String? subtitle,
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
      subtitle: subtitle,
      summaryItems: summaryItems,
      cellAlignments: cellAlignments,
      columnWidths: columnWidths,
      highlightFirstRow: highlightFirstRow,
      openingBalanceRow: openingBalanceRow,
    );

    return _fileService.saveBytes(
      fileName: fileName,
      bytes: bytes,
      dialogTitle: 'Save $title PDF',
    );
  }

  Future<Uint8List> generateSnapshotPdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String? subtitle,
    List<({String label, String value})> summaryItems = const [],
    Map<int, pw.Alignment> cellAlignments = const <int, pw.Alignment>{},
    Map<int, pw.TableColumnWidth>? columnWidths,
    bool highlightFirstRow = false,
    List<String>? openingBalanceRow,
  }) async {
    final fonts = await _loadFonts();
    final brand = await _loadBrand();
    final emblem = await _loadEmblem();

    final pdf = pw.Document(
      title: title,
      author: 'Balance Desk',
      creator: 'Balance Desk',
      theme: pw.ThemeData.withFont(
        base: fonts.latoRegular,
        bold: fonts.latoBold,
        italic: fonts.latoRegular,
        boldItalic: fonts.latoBold,
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
          margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 16),
        ),
        header: (pw.Context context) => _buildContinuousHeader(
          context: context,
          fonts: fonts,
          brand: brand,
          emblem: emblem,
          documentTitle: title,
          subtitle: subtitle,
          firstPageBody: summaryItems.isEmpty
              ? const <pw.Widget>[]
              : <pw.Widget>[
                  pw.SizedBox(height: 10),
                  _buildSummaryStatStrip(fonts, summaryItems),
                ],
          headers: headers,
          cellAlignments: resolvedCellAlignments,
          columnWidths: resolvedColumnWidths,
          openingBalanceRow: openingBalanceRow,
        ),
        footer: (pw.Context context) => _buildFooter(context, fonts, title),
        build: (pw.Context context) {
          return <pw.Widget>[
            if (rows.isEmpty)
              _buildEmptyState(fonts, 'No snapshot rows available.')
            else
              _buildCompactTextTableBody(
                fonts: fonts,
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


  pw.Widget _buildContinuousHeader({
    required pw.Context context,
    required _PdfFonts fonts,
    required _PdfBrand brand,
    required pw.MemoryImage? emblem,
    required String documentTitle,
    required String? subtitle,
    required List<pw.Widget> firstPageBody,
    required List<String> headers,
    required Map<int, pw.Alignment> cellAlignments,
    required Map<int, pw.TableColumnWidth> columnWidths,
    List<String>? openingBalanceRow,
  }) {
    final children = <pw.Widget>[];

    if (context.pageNumber == 1) {
      children.add(
        _buildBrandBand(
          fonts: fonts,
          brand: brand,
          emblem: emblem,
          title: documentTitle,
          titleNote: subtitle,
        ),
      );
      children.addAll(firstPageBody);
      children.add(pw.SizedBox(height: 12));
    } else {
      children.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Text(
                  'BALANCE DESK',
                  style: pw.TextStyle(
                    font: fonts.latoBold,
                    fontSize: 6.2,
                    letterSpacing: 1.6,
                    color: _inkVariant,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Text(
                  '·  ${documentTitle.toUpperCase()}',
                  style: pw.TextStyle(
                    font: fonts.latoBold,
                    fontSize: 6.2,
                    letterSpacing: 1.3,
                    color: _inkVariant,
                  ),
                ),
                pw.Spacer(),
                if ((subtitle ?? '').trim().isNotEmpty)
                  pw.Text(
                    subtitle!.toUpperCase(),
                    style: pw.TextStyle(
                      font: fonts.monoSemiBold,
                      fontSize: 6.8,
                      letterSpacing: 0.6,
                      color: _ink,
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Container(height: 0.8, color: _hairlineStrong),
            pw.SizedBox(height: 8),
          ],
        ),
      );
    }

    children.add(
      _buildCompactTextTableHeader(
        fonts: fonts,
        headers: headers,
        cellAlignments: cellAlignments,
        columnWidths: columnWidths,
      ),
    );

    if (context.pageNumber == 1 &&
        openingBalanceRow != null &&
        openingBalanceRow.isNotEmpty) {
      children.add(
        _buildOpeningBalanceRow(
          fonts: fonts,
          row: openingBalanceRow,
          headers: headers,
          cellAlignments: cellAlignments,
          columnWidths: columnWidths,
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  pw.Widget _buildBrandBand({
    required _PdfFonts fonts,
    required _PdfBrand brand,
    required pw.MemoryImage? emblem,
    required String title,
    required String? titleNote,
  }) {
    final companyName = brand.companyName.trim();

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(12),
        gradient: const pw.LinearGradient(
          begin: pw.Alignment.centerLeft,
          end: pw.Alignment.centerRight,
          colors: <PdfColor>[_emeraldDeep, _emeraldInk],
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          if (emblem != null) ...<pw.Widget>[
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFF08150F),
                shape: pw.BoxShape.circle,
                border: pw.Border.all(
                  color: const PdfColor.fromInt(0x595BE0A4),
                  width: 0.9,
                ),
              ),
              child: pw.Image(
                emblem,
                width: 30,
                height: 30,
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'BALANCE DESK',
                  style: pw.TextStyle(
                    font: fonts.latoBold,
                    fontSize: 7.6,
                    letterSpacing: 2.5,
                    color: _mint,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    font: fonts.latoBlack,
                    fontSize: 19,
                    color: _ivory,
                    letterSpacing: -0.3,
                  ),
                ),
                if ((titleNote ?? '').trim().isNotEmpty) ...<pw.Widget>[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    titleNote!.toUpperCase(),
                    style: pw.TextStyle(
                      font: fonts.latoBold,
                      fontSize: 7,
                      letterSpacing: 1.7,
                      color: _brassOnDark,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (brand.companyLogo != null || companyName.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(width: 12),
            pw.Container(
              constraints: const pw.BoxConstraints(maxWidth: 150),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: <pw.Widget>[
                  pw.Text(
                    'ACCOUNTS OF',
                    style: pw.TextStyle(
                      font: fonts.latoBold,
                      fontSize: 5.6,
                      letterSpacing: 1.8,
                      color: _mintFaint,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  if (brand.companyLogo != null) ...<pw.Widget>[
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(
                        color: _ivory,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Image(
                        brand.companyLogo!,
                        height: 30,
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                    if (companyName.isNotEmpty) pw.SizedBox(height: 4),
                  ],
                  if (companyName.isNotEmpty)
                    pw.Text(
                      companyName,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        font: fonts.latoBold,
                        fontSize: 9.2,
                        color: _ivory,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildCustomerMetaPanel(
    _PdfFonts fonts,
    Customer customer, {
    required bool isStock,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: pw.BoxDecoration(
        color: _paperTint,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _hairlineStrong, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  customer.name,
                  style: pw.TextStyle(
                    font: fonts.latoBlack,
                    fontSize: 14.5,
                    color: _ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: _paperWarm,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: _hairlineStrong, width: 0.7),
                ),
                child: pw.Text(
                  'ID ${customer.id ?? '-'}',
                  style: pw.TextStyle(
                    font: fonts.monoSemiBold,
                    fontSize: 7.2,
                    letterSpacing: 0.5,
                    color: _brass,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: _buildHeaderMeta(
                  fonts,
                  'ADDRESS',
                  customer.displayAddress,
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _buildHeaderMeta(fonts, 'PHONE', customer.displayPhone),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _buildHeaderMeta(
                  fonts,
                  'LEDGER TYPE',
                  isStock ? 'Stock Ledger' : 'Customer Ledger',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildLedgerStatStrip(
    _PdfFonts fonts, {
    required bool isStockLedger,
    required bool useWeight,
    required int entryCount,
    required double totalDebit,
    required double totalCredit,
    required double finalBalance,
    required double totalBuyBags,
    required double totalSellBags,
    required double remainingBags,
  }) {
    final balanceColor = _balanceTone(
      finalBalance,
      positiveIsDebit: !isStockLedger,
    );

    if (isStockLedger) {
      return _statStrip(fonts, <_StatCell>[
        _StatCell(
          label: useWeight ? 'Buy Wt' : 'Total Buy',
          value: useWeight ? formatWeight(totalBuyBags) : _formatBags(totalBuyBags),
          compact: true,
        ),
        _StatCell(
          label: 'Buy Amt',
          value: _formatAmount(totalDebit),
          compact: true,
        ),
        _StatCell(
          label: useWeight ? 'Sell Wt' : 'Total Sell',
          value: useWeight ? formatWeight(totalSellBags) : _formatBags(totalSellBags),
          compact: true,
        ),
        _StatCell(
          label: 'Sell Amt',
          value: _formatAmount(totalCredit),
          compact: true,
        ),
        _StatCell(
          label: useWeight ? 'Rem. Wt' : 'Remaining',
          value: useWeight ? formatWeight(remainingBags) : _formatBags(remainingBags),
          compact: true,
        ),
        _StatCell(
          label: 'Net Balance',
          value: _formatBalance(finalBalance),
          valueColor: balanceColor,
          compact: true,
        ),
      ]);
    }

    return _statStrip(fonts, <_StatCell>[
      _StatCell(label: 'Total Entries', value: '$entryCount'),
      _StatCell(label: 'Total Debit', value: _formatAmount(totalDebit), valueColor: _debit),
      _StatCell(label: 'Total Credit', value: _formatAmount(totalCredit), valueColor: _credit),
      _StatCell(
        label: 'Balance',
        value: _formatBalance(finalBalance),
        valueColor: balanceColor,
      ),
    ]);
  }

  pw.Widget _buildSummaryStatStrip(
    _PdfFonts fonts,
    List<({String label, String value})> summaryItems,
  ) {
    final cells = <_StatCell>[];
    for (final item in summaryItems) {
      PdfColor? tone;
      final normalized = item.label.trim().toLowerCase();
      final value = item.value.trim();
      final lowerValue = value.toLowerCase();
      if (normalized.contains('debit') || normalized.contains('buy')) {
        tone = normalized.contains('buy') ? _ink : _debit;
      } else if (normalized.contains('credit') || normalized.contains('sell')) {
        tone = normalized.contains('sell') ? _ink : _credit;
      }
      if (normalized.contains('balance')) {
        if (lowerValue.endsWith(' c')) {
          tone = _credit;
        } else if (lowerValue.endsWith(' d')) {
          tone = _debit;
        }
      }
      cells.add(
        _StatCell(
          label: item.label,
          value: value,
          valueColor: tone,
          compact: summaryItems.length > 4,
        ),
      );
    }
    return _statStrip(fonts, cells);
  }

  pw.Widget _statStrip(_PdfFonts fonts, List<_StatCell> cells) {
    if (cells.isEmpty) {
      return pw.SizedBox.shrink();
    }

    final children = <pw.Widget>[];
    for (var index = 0; index < cells.length; index++) {
      final cell = cells[index];
      if (index > 0) {
        children.add(
          pw.Container(width: 0.7, height: 40, color: _hairlineStrong),
        );
      }
      children.add(
        pw.Expanded(
          child: pw.Padding(
            padding: pw.EdgeInsets.symmetric(
              horizontal: cell.compact ? 5 : 10,
              vertical: 9,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: <pw.Widget>[
                pw.Text(
                  cell.label.toUpperCase(),
                  maxLines: 1,
                  style: pw.TextStyle(
                    font: fonts.latoBold,
                    fontSize: cell.compact ? 5.4 : 6.1,
                    letterSpacing: 1.0,
                    color: _inkVariant,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  cell.value,
                  maxLines: 1,
                  style: pw.TextStyle(
                    font: fonts.monoBold,
                    fontSize: cell.compact ? 7.6 : 11,
                    color: cell.valueColor ?? _ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _paper,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _hairlineStrong, width: 0.8),
      ),
      child: pw.Row(children: children),
    );
  }

  pw.Widget _buildHeaderMeta(
    _PdfFonts fonts,
    String label,
    String value,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            font: fonts.latoBold,
            fontSize: 5.8,
            letterSpacing: 1.4,
            color: _inkVariant,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value.trim().isEmpty ? '—' : value.trim(),
          maxLines: 2,
          style: pw.TextStyle(
            font: fonts.latoMedium,
            fontSize: 8.6,
            color: _ink,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildFooter(
    pw.Context context,
    _PdfFonts fonts,
    String documentTitle,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Container(height: 0.75, color: _hairlineStrong),
        pw.SizedBox(height: 5),
        pw.Row(
          children: <pw.Widget>[
            pw.Text(
              'BALANCE DESK',
              style: pw.TextStyle(
                font: fonts.latoBold,
                fontSize: 6.2,
                letterSpacing: 1.7,
                color: _inkVariant,
              ),
            ),
            pw.Text(
              '   ·   ${documentTitle.toUpperCase()}',
              style: pw.TextStyle(
                font: fonts.latoBold,
                fontSize: 6.2,
                letterSpacing: 1.2,
                color: _inkVariant,
              ),
            ),
            pw.Spacer(),
            pw.Text(
              'PAGE ${context.pageNumber} OF ${context.pagesCount}',
              style: pw.TextStyle(
                font: fonts.monoSemiBold,
                fontSize: 6.6,
                letterSpacing: 0.8,
                color: _inkVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildEmptyState(_PdfFonts fonts, String value) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: pw.BoxDecoration(
        color: _paperTint,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _hairlineStrong, width: 0.8),
      ),
      child: pw.Text(
        value,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: fonts.latoMedium,
          fontSize: 9,
          color: _inkVariant,
        ),
      ),
    );
  }

  PdfColor _balanceTone(
    double balance, {
    required bool positiveIsDebit,
  }) {
    if (balance == 0) {
      return _ink;
    }
    final isDebit = positiveIsDebit ? balance > 0 : balance < 0;
    return isDebit ? _debit : _credit;
  }

  pw.Widget _buildOpeningBalanceRow({
    required _PdfFonts fonts,
    required List<String> row,
    required List<String> headers,
    required Map<int, pw.Alignment> cellAlignments,
    required Map<int, pw.TableColumnWidth> columnWidths,
  }) {
    final cellStyle = pw.TextStyle(
      font: fonts.latoBold,
      fontSize: 6.8,
      color: _ink,
    );
    final numericStyle = pw.TextStyle(
      font: fonts.monoBold,
      fontSize: 6.8,
      color: _ink,
    );
    const padding = pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.2);

    return pw.Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _hairline, width: 0.5),
        bottom: pw.BorderSide(color: _hairlineStrong, width: 0.8),
      ),
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _brassSoft),
          children: List<pw.Widget>.generate(headers.length, (int index) {
            return _buildTableCell(
              value: index < row.length ? row[index] : '',
              style: _isNumericHeader(headers[index]) ? numericStyle : cellStyle,
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
}

pw.Widget _buildCompactTextTableHeader({
  required _PdfFonts fonts,
  required List<String> headers,
  Map<int, pw.Alignment> cellAlignments = const <int, pw.Alignment>{},
  Map<int, pw.TableColumnWidth>? columnWidths,
}) {
  final headerStyle = pw.TextStyle(
    font: fonts.latoBold,
    fontSize: 6.6,
    color: _ivory,
    letterSpacing: 0.9,
  );

  return pw.Table(
    columnWidths: columnWidths,
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    border: null,
    children: <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _emerald),
        children: List<pw.Widget>.generate(headers.length, (int index) {
          return _buildTableCell(
            value: headers[index].toUpperCase(),
            style: headerStyle,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 6,
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
  required _PdfFonts fonts,
  required List<String> headers,
  required List<List<String>> rows,
  Map<int, pw.Alignment> cellAlignments = const <int, pw.Alignment>{},
  Map<int, pw.TableColumnWidth>? columnWidths,
  bool highlightFirstRow = false,
}) {
  final cellStyle = pw.TextStyle(font: fonts.latoRegular, fontSize: 6.9);
  final numericStyle = pw.TextStyle(font: fonts.monoRegular, fontSize: 6.9);
  final highlightStyle = pw.TextStyle(
    font: fonts.latoBold,
    fontSize: 6.9,
    color: _ink,
  );
  final highlightNumericStyle = pw.TextStyle(
    font: fonts.monoBold,
    fontSize: 6.9,
    color: _ink,
  );
  const padding = pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.4);

  return pw.Table(
    columnWidths: columnWidths,
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    border: pw.TableBorder(
      horizontalInside: const pw.BorderSide(color: _hairline, width: 0.5),
      bottom: const pw.BorderSide(color: _ink, width: 1.3),
    ),
    children: List<pw.TableRow>.generate(rows.length, (int rowIndex) {
      final row = rows[rowIndex];
      final isFirst = rowIndex == 0 && highlightFirstRow;
      final isSnapshotTotal = row.isNotEmpty && row[0] == 'Snapshot Total';
      final isBalanceBF = row.isNotEmpty && row[0] == 'Balance B/F';
      final isHighlighted = isFirst || isSnapshotTotal || isBalanceBF;

      return pw.TableRow(
        decoration: isHighlighted
            ? const pw.BoxDecoration(color: _debitSoft)
            : (rowIndex.isOdd
                  ? const pw.BoxDecoration(color: _paperTint)
                  : null),
        children: List<pw.Widget>.generate(headers.length, (int colIndex) {
          final header = headers[colIndex].toLowerCase();
          final numeric = _isNumericHeader(headers[colIndex]);
          final isBuy = header.contains('buy');
          final isSell = header.contains('sell');
          final isDebit = header.contains('debit');
          final isCredit = header.contains('credit');
          final isRemBags =
              header.contains('rem. bags') ||
              header.contains('remaining') ||
              header.contains('rem. weight');
          final isBalance = header.contains('balance');

          pw.TextStyle currentStyle;
          if (isHighlighted) {
            currentStyle = numeric ? highlightNumericStyle : highlightStyle;
          } else {
            currentStyle = numeric
                ? numericStyle.copyWith(color: _ink)
                : cellStyle.copyWith(color: _ink);
          }

          // Emphasize key figures.
          if (isBuy || isSell || isDebit || isCredit || isRemBags || isBalance) {
            currentStyle = currentStyle.copyWith(
              font: numeric ? fonts.monoSemiBold : fonts.latoSemiBold,
            );
          }

          // Semantic ink colours for money movements.
          PdfColor? textColor;
          if (isBuy) {
            textColor = _credit; // Buy -> payable
          } else if (isSell) {
            textColor = _debit; // Sell -> receivable
          } else if (isDebit) {
            textColor = _debit;
          } else if (isCredit) {
            textColor = _credit;
          } else if (isRemBags) {
            final cellValue = colIndex < row.length
                ? row[colIndex].replaceAll(',', '')
                : '';
            final val = double.tryParse(cellValue) ?? 0;
            textColor = val >= 0 ? _debit : _credit;
          } else if (isBalance) {
            final cellValue = colIndex < row.length
                ? row[colIndex].toLowerCase()
                : '';
            if (cellValue.endsWith(' c')) {
              textColor = _credit;
            } else if (cellValue.endsWith(' d')) {
              textColor = _debit;
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

bool _isNumericHeader(String header) {
  final normalized = header.trim().toLowerCase();
  return normalized == 'sr #' ||
      normalized == 's/no' ||
      normalized.contains('debit') ||
      normalized.contains('credit') ||
      normalized.contains('balance') ||
      normalized.contains('amt') ||
      normalized.contains('amount') ||
      normalized.contains('buy') ||
      normalized.contains('sell') ||
      normalized.contains('remaining') ||
      normalized.contains('quantity') ||
      normalized.contains('qty');
}

List<List<String>> _buildLedgerRows(
  List<Entry> entries, {
  required bool isStockLedger,
  bool useWeight = false,
}) {
  final reversedEntries = entries.reversed.toList();
  final rows = <List<String>>[];
  int srNo = 1;
  double? runningBalance;
  double? runningBags;

  for (final entry in reversedEntries) {
    final hasValue = entry.debit != 0 || entry.credit != 0;
    final hasBags = (entry.buyBags.trim().isNotEmpty && entry.buyBags.trim() != '0') || (entry.sellBags.trim().isNotEmpty && entry.sellBags.trim() != '0');

    String balanceLabel = '';
    String bagsLabel = '';

    final isFirstEntry = _isOpeningBalanceEntry(entry);

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
        srNo.toString(),
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
        srNo.toString(),
        _formatDate(entry.entryDate),
        isFirstEntry ? '-' : (entry.pageNo.isEmpty ? '-' : entry.pageNo),
        isFirstEntry ? 'Opening Balance' : _formatDescription(entry, useWeight: useWeight),
        _formatAmount(entry.debit),
        _formatAmount(entry.credit),
        balanceLabel,
      ]);
    }

    srNo++;
  }

  return rows;
}

bool _isOpeningBalanceEntry(Entry entry) {
  return entry.id == null && entry.entryDate == '-' && entry.createdAt == '-';
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
      normalized.contains('amount') ||
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
    'sr #',
    'customer',
    'entry date',
    'description',
    'debit',
    'credit',
    'balance',
    'page no',
  ];

  const stockSnapshotHeaders = <String>[
    'sr #',
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
      0: const pw.FlexColumnWidth(0.5), // Sr #
      1: const pw.FlexColumnWidth(2.35), // Customer
      2: const pw.FlexColumnWidth(0.95), // Page No
      3: const pw.FlexColumnWidth(1.15), // Total Debit
      4: const pw.FlexColumnWidth(1.15), // Total Credit
      5: const pw.FlexColumnWidth(1.3), // Balance
    };
  }

  if (_sameHeaderShape(normalizedHeaders, snapshotHeaders)) {
    return <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.5), // Sr #
      1: const pw.FlexColumnWidth(1.65), // Customer
      2: const pw.FlexColumnWidth(1.2), // Entry Date
      3: const pw.FlexColumnWidth(2.45), // Description
      4: const pw.FlexColumnWidth(1.0), // Debit
      5: const pw.FlexColumnWidth(1.0), // Credit
      6: const pw.FlexColumnWidth(1.2), // Balance
      7: const pw.FlexColumnWidth(0.9), // Page No
    };
  }

  if (_sameHeaderShape(normalizedHeaders, stockSnapshotHeaders)) {
    return <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.5), // Sr #
      1: const pw.FlexColumnWidth(1.15), // Customer
      2: const pw.FlexColumnWidth(0.75), // Date
      3: const pw.FlexColumnWidth(1.1),  // Description
      4: const pw.FlexColumnWidth(0.6),  // Page No
      5: const pw.FlexColumnWidth(0.55), // Buy Bags
      6: const pw.FlexColumnWidth(0.8),  // Buy Amt
      7: const pw.FlexColumnWidth(0.55), // Sell Bags
      8: const pw.FlexColumnWidth(0.8),  // Sell Amt
      9: const pw.FlexColumnWidth(0.7),  // Rem. Bags
      10: const pw.FlexColumnWidth(1.0),  // Balance
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
    child: pw.Text(value, style: style, maxLines: 3),
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
