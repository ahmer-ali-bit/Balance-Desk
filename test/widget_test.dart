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
import 'package:shop/widgets/summary_stat_card.dart';
import 'package:shop/widgets/harbor_navigation.dart';
import 'package:shop/utils/number_format_utils.dart';
import 'package:shop/utils/platform_helper.dart';
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

  test('macOS desktop routes avoid composited slide transitions', () {
    final transitions = BalanceDeskTheme.desktopTheme().pageTransitionsTheme;
    final mac = transitions.builders[TargetPlatform.macOS]!;
    expect(mac.transitionDuration, Duration.zero);
    expect(mac.reverseTransitionDuration, Duration.zero);
    expect(
      transitions.builders[TargetPlatform.windows].runtimeType,
      const PageTransitionsTheme().builders[TargetPlatform.windows].runtimeType,
    );
    expect(
      transitions.builders[TargetPlatform.iOS].runtimeType,
      const PageTransitionsTheme().builders[TargetPlatform.iOS].runtimeType,
    );
  });

  testWidgets('macOS page navigation completes without a sliding overlap', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: BalanceDeskTheme.desktopTheme().copyWith(platform: TargetPlatform.macOS),
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Destination page')),
          )),
          child: const Text('Open page'),
        ),
      )),
    ));
    await tester.tap(find.text('Open page'));
    await tester.pump();
    expect(find.text('Destination page'), findsOneWidget);
    expect(find.text('Open page'), findsNothing);
    Navigator.of(tester.element(find.text('Destination page'))).pop();
    await tester.pump();
    expect(find.text('Open page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary amounts stay legible in the light theme', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: BalanceDeskTheme.desktopTheme(),
      home: const Scaffold(body: SummaryStatCard(
        label: 'Total Debit',
        value: '12,500',
        backgroundColor: Colors.green,
        labelColor: Colors.white,
      )),
    ));
    expect(tester.widget<Text>(find.text('12,500')).style?.color, isNot(Colors.white));
    expect(tester.takeException(), isNull);
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

  testWidgets('Harbor navigation remains usable at phone widths', (tester) async {
    var selected = -1;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: BalanceDeskTheme.lightTheme(),
      home: Scaffold(body: Column(children: <Widget>[
        HarborNavigationBar(
          selectedIndex: 0,
          includeBackup: false,
          onSelected: (index) => selected = index,
        ),
      ])),
    ));
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Daily Logs'), findsOneWidget);
    await tester.tap(find.text('Summary'));
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Harbor ledger keeps actions and lazily builds long lists', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final customerProvider = CustomerProvider();
    late final Customer customer;
    await tester.runAsync(() async {
      customer = (await customerProvider.addCustomerAndReturn('Long Ledger'))!;
      await customerProvider.addCustomerAndReturn('Other Customer');
      await customerProvider.loadCustomers();
      final db = await AppDatabase.instance.database;
      final batch = db.batch();
      for (var i = 0; i < 200; i++) {
        batch.insert('entries', <String, Object?>{
          'customerId': customer.id,
          'entryDate': '2026-01-01',
          'createdAt': DateTime(2026, 1, 1).add(Duration(seconds: i)).toIso8601String(),
          'pageNo': '$i',
          'description': 'Entry $i',
          'debit': 1.0,
          'credit': 0.0,
          'buyBags': 0,
          'sellBags': 0,
        });
      }
      await batch.commit(noResult: true);
      await AppDatabase.instance.setCustomerLedgerOpeningBalance(
        customerId: customer.id!, debit: 25, credit: 0,
      );
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider<CustomerProvider>.value(
        value: customerProvider,
        child: MaterialApp(
          theme: BalanceDeskTheme.desktopTheme(),
          home: LedgerScreen(customer: customer, autoOpenAddEntry: false),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('harbor-ledger-scroll')), findsOneWidget);
      expect(find.text('Entry 199'), findsOneWidget);
      expect(find.text('Entry 0'), findsNothing); // off-screen rows are not built
      expect(find.text('225 D'), findsWidgets); // includes opening balance
      expect(find.byTooltip('Entry Options'), findsWidgets);
      final scrollBefore = tester.widget<CustomScrollView>(
        find.byKey(const ValueKey<String>('harbor-ledger-scroll')),
      );
      await tester.enterText(find.byType(TextField).first, 'Other');
      await tester.pump();
      expect(find.text('Other Customer'), findsOneWidget);
      expect(identical(scrollBefore, tester.widget<CustomScrollView>(
        find.byKey(const ValueKey<String>('harbor-ledger-scroll')),
      )), isTrue); // directory search doesn't rebuild the ledger
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tester.tap(find.byTooltip('Entry Options').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Edit Entry'), findsOneWidget);
      expect(find.text('Transfer to another customer'), findsOneWidget);
      Navigator.of(tester.element(find.text('Edit Entry'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        find.text('Entry 0'), 1200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey<String>('harbor-ledger-scroll')),
          matching: find.byType(Scrollable),
        ),
        maxScrolls: 100,
      );
      expect(find.text('Entry 0'), findsOneWidget);
      expect(find.text('26 D'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    customerProvider.dispose();
  });

  testWidgets('mobile ledger keeps navigation and action menu at phone widths', (tester) async {
    PlatformHelper.debugDesktopOverride = false;
    addTearDown(() => PlatformHelper.debugDesktopOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final customerProvider = CustomerProvider();
    late final Customer customer;
    await tester.runAsync(() async {
      customer = (await customerProvider.addCustomerAndReturn('Phone Customer'))!;
      await AppDatabase.instance.addEntry(
        customerId: customer.id!, entryDate: '2026-01-01',
        createdAt: '2026-01-01T10:00:00', pageNo: '9',
        description: 'Phone Entry', debit: 50, credit: 0,
      );
      await customerProvider.loadCustomers();
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider<CustomerProvider>.value(
        value: customerProvider,
        child: MaterialApp(theme: BalanceDeskTheme.lightTheme(),
          home: LedgerScreen(customer: customer, autoOpenAddEntry: false,
            onNavigate: (_) {})),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Daily Logs'), findsOneWidget);
      expect(find.text('Add Entry'), findsWidgets);
      expect(find.byTooltip('Refresh ledger'), findsOneWidget);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
      expect(find.text('Edit Customer'), findsOneWidget);
      expect(find.text('Menu'), findsOneWidget);
      Navigator.of(tester.element(find.text('Export'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    customerProvider.dispose();
  });

  testWidgets('ledger navigation returns to the requested shell destination', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final customerProvider = CustomerProvider();
    late final Customer customer;
    var selected = -1;
    await tester.runAsync(() async {
      customer = (await customerProvider.addCustomerAndReturn('Navigation Customer'))!;
      await customerProvider.loadCustomers();
      await tester.pumpWidget(ChangeNotifierProvider<CustomerProvider>.value(
        value: customerProvider,
        child: MaterialApp(theme: BalanceDeskTheme.desktopTheme().copyWith(platform: TargetPlatform.macOS),
          home: HarborNavigationScope(
            onNavigate: (index) => selected = index,
            child: Builder(builder: (context) => Scaffold(
              body: TextButton(onPressed: () {
                final navigate = HarborNavigationScope.maybeOf(context);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                  LedgerScreen(customer: customer, autoOpenAddEntry: false, onNavigate: navigate)));
              }, child: const Text('Open ledger')),
            )),
          ),
        ),
      ));
      await tester.tap(find.text('Open ledger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.tap(find.text('Summary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(selected, 1);
      expect(find.text('Open ledger'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    customerProvider.dispose();
  });

  testWidgets('Harbor stock ledger preserves quantity and balance display', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final customerProvider = CustomerProvider();
    late final Customer customer;
    await tester.runAsync(() async {
      customer = (await customerProvider.addCustomerAndReturn('Stock Customer'))!;
      final db = AppDatabase.instance;
      await db.updateCustomerStockMode(customer.id!, true);
      await db.addStockEntry(customerId: customer.id!, entryDate: '2026-01-01',
        createdAt: '2026-01-01T09:00:00', pageNo: '1', description: 'Stock purchase',
        buyBags: '10', buyAmount: 100, sellBags: '', sellAmount: 0);
      await db.addStockEntry(customerId: customer.id!, entryDate: '2026-01-02',
        createdAt: '2026-01-02T09:00:00', pageNo: '2', description: 'Stock sale',
        buyBags: '', buyAmount: 0, sellBags: '4', sellAmount: 40);
      await customerProvider.loadCustomers();
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider<CustomerProvider>.value(
        value: customerProvider,
        child: MaterialApp(theme: BalanceDeskTheme.desktopTheme(),
          home: LedgerScreen(customer: customer, autoOpenAddEntry: false)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Stock sale'), findsOneWidget);
      expect(find.text('Buy Bags'), findsWidgets);
      expect(find.text('Sell Bags'), findsWidgets);
      expect(find.text('Remaining Bags'), findsWidgets);
      expect(find.text('60 C'), findsWidgets);
      expect(find.text('6'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    customerProvider.dispose();
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
