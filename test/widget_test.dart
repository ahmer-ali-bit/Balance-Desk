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
}
