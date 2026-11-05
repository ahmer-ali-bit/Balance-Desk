import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shop/database/app_database.dart';
import 'package:shop/providers/customer_provider.dart';
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

  // --- Sync signal ---------------------------------------------------------
  //
  // The sync engine pushes a device's work to the cloud only when the database
  // says something changed. These cases pin the two halves of that contract: a
  // real edit must raise the signal, and a change that arrived *from* the cloud
  // must not raise it (or a pull would bounce straight back out again).

  test('adding a customer raises a sync signal', () async {
    final signals = _recordSyncSignals();

    await AppDatabase.instance.addCustomer('Ali Traders');
    await _settle();

    expect(signals, isNotEmpty);
  });

  test('deleting a customer raises a sync signal and leaves a tombstone', () async {
    final int id = await AppDatabase.instance.addCustomer('Ali Traders');
    await _settle();
    final signals = _recordSyncSignals();

    await AppDatabase.instance.deleteCustomer(id);
    await _settle();

    expect(
      signals,
      isNotEmpty,
      reason: 'a delete must wake the push, otherwise no other device ever '
          'learns the record is gone',
    );

    final db = await AppDatabase.instance.database;
    final tombstones = await db.rawQuery(
      'SELECT entity, syncId FROM sync_tombstones WHERE entity = ?',
      <Object?>['customers'],
    );
    expect(tombstones.length, 1);
  });

  test('sync bookkeeping does not raise a sync signal', () async {
    final signals = _recordSyncSignals();

    await DatabaseHelper.instance.setSyncState('sync.cursor.customers', 'abc');
    await DatabaseHelper.instance.setSyncState('linked.role', 'guest');
    await _settle();

    expect(
      signals,
      isEmpty,
      reason: 'a sync cycle writing its own cursors must not queue another '
          'cycle',
    );
  });

  test('applying a remote record does not raise a sync signal', () async {
    await AppDatabase.instance.addCustomer('Local Only');
    await _settle();
    final signals = _recordSyncSignals();

    await DatabaseHelper.instance.runAsRemoteApply(() async {
      await DatabaseHelper.instance.applyRemoteRow(
        table: 'customers',
        syncId: 'remote-1',
        values: <String, Object?>{
          'name': 'From Cloud',
          'address': '',
          'phone': '',
          'ledgerYear': DateTime.now().year,
          'isStockLedger': 0,
          'useWeight': 0,
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
      );
    });
    await _settle();

    expect(
      signals,
      isEmpty,
      reason: 'a record pulled from the cloud is already on the cloud',
    );

    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT name FROM customers WHERE syncId = ?',
      <Object?>['remote-1'],
    );
    expect(rows.length, 1);
  });
}

/// Collects every sync signal raised from now on.
List<void> _recordSyncSignals() {
  final List<void> signals = <void>[];
  AppDatabase.instance.onDataChanged.listen((_) => signals.add(null));
  return signals;
}

/// Gives the broadcast stream a turn to deliver.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));
