import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shop/database/app_database.dart';
import 'package:shop/main.dart' show ShopDesktopApp;
import 'package:shop/models/customer.dart';
import 'package:shop/providers/customer_provider.dart';
import 'package:shop/screens/customer_list_screen.dart';
import 'package:shop/screens/ledger_screen.dart';
import 'package:shop/theme/balance_desk_theme.dart';
import 'package:shop/utils/number_format_utils.dart';
import 'package:intl/intl.dart';

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.directory);

  final String directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testDirectory;
  late PathProviderPlatform previousPathProvider;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('balance_desk_test_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(testDirectory.path);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await AppDatabase.instance.close();
    await AppDatabase.instance.initialize();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    PathProviderPlatform.instance = previousPathProvider;
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
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

  test('desktop and mobile themes use the same readable light palette', () {
    expect(BalanceDeskTheme.desktopTheme().brightness, Brightness.light);
    expect(BalanceDeskTheme.lightTheme().brightness, Brightness.light);
    expect(
      BalanceDeskTheme.desktopTheme().colorScheme.primary,
      BalanceDeskTheme.lightTheme().colorScheme.primary,
    );
  });

  testWidgets('desktop ledger keeps the customer directory and actions', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = CustomerProvider();
    late final Customer first;
    await tester.runAsync(() async {
      first = (await provider.addCustomerAndReturn('Ali Traders'))!;
      await provider.addCustomerAndReturn('Beta Traders');
      await provider.loadCustomers();
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<CustomerProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: BalanceDeskTheme.desktopTheme(),
            home: LedgerScreen(customer: first, autoOpenAddEntry: false),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Beta Traders'), findsOneWidget);
      expect(find.byTooltip('Add customer'), findsOneWidget);
      expect(find.text('Refresh'), findsWidgets);
      expect(find.text('Export'), findsWidgets);
      expect(find.text('Print'), findsWidgets);
      expect(find.text('Menu'), findsWidgets);
      expect(find.text('Add Entry'), findsWidgets);

      await tester.tap(find.text('Beta Traders'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Beta Traders Ledger'), findsOneWidget);
      expect(find.text('Save Entry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    provider.dispose();
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

  test('application entry point compiles', () {
    expect(const ShopDesktopApp(), isA<ShopDesktopApp>());
  });

  test('batched summary reads match individual ledger reads', () async {
    final db = AppDatabase.instance;
    final first = await db.addCustomer('Alpha');
    final second = await db.addCustomer('Beta');
    await db.setCustomerLedgerOpeningBalance(
      customerId: first,
      debit: 125.5,
      credit: 23,
      buyBags: 4.5,
      sellBags: 2,
    );
    await db.addEntry(
      customerId: first,
      entryDate: '2026-01-01',
      createdAt: '2026-01-01T09:00:00',
      pageNo: 'old',
      description: 'first',
      debit: 120,
      credit: 10,
    );
    await db.addEntry(
      customerId: first,
      entryDate: '2026-01-02',
      createdAt: '2026-01-02T09:00:00',
      pageNo: 'new',
      description: 'second',
      debit: 0,
      credit: 45,
    );
    await db.addEntry(
      customerId: second,
      entryDate: '2026-01-01',
      createdAt: '2026-01-01T09:00:00',
      pageNo: 'other',
      description: 'other',
      debit: 3,
      credit: 1,
    );

    final grouped = await db.getEntriesForActiveYearGrouped();
    for (final id in [first, second]) {
      expect(
        grouped.where((row) => row['customerId'] == id).toList(),
        await db.getEntriesByCustomer(id),
      );
    }
    final opening = (await db.getCustomerLedgerOpeningBalance(first))!;
    final allOpenings = await db.getCustomerLedgerOpeningBalances();
    expect(allOpenings[first]!.debit, opening.debit);
    expect(allOpenings[first]!.credit, opening.credit);
    expect(allOpenings[first]!.buyBags, opening.buyBags);
    expect(allOpenings[first]!.sellBags, opening.sellBags);
    expect(allOpenings.containsKey(second), isFalse);
  });

  test('cached number formats preserve original formatting', () {
    for (final amount in <double>[0, 1, -17, 1234567, 2.5, -1834.24]) {
      final original = NumberFormat('#,##,##0.##', 'en_IN');
      final digits = amount == amount.roundToDouble() ? 0 : 2;
      original.minimumFractionDigits = digits;
      original.maximumFractionDigits = digits;
      expect(formatAmount(amount), original.format(amount));
    }
  });

}
