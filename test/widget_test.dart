import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shop/database/app_database.dart';
import 'package:shop/providers/customer_provider.dart';
import 'package:shop/providers/linked_devices_provider.dart';
import 'package:shop/screens/customer_list_screen.dart';

void main() {
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await AppDatabase.instance.close();
    final databasePath = await AppDatabase.instance.databasePath;
    final databaseFile = File(databasePath);
    if (await databaseFile.exists()) {
      await databaseFile.delete();
    }

    await AppDatabase.instance.initialize();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  testWidgets('customer screen renders without framework exceptions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => CustomerProvider()..loadCustomers(),
          ),
          ChangeNotifierProvider(create: (_) => LinkedDevicesProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: CustomerListScreen())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
  });

  test('customer provider can add and reload a customer', () async {
    final provider = CustomerProvider();

    await provider.loadCustomers();
    expect(provider.customers, isEmpty);

    final customer = await provider.addCustomerAndReturn('Ali Traders');
    expect(customer, isNotNull);
    expect(customer!.name, 'Ali Traders');

    await provider.loadCustomers();
    expect(
      provider.customers.any((customer) => customer.name == 'Ali Traders'),
      isTrue,
    );

    provider.dispose();
  });

  test('customer provider blocks duplicate customer names', () async {
    final provider = CustomerProvider();

    await provider.loadCustomers();

    final firstCustomer = await provider.addCustomerAndReturn('Ali Traders');
    expect(firstCustomer, isNotNull);

    final duplicateCustomer = await provider.addCustomerAndReturn(
      '  ali traders  ',
    );
    expect(duplicateCustomer, isNull);
    expect(
      provider.errorMessage,
      'A customer named "ali traders" already exists.',
    );

    await provider.loadCustomers();
    expect(provider.customers.length, 1);

    provider.dispose();
  });

  test('moving an unsaved entry recalculates its target snapshot totals', () async {
    final database = AppDatabase.instance;
    final customerId = await database.addCustomer('Snapshot customer');
    const savedAt = '2026-01-02T12:00:00.000';

    await database.addSummarySnapshot(
      savedAt: savedAt,
      overallDebit: 0,
      overallCredit: 0,
      customerCount: 0,
      dailyLogPageNo: '7',
    );
    const nextSavedAt = '2026-01-03T12:00:00.000';
    await database.addSummarySnapshot(
      savedAt: nextSavedAt,
      overallDebit: 0,
      overallCredit: 0,
      customerCount: 0,
      dailyLogPageNo: '8',
    );
    final entryId = await database.addEntry(
      customerId: customerId,
      entryDate: '2026-01-04T00:00:00.000',
      createdAt: '2026-01-04T00:00:00.000',
      pageNo: '3',
      description: 'Moved entry',
      debit: 42.5,
      credit: 0,
    );

    await database.addEntryToSavedSnapshot(
      entryId: entryId,
      savedAt: savedAt,
      dailyLogPageNo: '7',
    );
    await database.recalculateAllSnapshots();

    final snapshots = await database.getSummarySnapshots();
    expect(snapshots, hasLength(2));
    final targetSnapshot = snapshots.singleWhere(
      (row) => row['savedAt'] == savedAt,
    );
    final laterSnapshot = snapshots.singleWhere(
      (row) => row['savedAt'] == nextSavedAt,
    );
    expect(targetSnapshot['overallDebit'], 42.5);
    expect(targetSnapshot['customerCount'], 1);
    expect(laterSnapshot['overallDebit'], 42.5);
    expect(laterSnapshot['customerCount'], 0);

    final entries = await database.getEntriesWithCustomerRangePaged(
      startDate: null,
      endDate: savedAt,
      limit: 20,
      offset: 0,
    );
    expect(entries, hasLength(1));
    final laterIntervalEntries = await database.getEntriesWithCustomerRangePaged(
      startDate: savedAt,
      endDate: nextSavedAt,
      limit: 20,
      offset: 0,
    );
    expect(laterIntervalEntries, isEmpty);
    expect(entries.single['createdAt'], savedAt);
    expect(entries.single['dailyLogPageNo'], '7');

    final customerTotals = await database.getCustomerEntryTotalsSince();
    expect(customerTotals.single['latestPageNo'], '3');
  });
}
