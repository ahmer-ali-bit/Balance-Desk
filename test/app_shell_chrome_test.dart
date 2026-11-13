import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop/theme/balance_desk_theme.dart';
import 'package:shop/widgets/app_shell_chrome.dart';

const List<ShellNavEntry> _entries = <ShellNavEntry>[
  ShellNavEntry(
    label: 'Customers',
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt,
    description: 'Accounts, balances and statements',
  ),
  ShellNavEntry(
    label: 'Summary',
    icon: Icons.assessment_outlined,
    selectedIcon: Icons.assessment,
    description: 'Your ledger year at a glance',
  ),
  ShellNavEntry(
    label: 'Daily Logs',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    description: 'Daily snapshot history',
  ),
];

List<ShellToolEntry> _tools(void Function(String) onTap) {
  return <ShellToolEntry>[
    ShellToolEntry(
      icon: Icons.business_outlined,
      label: 'Company Profile',
      onTap: () => onTap('company'),
    ),
    ShellToolEntry(
      icon: Icons.edit_note_outlined,
      label: 'Notes',
      badge: true,
      onTap: () => onTap('notes'),
    ),
    ShellToolEntry(
      icon: Icons.backup_rounded,
      label: 'Backup & Restore',
      onTap: () => onTap('backup'),
    ),
    ShellToolEntry(
      icon: Icons.lock_outline_rounded,
      label: 'Set App PIN',
      onTap: () => onTap('pin'),
    ),
    ShellToolEntry(
      icon: Icons.system_update_alt_outlined,
      label: 'Check for Update',
      onTap: () => onTap('update'),
    ),
  ];
}

Widget _harness({
  required Widget child,
  Size size = const Size(1440, 900),
}) {
  return MaterialApp(
    theme: BalanceDeskTheme.desktopTheme(),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: child),
    ),
  );
}

Widget _sidebar({int selected = 0, void Function(String)? onTap}) {
  return AppShellSidebar(
    companyName: 'Ahmer Traders',
    subtitle: 'Accounting command center',
    logo: null,
    yearControl: Row(
      children: <Widget>[
        const Expanded(
          child: ShellSelectField(
            icon: Icons.calendar_month_outlined,
            value: '2026',
          ),
        ),
        const SizedBox(width: 6),
        ShellIconAction(
          icon: Icons.add_rounded,
          tooltip: 'Add year',
          onPressed: () {},
        ),
        const SizedBox(width: 6),
        ShellIconAction(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Delete year',
          destructive: true,
          onPressed: () {},
        ),
      ],
    ),
    workspaceControl: Row(
      children: <Widget>[
        const Expanded(
          child: ShellSelectField(
            icon: Icons.workspaces_outlined,
            value: 'Main Shop',
          ),
        ),
        const SizedBox(width: 6),
        ShellIconAction(
          icon: Icons.add_rounded,
          tooltip: 'Add Workspace',
          onPressed: () {},
        ),
      ],
    ),
    navEntries: _entries,
    selectedIndex: selected,
    onSelectIndex: (int _) {},
    tools: _tools(onTap ?? (String _) {}),
    showNavEntries: true,
  );
}

void main() {
  const List<Size> desktopSizes = <Size>[
    Size(1920, 1080),
    Size(1440, 900),
    Size(1280, 800),
    Size(1024, 720),
    Size(1024, 620),
  ];

  for (final Size size in desktopSizes) {
    testWidgets('desktop chrome lays out at ${size.width}x${size.height} '
        'without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          size: size,
          child: AppShellBackdrop(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: ShellMetrics.sidebarWidth,
                    child: _sidebar(),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const ShellPageHeader(
                          eyebrow: 'Balance Desk',
                          title: 'Customers',
                          subtitle: 'Accounts, balances and statements',
                          trailing: ShellChip(
                            icon: Icons.calendar_month_outlined,
                            label: 'FY 2026',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: ShellContentSheet(
                            child: Container(color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('every sidebar action is reachable', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final List<String> tapped = <String>[];

    await tester.pumpWidget(
      _harness(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: ShellMetrics.sidebarWidth,
            child: _sidebar(onTap: tapped.add),
          ),
        ),
      ),
    );

    for (final String label in <String>['Customers', 'Summary', 'Daily Logs']) {
      expect(find.text(label), findsOneWidget);
    }

    const Map<String, String> tools = <String, String>{
      'Company Profile': 'company',
      'Notes': 'notes',
      'Backup & Restore': 'backup',
      'Set App PIN': 'pin',
      'Check for Update': 'update',
    };

    for (final MapEntry<String, String> tool in tools.entries) {
      await tester.tap(find.text(tool.key));
      await tester.pump();
      expect(tapped, contains(tool.value), reason: '${tool.key} must stay wired');
    }

    expect(find.text('2026'), findsOneWidget);
    expect(find.byTooltip('Add year'), findsOneWidget);
    expect(find.byTooltip('Delete year'), findsOneWidget);
    expect(find.text('Main Shop'), findsOneWidget);
    expect(find.byTooltip('Add Workspace'), findsOneWidget);
  });

  testWidgets('mobile dock lays out on a phone viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        size: const Size(390, 844),
        child: AppShellBackdrop(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: ShellMobileHeader(
                  onMenu: () {},
                  companyName: 'Ahmer Traders',
                  title: 'Customers',
                  icon: Icons.people_alt,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: ShellContentSheet(
                    radius: 20,
                    child: Container(color: Colors.black),
                  ),
                ),
              ),
              ShellMobileDock(
                entries: _entries,
                selectedIndex: 0,
                onSelected: (int _) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // Page title plus the dock label.
    expect(find.text('Customers'), findsNWidgets(2));
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Daily Logs'), findsOneWidget);
  });
}
